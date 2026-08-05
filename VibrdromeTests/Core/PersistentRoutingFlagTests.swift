import Foundation
import Testing
@testable import Vibrdrome

/// Lane 3D commit A: the routing flag, the session-selection model and the persistent application
/// adapter exist — and change nothing.
///
/// **Flag-Off is the whole safety property of this commit.** The adapter is built, the state model
/// is in place, the toggle is on the Debug screen, and routing still resolves to legacy for
/// everything. Commit B is what makes the flag mean something.
@Suite(.serialized)
@MainActor
struct PersistentRoutingFlagTests {

    private func withFlag(_ enabled: Bool, _ body: () -> Void) {
        let original = PersistentRoutingSetting.isEnabled
        PersistentRoutingSetting.setEnabled(enabled)
        defer { PersistentRoutingSetting.setEnabled(original) }
        body()
    }

    // MARK: - Flag

    /// Off unless someone turns it on, and reading it builds nothing.
    @Test func theFlagDefaultsOffAndReadingItConstructsNothing() {
        UserDefaults.standard.removeObject(forKey: PersistentRoutingSetting.defaultsKey)
        #expect(PersistentRoutingSetting.isEnabled == false,
                "persistent routing must default to Off")

        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        for _ in 0..<50 { _ = PersistentRoutingSetting.isEnabled }
        #expect(router.persistentAssembly == nil, "reading the flag constructed the persistent stack")
        #expect(router.persistentPreparationState == .notConstructed)
        #expect(GaplessDiagnosticsRegistry.current == nil)
    }

    /// Enabling it starts nothing and constructs nothing on its own.
    @Test func enablingTheFlagStartsNothing() {
        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let queueBefore = engine.queue.map(\.id)

        withFlag(true) {
            #expect(PersistentRoutingSetting.isEnabled)
            #expect(engine.isPlaying == playingBefore, "enabling the flag started playback")
            #expect(engine.queue.map(\.id) == queueBefore, "enabling the flag changed the queue")
            #expect(router.persistentAssembly == nil,
                    "enabling the flag constructed the persistent stack")
            #expect(router.selectedBackend == .legacy)
        }
    }

    /// With the flag On, commit A still routes everything to legacy — the flag has no teeth yet.
    @Test func flagOnStillRoutesEverythingToLegacyInCommitA() {
        let adapter = LegacyAudioEngineAdapter()
        let router = ApplicationPlaybackRouter(
            legacy: adapter, persistentBuilder: ProductionPersistentPlaybackAssemblyBuilder())

        withFlag(true) {
            adapter.resetDelegationCounts()
            let playback: any ApplicationPlaybackControlling = router
            playback.seek(to: 9_999)
            playback.applyEffectiveVolume()
            playback.saveQueueLocally()

            #expect(adapter.delegatedCallCounts["seek"] == 1,
                    "an operation escaped the legacy adapter with the flag on")
            #expect(adapter.delegatedCallCounts["applyEffectiveVolume"] == 1)
            #expect(adapter.delegatedCallCounts["saveQueueLocally"] == 1)
            #expect(router.selectedBackend == .legacy,
                    "commit A must not select persistent even with the flag on")
            #expect(router.sessionSelectionState == .idle,
                    "commit A must not drive session selection")
        }
    }

    /// Flipping the flag never moves an existing session. Commit B keeps this true by applying the
    /// value at the next explicit playback request; commit A keeps it true trivially.
    @Test func changingTheFlagDoesNotSwitchTheCurrentSession() {
        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        let stateBefore = router.sessionSelectionState
        withFlag(true) {
            #expect(router.sessionSelectionState == stateBefore,
                    "changing the flag moved the current session's selection")
            #expect(router.selectedBackend == .legacy)
        }
        withFlag(false) {
            #expect(router.sessionSelectionState == stateBefore)
            #expect(router.selectedBackend == .legacy)
        }
    }

    // MARK: - State model

    /// Selection state starts idle and names a backend only once settled.
    @Test func theSelectionStateModelIsWellFormed() {
        #expect(PlaybackSessionSelectionState.idle.backend == nil)
        #expect(PlaybackSessionSelectionState.evaluating.backend == nil)
        #expect(PlaybackSessionSelectionState.preparing.backend == nil)
        #expect(PlaybackSessionSelectionState.legacy(reason: .supportedLocalSource).backend == .legacy)
        #expect(PlaybackSessionSelectionState.persistent(reason: .supportedLocalSource).backend
                == .persistent)
        // A failed routing attempt is legacy-owned: fallback happens before anything is audible.
        #expect(PlaybackSessionSelectionState.failed(reason: .policySelectedLegacy).backend == .legacy)
    }

    /// Routing failure reasons must never carry a credential, URL, header or path.
    @Test func routingFailureReasonsCarryNoSensitiveDetail() {
        for failure in SafePlaybackRoutingFailure.allCases {
            let raw = failure.rawValue
            #expect(raw.contains("/") == false, "\(raw) looks like a path")
            #expect(raw.lowercased().contains("http") == false)
            #expect(raw.lowercased().contains("token") == false)
            #expect(raw.isEmpty == false)
        }
    }

    // MARK: - Persistent adapter

    /// The adapter projects the `Song` view without becoming a second queue authority: position and
    /// playing state are read from the gapless session, never stored.
    @Test func theAdapterProjectsSongsWithoutOwningPosition() throws {
        let router = ApplicationPlaybackRouter(
            legacy: LegacyAudioEngineAdapter(),
            persistentBuilder: ProductionPersistentPlaybackAssemblyBuilder())
        let assembly = try router.preparePersistentBackend()
        let adapter = PersistentApplicationPlaybackAdapter(assembly: assembly)

        let songs = (0..<3).map { index in
            Song(id: "p\(index)", parent: nil, title: "Track \(index)",
                 album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
                 track: nil, year: nil, genre: nil, coverArt: nil,
                 size: nil, contentType: nil, suffix: nil,
                 duration: 180, bitRate: nil, path: nil,
                 discNumber: nil, created: nil, starred: nil, userRating: nil,
                 bpm: nil, replayGain: nil, musicBrainzId: nil)
        }
        adapter.adoptQueue(songs)

        #expect(adapter.queue.map(\.id) == ["p0", "p1", "p2"])
        // Position comes from the gapless session, which has not been given a queue here.
        #expect(adapter.currentIndex == assembly.session.queue.currentIndex,
                "the adapter stored its own position instead of reading the session")
        #expect(adapter.isPlaying == assembly.session.isPlaying)
        #expect(adapter.isTransportActive == false, "constructing the adapter started playback")
    }

    /// Building the adapter is inert — it neither starts the engine nor selects a backend.
    @Test func constructingTheAdapterStartsNothing() throws {
        let router = ApplicationPlaybackRouter(
            legacy: LegacyAudioEngineAdapter(),
            persistentBuilder: ProductionPersistentPlaybackAssemblyBuilder())
        let assembly = try router.preparePersistentBackend()

        let adapter = PersistentApplicationPlaybackAdapter(assembly: assembly)
        #expect(adapter.isTransportActive == false)
        #expect(assembly.backend.engine.engine.isRunning == false,
                "constructing the adapter started the persistent engine")
        #expect(assembly.backend.engine.player.isPlaying == false)
        #expect(assembly.diagnostics.bufferPoolAllocated == false,
                "constructing the adapter allocated the buffer pool")
        #expect(router.selectedBackend == .legacy)
        #expect(adapter.delegatedCallCounts.isEmpty,
                "constructing the adapter delegated \(adapter.delegatedCallCounts)")
    }
}
