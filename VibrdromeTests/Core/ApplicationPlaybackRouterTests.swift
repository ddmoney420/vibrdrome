import AVFoundation
import Foundation
import Observation
import Testing
@testable import Vibrdrome

/// Lane 3A: `ApplicationPlayback.shared` is now an `ApplicationPlaybackRouter` that routes every
/// operation to the legacy adapter.
///
/// **Zero behaviour change is the whole point**, so most of this suite is about what the new layer
/// must *not* have done: not become a second source of truth, not break Observation, not duplicate a
/// delegation, not construct anything, and not quietly select an engine that does not exist.
///
/// **Why a router instead of swapping what `shared` returns.** Lane 2 moved 170 call sites across
/// eight surfaces onto `ApplicationPlayback.shared`, and those surfaces hold it. If its identity
/// could change under them the app would end up with two queue authorities and no way to tell which
/// one the user is looking at. So the authority is stable and the decision lives inside it.
@Suite(.serialized)
@MainActor
struct ApplicationPlaybackRouterTests {

    private func makeSong(id: String, title: String = "Probe") -> Song {
        Song(
            id: id, parent: nil, title: title,
            album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
            track: nil, year: nil, genre: nil, coverArt: nil,
            size: nil, contentType: nil, suffix: nil,
            duration: 180, bitRate: nil, path: nil,
            discNumber: nil, created: nil, starred: nil, userRating: nil,
            bpm: nil, replayGain: nil, musicBrainzId: nil
        )
    }

    private func makeClient() -> SubsonicClient {
        SubsonicClient(
            baseURL: URL(string: "https://example.invalid")!,
            username: "probe", password: "probe"
        )
    }

    /// Records whether Observation fired, from the `@Sendable` `onChange` closure.
    private final class ObservationProbe: @unchecked Sendable {
        var fired = false
    }

    // MARK: - Composition

