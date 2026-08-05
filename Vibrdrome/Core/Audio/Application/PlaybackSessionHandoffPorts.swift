import AVFoundation
import Foundation

/// The production legacy side of a handoff.
///
/// Everything except the transport start is the **real** `AudioEngine`: transport state, snapshot
/// capture and quiescence all go straight to it, because those are precisely the behaviours a
/// handoff depends on and a substitute for them would prove nothing. The transport start is reached
/// through `ApplicationPlaybackControlling` so the one step that opens a real `AVQueuePlayer`
/// against a real server is the one step a test can substitute.
@MainActor
final class AudioEngineLegacySessionPort: LegacyPlaybackSessionPort {

    private let engine: AudioEngine
    private let transport: any ApplicationPlaybackControlling

    init(engine: AudioEngine = .shared,
         transport: any ApplicationPlaybackControlling = LegacyAudioEngineAdapter()) {
        self.engine = engine
        self.transport = transport
    }

    var transportState: LegacyTransportState { engine.legacyTransportState }

    func captureSnapshot(startOffsetSeconds: TimeInterval) -> PlaybackSessionSnapshot {
        engine.captureSessionSnapshot(startOffsetSeconds: startOffsetSeconds)
    }

    func quiesceForPersistentSession() { engine.quiesceForPersistentSession() }

    /// Restore the logical session onto the engine. **Starts nothing.**
    ///
    /// Each property is written only when it differs, because these are observed values with
    /// side effects — `userVolume` re-applies the effective volume on every assignment — and an
    /// identity write would publish a change that did not happen.
    func adopt(_ snapshot: PlaybackSessionSnapshot) {
        if engine.repeatMode != snapshot.repeatMode { engine.repeatMode = snapshot.repeatMode }
        if engine.shuffleEnabled != snapshot.shuffleEnabled {
            engine.shuffleEnabled = snapshot.shuffleEnabled
        }
        if engine.playingFromContext != snapshot.playingFromContext {
            engine.playingFromContext = snapshot.playingFromContext
        }
        if engine.userVolume != snapshot.userVolume { engine.userVolume = snapshot.userVolume }
        if engine.eqEnabled != snapshot.eqEnabled {
            transport.applyEQToggle(enabled: snapshot.eqEnabled)
        }
    }

    /// One transport start, from the snapshot rather than from the quiesced player.
    ///
    /// The queue comes from the snapshot because after a handoff the inactive `AVQueuePlayer` holds
    /// no items at all — it is explicitly not the queue authority while ownership is moving.
    ///
    /// **Deliberately no seek.** Resuming mid-track cannot be done by starting and then seeking:
    /// `AudioEngine.play` coalesces the item swap through `scheduleDebouncedPlayerSwap`, which
    /// sleeps 50 ms before calling `replacePlayerItem`, so a seek issued in the same turn would
    /// target the outgoing item — or be dropped outright, since `seek` returns early while
    /// `effectiveDuration` is still zero. The executor therefore refuses a mid-track plan rather
    /// than issuing a seek that silently does nothing; wiring a real resume belongs to the lane
    /// that owns the engine's restore path.
    func start(_ snapshot: PlaybackSessionSnapshot) {
        guard let song = snapshot.currentSong else { return }
        transport.play(song: song, from: snapshot.songs, at: snapshot.currentIndex)
    }
}

/// The production persistent side of a handoff, over the assembly built by Lane 3C.
///
/// Holds `PersistentApplicationPlaybackAdapter` for the `Song` projection and the transport-active
/// read, and reaches the controller directly for the two things the application contract cannot
/// express: an **awaitable** start whose failure is visible (the adapter's fire-and-forget `Task`
/// swallows it, which would make pre-audible fallback undetectable) and the render-observed
/// first-audible callback.
@MainActor
final class PersistentAssemblySessionPort: PersistentPlaybackSessionPort {

    private let assembly: PersistentPlaybackAssembly
    /// The application-facing adapter. Exposed so a test can read its delegation counters.
    let application: PersistentApplicationPlaybackAdapter

    init(assembly: PersistentPlaybackAssembly,
         application: PersistentApplicationPlaybackAdapter? = nil) {
        self.assembly = assembly
        self.application = application ?? PersistentApplicationPlaybackAdapter(assembly: assembly)
    }

    var isTransportActive: Bool { application.isTransportActive }

    /// Adopt the queue being handed over. **Starts nothing**, and schedules nothing.
    ///
    /// Two views of one queue, deliberately: the adapter keeps the `Song` projection that answers
    /// `currentSong`/`queue`, and the gapless session takes the occurrence list it schedules from.
    /// Position is read from the session in both cases, so the projection never becomes a second
    /// queue authority.
    ///
    /// Repeat, shuffle and playback context are **not** transferred here — moving those with the
    /// session belongs to the transport-routing lane, and inventing a transfer now would mean
    /// guessing at how a shuffled legacy order maps onto the persistent session's own ordering.
    func adopt(_ snapshot: PlaybackSessionSnapshot) {
        application.adoptQueue(snapshot.songs)
        assembly.session.replaceQueue(songIDs: snapshot.songs.map(\.id),
                                      startIndex: snapshot.currentIndex)
        // Queue data, not a mode: the session's completion and previous-track policies are measured
        // against track length.
        for song in snapshot.songs {
            guard let duration = song.duration else { continue }
            assembly.session.songDurations[song.id] = TimeInterval(duration)
        }
    }

    func adopt(preparedSource: GaplessPreparedTrack) async {
        await assembly.preparer.adopt(preparedSource)
    }

    func installAudibleObserver(_ observer: @escaping @MainActor () -> Void) {
        assembly.controller.onFirstAudibleSample = observer
    }

    func clearAudibleObserver() {
        assembly.controller.onFirstAudibleSample = nil
    }

    /// The only path that activates the audio session, and the only start in the sequence.
    func start() async throws {
        try await assembly.controller.play()
    }

    /// Tear down whatever transport was brought up. `quiesce()` is the adapter's own idempotent
    /// stop, and the backend's stop is a no-op on a graph that never started.
    ///
    /// The `.failed` case needs the extra step: `GaplessRealTimeBackend.stop()` declines to act
    /// from `.failed`, so a start that got as far as scheduling before refusing would otherwise
    /// leave its segments — and the buffers behind them — on the player node. `resetTail()` is the
    /// one path that drops them irrespective of state, and it touches only structures the failed
    /// start had already built.
    func tearDown() {
        application.quiesce()
        if assembly.backend.state == .failed { assembly.backend.resetTail() }
    }
}
