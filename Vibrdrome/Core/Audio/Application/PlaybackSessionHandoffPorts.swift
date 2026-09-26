import AVFoundation
import Foundation

extension RepeatMode {
    /// The next mode in the user-facing cycle, matching `AudioEngine.cycleRepeatMode`.
    ///
    /// Shared so the two backends cannot cycle in different orders — the button would then do
    /// something different depending on which engine happened to be playing.
    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// A persistent side that exists only so a legacy plan can be executed without building an engine.
///
/// Every member is a no-op **and unreachable**: the executor's legacy path grants legacy authority,
/// adopts and starts legacy, and never calls the persistent port. It is a structural stand-in, not
/// a fallback — if anything here ever ran it would mean a persistent plan was executed against a
/// backend that does not exist.
@MainActor
final class InertPersistentSessionPort: PersistentPlaybackSessionPort, PersistentTransportRouting {
    var transport: any PersistentTransportRouting { self }
    var isTransportActive: Bool { false }
    func adopt(_ snapshot: PlaybackSessionSnapshot) {}
    func adopt(preparedSource: GaplessPreparedTrack) async {}
    func installAudibleObserver(_ observer: @escaping @MainActor () -> Void) {}
    func clearAudibleObserver() {}
    func start(sessionGeneration: UInt64) async throws {}
    func tearDown(preserveAudioSession: Bool) async {}
    func invalidateForMediaServicesReset() {}

    func play(song: Song, from newQueue: [Song]?, at index: Int) {}
    func pause() {}
    func resume() {}
    func stop() {}
    func togglePlayPause() {}
    func next() {}
    func previous() {}
    func seek(to time: TimeInterval) {}
    func skipToIndex(_ index: Int) {}
    func addToQueue(_ song: Song) {}
    func addToQueueNext(_ song: Song) {}
    func removeFromQueue(atAbsolute index: Int) {}
    func moveInUpNext(from source: IndexSet, to destination: Int) {}
    func clearQueue() {}
    func replaceQueue(_ songs: [Song], startIndex: Int) {}
    func setRepeatMode(_ mode: RepeatMode) {}
    func setShuffleEnabled(_ enabled: Bool) {}
    func applyEQToggle(enabled: Bool) {}
    func applyEffectiveVolume() {}
    var visualizerActive: Bool = false
    var volume: Float = 1
    var userVolume: Float = 1
    var eqEnabled: Bool { false }
    var isPlaying: Bool { false }
    var currentSong: Song? { nil }
    var currentTime: TimeInterval { 0 }
    var duration: TimeInterval { 0 }
    var effectiveDuration: TimeInterval { 0 }
    var queue: [Song] { [] }
    var currentIndex: Int { 0 }
    var repeatMode: RepeatMode { .off }
    var shuffleEnabled: Bool { false }
    func nextSongIndex() -> Int? { nil }
    var upNext: [Song] { [] }
    var upNextEntries: [(index: Int, song: Song)] { [] }
    var heartbeatDiagnostics: PersistentHeartbeatDiagnostics { PersistentHeartbeatDiagnostics() }
}

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

    /// The adapter is the transport surface: one object owns both the `Song` projection and the
    /// commands, so the queue the UI reads and the queue the commands act on cannot diverge.
    var transport: any PersistentTransportRouting { application }

    var isTransportActive: Bool { application.isTransportActive }

    /// Adopt the queue being handed over. **Starts nothing**, and schedules nothing.
    ///
    /// Two views of one queue, deliberately: the adapter keeps the `Song` projection that answers
    /// `currentSong`/`queue`, and the gapless session takes the occurrence list it schedules from.
    /// Position is read from the session in both cases, so the projection never becomes a second
    /// queue authority.
    ///
    /// Repeat, shuffle, volume and EQ come across with the session. The queue array is the play
    /// order in both engines and the flags govern how each one picks its own next occurrence, so
    /// mirroring them is a transfer rather than a second shuffle.
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
        assembly.session.setRepeatMode(snapshot.repeatMode)
        assembly.session.setShuffleEnabled(snapshot.shuffleEnabled)
        application.userVolume = snapshot.userVolume
        // Applied before any audio flows, so the initial state costs no ramp; later changes go
        // through `applyEQToggle`, which does ramp.
        assembly.backend.engine.applyEQ(GaplessEQSettings.current())
        assembly.backend.engine.setEQEnabled(snapshot.eqEnabled)
        // Last, so the presentation mirror reflects the session queue that was just installed
        // rather than the empty one it was built against.
        application.refreshObservedState()
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
    ///
    /// The heartbeat begins immediately after the controller's transport start, per the controller
    /// contract: `play()` prepares the graph, fills the tail and starts the node, and only once
    /// there is a running session does driving it mean anything. Starting the heartbeat first would
    /// tick a controller that had not yet scheduled anything.
    func start(sessionGeneration: UInt64) async throws {
        try await assembly.controller.play()
        application.startHeartbeat(sessionGeneration: sessionGeneration)
    }

    /// Tear down whatever transport was brought up, and leave the retained assembly reusable.
    ///
    /// `quiesce()` is the adapter's own idempotent stop, which routes through
    /// `GaplessRealTimeBackend.stop()` — that recovers from `.failed` as well, so a start that got
    /// as far as scheduling before refusing releases its segments, buffers, source files and
    /// converters like any other ended session. `resetAfterFailure()` states that requirement
    /// explicitly and is a no-op once the stop has already done it; it is deliberately not a tail
    /// reset, which cleared the segments but left the backend stuck in `.failed` and therefore
    /// unable to start again on the assembly the process keeps for its whole lifetime.
    ///
    /// The two `settleTransport()` awaits are what make this honest: the backend's `stop()` is a
    /// synchronous façade over an ordered teardown, and this returns only once that teardown — node
    /// stopped, refill drained, recycle reconciled, pool reclaimed, sources closed, backend idle —
    /// has actually completed. A replacement granted before that would be built on a graph the old
    /// session still holds.
    func tearDown(preserveAudioSession: Bool) async {
        // Tell the backend whether this teardown is a handoff (keep the shared session active for the
        // incoming backend) or a genuine stop (deactivate). Set before quiesce(), which is what
        // orders the transport release that consumes it.
        assembly.backend.preserveAudioSessionForReplacement = preserveAudioSession
        application.quiesce()
        await assembly.backend.settleTransport()
        assembly.backend.resetAfterFailure()
        await assembly.backend.settleTransport()
    }

    func invalidateForMediaServicesReset() {
        // Drop the orphaned engine's async work; do NOT operate the dead graph. The router discards
        // this assembly immediately after, so nothing here is reused.
        application.invalidateForMediaServicesReset()
        clearAudibleObserver()
    }
}