    /// The composition point resolves to the router, once, for the process lifetime.
    @Test func compositionResolvesToOneStableRouter() {
        guard let router = ApplicationPlayback.router else {
            Issue.record("ApplicationPlayback.shared is not an ApplicationPlaybackRouter")
            return
        }

        for _ in 0..<50 {
            #expect(ApplicationPlayback.shared === router,
                    "resolving the composition point produced a second router")
            #expect(ApplicationPlayback.router === router)
        }
    }

    /// The router owns one legacy adapter, and that adapter is what reaches `AudioEngine.shared`.
    @Test func routerHoldsOneLegacyAdapterThatReachesTheEngine() {
        guard let router = ApplicationPlayback.router,
              let adapter = ApplicationPlayback.legacyAdapter else {
            Issue.record("the router or its legacy adapter is missing")
            return
        }
        for _ in 0..<50 {
            #expect(router.legacyAdapterForTesting === adapter,
                    "the router produced a second legacy adapter")
        }

        // The adapter reads the same singleton the rest of the app still uses directly.
        let engine = AudioEngine.shared
        let original = engine.playingFromContext
        defer { engine.playingFromContext = original }

        engine.playingFromContext = "router-probe"
        #expect(adapter.playingFromContext == "router-probe",
                "the legacy adapter is not reading AudioEngine.shared")
        #expect(ApplicationPlayback.shared.playingFromContext == "router-probe",
                "the router is not reading through to AudioEngine.shared")
    }

    /// Nothing in production constructs the persistent controller.
    @Test func noProductionObjectConstructsThePersistentController() {
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "a persistent playback controller exists in production")
        _ = ApplicationPlayback.shared
        _ = ApplicationPlayback.router
        _ = ApplicationPlayback.legacyAdapter
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "resolving the router constructed a persistent playback controller")
    }

    // MARK: - Backend selection

    /// `.legacy` is the only reachable runtime value, and `.persistent` exists in name only.
    @Test func theOnlySelectableBackendIsLegacy() {
        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        #expect(router.selectedBackend == .legacy,
                "the router selected \(router.selectedBackend) — Lane 3A must always select legacy")

        // Resolving repeatedly, and driving operations, must not move the decision.
        for _ in 0..<50 {
            _ = ApplicationPlayback.shared.currentSong
            #expect(router.selectedBackend == .legacy)
        }
        #expect(PlaybackBackend.allCases == [.legacy, .persistent],
                "the backend model changed shape")
    }

    // MARK: - Stable seams

    /// Every one of the eight application seams resolves the same router and observes the same
    /// decision. This is the Lane 2 identity invariant, extended to the routing decision.
    @Test func everySeamResolvesTheSameRouterAndDecision() {
        #expect(RemoteCommandManager.shared.playbackOverride == nil)
        #expect(CarPlayPlaybackActions.playbackOverride == nil)
        #expect(CarPlayScenePlaybackActions.playbackOverride == nil)
        #expect(WatchPlaybackActions.playbackOverride == nil)
        #expect(AppIntentPlaybackActions.playbackOverride == nil)
        #expect(AppCommandPlaybackActions.playbackOverride == nil)
        #expect(ScenePlaybackLifecycleActions.playbackOverride == nil)

        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }

        let seams: [(name: String, resolved: any ApplicationPlaybackControlling)] = [
            ("views / composition point", ApplicationPlayback.shared),
            ("CarPlayPlaybackActions", CarPlayPlaybackActions.playback),
            ("CarPlayScenePlaybackActions", CarPlayScenePlaybackActions.playback),
            ("WatchPlaybackActions", WatchPlaybackActions.playback),
            ("AppIntentPlaybackActions", AppIntentPlaybackActions.playback),
            ("AppCommandPlaybackActions", AppCommandPlaybackActions.playback),
            ("ScenePlaybackLifecycleActions", ScenePlaybackLifecycleActions.playback)
        ]

        for seam in seams {
            #expect(seam.resolved === router,
                    "\(seam.name) resolved a different playback authority than the router")
        }
        #expect(router.selectedBackend == .legacy, "the shared decision is not legacy")

        // Rebuilding views must not produce another router.
        for _ in 0..<25 {
            _ = ContentView()
            #expect(ApplicationPlayback.shared === router)
        }
    }

    // MARK: - Delegation, exactly once

    /// One application operation produces exactly one legacy-adapter operation through the router.
    /// Every member here is a guarded no-op or a restorable flag in the engine, so nothing audible
    /// happens; the transport members that would start AVQueuePlayer are covered by the seam suites
    /// against recorders.
    @Test func representativeOperationsDelegateExactlyOnceThroughTheRouter() {
        guard let adapter = ApplicationPlayback.legacyAdapter else {
            Issue.record("no legacy adapter")
            return
        }
        let engine = AudioEngine.shared
        let playback = ApplicationPlayback.shared

        let shuffleBefore = engine.shuffleEnabled
        let repeatBefore = engine.repeatMode
        let eqBefore = engine.eqEnabled
        let volumeBefore = engine.userVolume
        let queueBefore = engine.queue.map(\.id)
        let indexBefore = engine.currentIndex
        let playingBefore = engine.isPlaying
        defer {
            if engine.shuffleEnabled != shuffleBefore { engine.toggleShuffle() }
            while engine.repeatMode != repeatBefore { engine.cycleRepeatMode() }
            engine.applyEQToggle(enabled: eqBefore)
            engine.userVolume = volumeBefore
        }

        adapter.resetDelegationCounts()

        playback.seek(to: 12_345)                                   // guarded no-op when idle
        playback.skipToIndex(Int.max)                               // out of range
        playback.removeFromQueue(atAbsolute: Int.max)               // out of range
        playback.moveInUpNext(from: IndexSet(), to: 0)              // empty move
        playback.updateQueueSongStarred(id: "router-absent", starred: true)
        playback.updateQueueSongRating(id: "router-absent", rating: 5)
        playback.toggleShuffle()
        playback.cycleRepeatMode()
        playback.applyEQToggle(enabled: !eqBefore)
        playback.applyEffectiveVolume()
        playback.saveQueueLocally()
        playback.restorePlayQueue(client: makeClient())

        let counts = adapter.delegatedCallCounts
        for member in ["seek", "skipToIndex", "removeFromQueue", "moveInUpNext",
                       "updateQueueSongStarred", "updateQueueSongRating", "toggleShuffle",
                       "cycleRepeatMode", "applyEQToggle", "applyEffectiveVolume",
                       "saveQueueLocally", "restorePlayQueue"] {
            #expect(counts[member] == 1,
                    "\(member) produced \(counts[member] ?? 0) adapter calls through the router")
        }
        // Nothing was invoked that was not asked for.
        #expect(counts["play"] == nil, "the router invoked play unprompted")
        #expect(counts["pause"] == nil)
        #expect(counts["stop"] == nil)
        #expect(counts["next"] == nil)

        #expect(engine.queue.map(\.id) == queueBefore, "a delegated no-op changed the queue")
        #expect(engine.currentIndex == indexBefore)
        #expect(engine.isPlaying == playingBefore, "a delegated operation started playback")
        adapter.resetDelegationCounts()
    }

    /// The router must reach the engine **only** through the adapter. If any member bypassed it,
    /// engine state would move while the adapter's counter stayed at zero.
    @Test func theRouterNeverBypassesTheLegacyAdapter() {
        guard let adapter = ApplicationPlayback.legacyAdapter else {
            Issue.record("no legacy adapter")
            return
        }
        let engine = AudioEngine.shared
        let shuffleBefore = engine.shuffleEnabled
        defer { if engine.shuffleEnabled != shuffleBefore { engine.toggleShuffle() } }

        adapter.resetDelegationCounts()
        ApplicationPlayback.shared.toggleShuffle()

        #expect(engine.shuffleEnabled != shuffleBefore, "the operation never reached the engine")
        #expect(adapter.delegatedCallCounts["toggleShuffle"] == 1,
                "engine state moved without the adapter counting it — the router bypassed the adapter")
        adapter.resetDelegationCounts()
    }

    /// Writes through the router reach the engine once, and reads come straight back.
    @Test func stateWritesReachTheEngineThroughTheRouter() {
        let engine = AudioEngine.shared
        let volumeBefore = engine.userVolume
        let contextBefore = engine.playingFromContext
        let visualizerBefore = engine.visualizerActive
        defer {
            engine.userVolume = volumeBefore
            engine.playingFromContext = contextBefore
            engine.visualizerActive = visualizerBefore
        }

        ApplicationPlayback.shared.userVolume = 0.33
        #expect(abs(engine.userVolume - 0.33) < 0.0001, "a router volume write missed the engine")

        ApplicationPlayback.shared.playingFromContext = "router write"
        #expect(engine.playingFromContext == "router write")

        ApplicationPlayback.shared.visualizerActive = !visualizerBefore
        #expect(engine.visualizerActive == !visualizerBefore)

        // Clamping still belongs to the engine, unchanged by the extra layer.
        ApplicationPlayback.shared.volume = 4
        #expect(engine.userVolume == 1.0, "the engine stopped clamping through the router")
    }

    /// The whole capability surface reads through — no member is stale or mirrored.
    @Test func everyCapabilityReadsThroughToTheEngine() {
        let engine = AudioEngine.shared
        let playback = ApplicationPlayback.shared

        #expect(playback.isPlaying == engine.isPlaying)
        #expect(playback.currentSong?.id == engine.currentSong?.id)
        #expect(playback.currentTime == engine.currentTime)
        #expect(playback.smoothCurrentTime == engine.smoothCurrentTime)
        #expect(playback.isBuffering == engine.isBuffering)
        #expect(playback.duration == engine.duration)
        #expect(playback.effectiveDuration == engine.effectiveDuration)
        #expect(playback.queue.count == engine.queue.count)
        #expect(playback.currentIndex == engine.currentIndex)
        #expect(playback.upNext.count == engine.upNext.count)
        #expect(playback.upNextEntries.count == engine.upNextEntries.count)
        #expect(playback.nextSongIndex() == engine.nextSongIndex())
        #expect(playback.shuffleEnabled == engine.shuffleEnabled)
        #expect(playback.repeatMode == engine.repeatMode)
        #expect(playback.isRadioMode == engine.isRadioMode)
        #expect(playback.currentRadioStation?.id == engine.currentRadioStation?.id)
        #expect(playback.radioSeedArtistName == engine.radioSeedArtistName)
        #expect(playback.eqEnabled == engine.eqEnabled)
        #expect(playback.volume == engine.volume)
        #expect(playback.userVolume == engine.userVolume)
        #expect(playback.playbackRate == engine.playbackRate)
        #expect(playback.visualizerActive == engine.visualizerActive)
        #expect(playback.predownloadsPending == engine.predownloadsPending)
        #expect(playback.predownloadSpeed == engine.predownloadSpeed)
        #expect(playback.recentlyPlayed.count == engine.recentlyPlayed.count)
        #expect(playback.playingFromContext == engine.playingFromContext)
    }

    // MARK: - Observation through the extra layer

    /// The load-bearing property: adding a layer must not break SwiftUI invalidation. The router's
    /// members are computed read-throughs, so the access still happens on the `@Observable` engine
    /// inside the caller's tracking scope.
    @Test func observationSurvivesTheRouterLayer() {
        let engine = AudioEngine.shared
        let originalContext = engine.playingFromContext
        let originalVisualizer = engine.visualizerActive
        defer {
            engine.playingFromContext = originalContext
            engine.visualizerActive = originalVisualizer
        }

        let probe = ObservationProbe()
        withObservationTracking {
            _ = ApplicationPlayback.shared.playingFromContext
        } onChange: {
            probe.fired = true
        }

        // Negative control: an unrelated property must not invalidate this scope.
        engine.visualizerActive = !originalVisualizer
        #expect(probe.fired == false,
                "the router over-registered — one read tracked an unrelated property")

        engine.playingFromContext = "router-observation-probe"
        #expect(probe.fired,
                "a read through the router registered no Observation dependency; views would freeze")
    }

    /// Each state family invalidates independently through the router.
    @Test func everyObservedStateFamilyInvalidatesThroughTheRouter() {
        let engine = AudioEngine.shared
        let queueBefore = engine.queue
        let songBefore = engine.currentSong
        let timeBefore = engine.currentTime
        let repeatBefore = engine.repeatMode
        let shuffleBefore = engine.shuffleEnabled
        let volumeBefore = engine.userVolume
        defer {
            engine.queue = queueBefore
            engine.currentSong = songBefore
            engine.currentTime = timeBefore
            while engine.repeatMode != repeatBefore { engine.cycleRepeatMode() }
            if engine.shuffleEnabled != shuffleBefore { engine.toggleShuffle() }
            engine.userVolume = volumeBefore
        }

        let mutations: [(name: String, read: @MainActor () -> Void, mutate: @MainActor () -> Void)] = [
            ("currentSong", { _ = ApplicationPlayback.shared.currentSong },
             { engine.currentSong = self.makeSong(id: "obs-\(Int(engine.currentTime))") }),
            ("queue", { _ = ApplicationPlayback.shared.queue },
             { engine.queue = [self.makeSong(id: "obs-queue")] }),
            ("currentTime", { _ = ApplicationPlayback.shared.currentTime },
             { engine.currentTime += 5 }),
            ("repeatMode", { _ = ApplicationPlayback.shared.repeatMode },
             { engine.cycleRepeatMode() }),
            ("shuffleEnabled", { _ = ApplicationPlayback.shared.shuffleEnabled },
             { engine.toggleShuffle() }),
            ("userVolume", { _ = ApplicationPlayback.shared.userVolume },
             { engine.userVolume = engine.userVolume == 0.5 ? 0.6 : 0.5 })
        ]

        for mutation in mutations {
            let probe = ObservationProbe()
            withObservationTracking { mutation.read() } onChange: { probe.fired = true }
            mutation.mutate()
            #expect(probe.fired,
                    "\(mutation.name) changes no longer invalidate a read through the router")
        }
    }

    // MARK: - Cold construction

    /// Constructing and resolving the router must start nothing and build nothing.
    @Test func routerConstructionStartsNothing() {
        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let queueBefore = engine.queue.map(\.id)
        let indexBefore = engine.currentIndex
        let contextBefore = engine.playingFromContext
        let categoryBefore = AVAudioSession.sharedInstance().category
        let modeBefore = AVAudioSession.sharedInstance().mode
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        guard let adapter = ApplicationPlayback.legacyAdapter else {
            Issue.record("no legacy adapter")
            return
        }
        adapter.resetDelegationCounts()

        // A freshly built router, plus repeated resolution of the shared one.
        for _ in 0..<50 {
            _ = ApplicationPlaybackRouter()
            _ = ApplicationPlayback.shared
        }

        #expect(adapter.delegatedCallCounts.isEmpty,
                "constructing routers delegated \(adapter.delegatedCallCounts)")
        #expect(engine.isPlaying == playingBefore, "constructing the router started playback")
        #expect(engine.queue.map(\.id) == queueBefore,
                "constructing the router restored or changed the queue")
        #expect(engine.currentIndex == indexBefore)
        #expect(engine.playingFromContext == contextBefore,
                "constructing the router published new playback context")
        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "constructing the router changed the audio session category")
        #expect(AVAudioSession.sharedInstance().mode == modeBefore,
                "constructing the router changed the audio session mode")
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore,
                "constructing the router registered remote commands")
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "constructing the router built a persistent playback controller")
        adapter.resetDelegationCounts()
    }

    // MARK: - Diagnostics

    /// The router reports the truth: legacy selected, persistent not constructed. An installed build
    /// must never claim to be running the persistent engine.
    @Test func diagnosticsReportLegacyAndNoPersistentController() {
        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        let diagnostics = router.diagnostics

        #expect(diagnostics.routerActive)
        #expect(diagnostics.selectedBackend == .legacy)
        #expect(diagnostics.legacyAdapterActive)
        #expect(diagnostics.persistentControllerConstructed == false)

        let summary = diagnostics.summary
        #expect(summary.contains("Application playback router: Active"))
        #expect(summary.contains("Selected backend: Legacy"))
        #expect(summary.contains("Legacy adapter: Active"))
        #expect(summary.contains("Persistent controller: Not constructed"))
        #expect(summary.contains("Persistent engine: Active") == false,
                "diagnostics claimed the persistent engine is active")
    }

    /// Lane 3A adds a layer, not an engine.
    @Test func persistentPlaybackRemainsUnwired() {
        #expect(GaplessDiagnosticsRegistry.current == nil)
        #expect(ApplicationPlayback.router?.selectedBackend == .legacy)
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the router lost its legacy adapter")
    }
}
