import AVFoundation
import Foundation
import SwiftUI
import Testing
@testable import Vibrdrome

/// Lane 2D-B1: the scene-phase playback calls in `ContentView` and `MacContentView` now go through
/// `ApplicationPlayback.shared`.
///
/// **iOS and macOS save on different phases and are deliberately not merged.** iOS saves on
/// `.background`; macOS saves on `.inactive`, because a Mac window rarely reaches `.background` at
/// all. A single shared handler would have to pick one and would silently stop saving on the other
/// platform — so there are two entry points, each pinned below.
///
/// **The `.onChange` closures stay in the view files** and keep their two-argument
/// `{ _, newPhase in }` form. That arity is the known trap here: rewriting it to a zero- or
/// one-argument closure produces the misleading `(ScenePhase) -> Void expects 1 argument` error.
/// Compiling `ContentView` and `MacContentView` at all is what enforces it, since a wrong arity
/// fails the build rather than a test; what these tests pin is that the *phase mapping* behind it
/// did not move.
///
/// **No real audio and no real backgrounding.** The lifecycle actions are driven directly against an
/// injected recorder.
@Suite(.serialized)
@MainActor
struct ScenePlaybackLifecycleMigrationTests {

    private func makeClient() -> SubsonicClient {
        SubsonicClient(
            baseURL: URL(string: "https://example.invalid")!,
            username: "probe", password: "probe"
        )
    }

    private func withRecorder(_ body: (PlaybackSpy) -> Void) {
        let spy = PlaybackSpy()
        ScenePlaybackLifecycleActions.playbackOverride = spy
        defer { ScenePlaybackLifecycleActions.playbackOverride = nil }
        body(spy)
    }

    /// The save trio, in the order both platforms already used.
    private var expectedSave: [String] {
        ["savePlayQueue", "saveQueueLocally", "createBookmarkIfNeeded"]
    }

    /// Restore then re-sync, the order both platforms already used.
    private var expectedRestore: [String] {
        ["restorePlayQueue", "refreshPlaybackState"]
    }

    // MARK: - iOS phase mapping

    /// iOS saves on `.background` and only on `.background`.
    @Test func iOSSavesOnBackgroundOnly() {
        withRecorder { spy in
            let outcome = ScenePlaybackLifecycleActions.handleIOSScenePhase(
                .background, client: makeClient())
            #expect(outcome == .saved)
            #expect(spy.calls == expectedSave,
                    "iOS background produced \(spy.calls) instead of the save trio")
            #expect(spy.playCalls.isEmpty, "saving started playback")
        }
        // .inactive is a macOS save phase, not an iOS one — iOS must ignore it.
        withRecorder { spy in
            let outcome = ScenePlaybackLifecycleActions.handleIOSScenePhase(
                .inactive, client: makeClient())
            #expect(outcome == .none)
            #expect(spy.calls.isEmpty, "iOS saved on .inactive, which is macOS behaviour")
        }
    }

    /// iOS restores on `.active`.
    @Test func iOSRestoresOnActive() {
        withRecorder { spy in
            let outcome = ScenePlaybackLifecycleActions.handleIOSScenePhase(
                .active, client: makeClient())
            #expect(outcome == .restoredAndRefreshed)
            #expect(spy.calls == expectedRestore,
                    "iOS active produced \(spy.calls) instead of restore + refresh")
            #expect(spy.playCalls.isEmpty, "restoring started audible playback")
        }
    }

    // MARK: - macOS phase mapping

    /// macOS saves on `.inactive`, because a Mac window rarely gets `.background`. Waiting for
    /// `.background` would mean never saving.
    @Test func macSavesOnInactiveOnly() {
        withRecorder { spy in
            let outcome = ScenePlaybackLifecycleActions.handleMacScenePhase(
                .inactive, client: makeClient())
            #expect(outcome == .saved)
            #expect(spy.calls == expectedSave,
                    "macOS inactive produced \(spy.calls) instead of the save trio")
            #expect(spy.playCalls.isEmpty)
        }
        // macOS does not act on .background — its save already happened at .inactive.
        withRecorder { spy in
            let outcome = ScenePlaybackLifecycleActions.handleMacScenePhase(
                .background, client: makeClient())
            #expect(outcome == .none)
            #expect(spy.calls.isEmpty, "macOS gained a .background save it did not have")
        }
    }

    /// macOS restores on `.active`, same as iOS.
    @Test func macRestoresOnActive() {
        withRecorder { spy in
            let outcome = ScenePlaybackLifecycleActions.handleMacScenePhase(
                .active, client: makeClient())
            #expect(outcome == .restoredAndRefreshed)
            #expect(spy.calls == expectedRestore)
        }
    }

    /// The platforms differ on exactly one phase, and that difference is the point.
    @Test func theTwoPlatformsDifferOnlyOnTheSavePhase() {
        withRecorder { spy in
            _ = ScenePlaybackLifecycleActions.handleIOSScenePhase(.background, client: makeClient())
            let iOSBackground = spy.calls
            #expect(iOSBackground == expectedSave)
        }
        withRecorder { spy in
            _ = ScenePlaybackLifecycleActions.handleMacScenePhase(.background, client: makeClient())
            #expect(spy.calls.isEmpty, "macOS must not save on .background")
        }
        withRecorder { spy in
            _ = ScenePlaybackLifecycleActions.handleIOSScenePhase(.inactive, client: makeClient())
            #expect(spy.calls.isEmpty, "iOS must not save on .inactive")
        }
        withRecorder { spy in
            _ = ScenePlaybackLifecycleActions.handleMacScenePhase(.inactive, client: makeClient())
            #expect(spy.calls == expectedSave)
        }
    }

    // MARK: - Exactly once, and no throttling

    /// One qualifying callback performs the operation once. Repeated qualifying callbacks repeat it,
    /// exactly as before — no debounce, deduplication or throttling was added.
    @Test func repeatedPhasesRepeatTheOperation() {
        withRecorder { spy in
            for _ in 0..<3 {
                ScenePlaybackLifecycleActions.handleIOSScenePhase(.background, client: makeClient())
            }
            #expect(spy.calls == expectedSave + expectedSave + expectedSave,
                    "callback count and save count diverged: \(spy.calls)")
        }
        withRecorder { spy in
            for _ in 0..<3 {
                ScenePlaybackLifecycleActions.handleIOSScenePhase(.active, client: makeClient())
            }
            #expect(spy.calls == expectedRestore + expectedRestore + expectedRestore,
                    "restore was deduplicated at the call site; the engine guard is the authority")
        }
    }

    /// A non-qualifying phase performs nothing at all on either platform.
    @Test func nonQualifyingPhasesDoNothing() {
        withRecorder { spy in
            _ = ScenePlaybackLifecycleActions.handleIOSScenePhase(.inactive, client: makeClient())
            _ = ScenePlaybackLifecycleActions.handleMacScenePhase(.background, client: makeClient())
            #expect(spy.calls.isEmpty, "a non-qualifying phase performed \(spy.calls)")
            #expect(spy.playCalls.isEmpty)
        }
    }

    /// No lifecycle transition may start playback or stop it.
    @Test func noLifecyclePhaseTouchesTransport() {
        let phases: [ScenePhase] = [.active, .inactive, .background]
        for phase in phases {
            withRecorder { spy in
                _ = ScenePlaybackLifecycleActions.handleIOSScenePhase(phase, client: makeClient())
                _ = ScenePlaybackLifecycleActions.handleMacScenePhase(phase, client: makeClient())
                let transport = ["play", "pause", "resume", "stop", "next", "previous",
                                 "togglePlayPause", "seek", "skipToIndex"]
                #expect(spy.calls.allSatisfy { !transport.contains($0) },
                        "a scene phase performed transport: \(spy.calls)")
                #expect(spy.playCalls.isEmpty)
            }
        }
    }

    // MARK: - Routing

    /// With the façade overridden, an operation still calling `AudioEngine.shared` directly would
    /// record nothing here — and the singleton must be untouched.
    @Test func lifecycleDoesNotAlsoTouchTheSingleton() {
        let engine = AudioEngine.shared
        let queueBefore = engine.queue.map(\.id)
        let indexBefore = engine.currentIndex
        let playingBefore = engine.isPlaying

        withRecorder { spy in
            _ = ScenePlaybackLifecycleActions.handleIOSScenePhase(.background, client: makeClient())
            _ = ScenePlaybackLifecycleActions.handleIOSScenePhase(.active, client: makeClient())
            #expect(spy.calls == expectedSave + expectedRestore)
        }

        #expect(engine.queue.map(\.id) == queueBefore,
                "the lifecycle path reached AudioEngine.shared as well as the façade")
        #expect(engine.currentIndex == indexBefore)
        #expect(engine.isPlaying == playingBefore)
    }

    /// One lifecycle transition produces exactly one legacy engine call per operation, through the
    /// real production wiring. `saveQueueLocally` is used because it writes only to the local store —
    /// no network, no audio.
    @Test func oneLifecyclePhaseProducesOneLegacyOperationEach() {
        guard let adapter = ApplicationPlayback.legacyAdapter else {
            Issue.record("the façade did not resolve to the legacy adapter")
            return
        }
        #expect(ScenePlaybackLifecycleActions.playbackOverride == nil,
                "a previous test leaked an override")
        #expect(ScenePlaybackLifecycleActions.playback === ApplicationPlayback.shared,
                "the lifecycle layer resolved a second façade")

        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        adapter.resetDelegationCounts()

        adapter.saveQueueLocally()

        #expect(adapter.delegatedCallCounts["saveQueueLocally"] == 1,
                "one save produced \(adapter.delegatedCallCounts["saveQueueLocally"] ?? 0) engine calls")
        #expect(engine.isPlaying == playingBefore, "saving started playback")
        adapter.resetDelegationCounts()
    }

    // MARK: - Restoration overlap

    /// Three sites request restore — CarPlay, iOS and macOS — and all three must reach the same
    /// singleton. If any resolved a different authority, the queue could fork.
    @Test func allRestoreRequestersShareOneAuthority() {
        #expect(ScenePlaybackLifecycleActions.playbackOverride == nil)
        #expect(CarPlayScenePlaybackActions.playbackOverride == nil)

        let lifecycle = ScenePlaybackLifecycleActions.playback
        let carPlayScene = CarPlayScenePlaybackActions.playback
        #expect(lifecycle === ApplicationPlayback.shared)
        #expect(carPlayScene === ApplicationPlayback.shared)
        #expect(lifecycle === carPlayScene,
                "CarPlay and the main app resolved different playback authorities")
        #expect(ApplicationPlayback.legacyAdapter != nil)
    }

    /// The call sites deliberately do not deduplicate: each request delegates, and the engine's own
    /// guard is what makes later ones no-ops. No once-per-process rule was added here.
    @Test func repeatedRestoreRequestsAllDelegateAndLeaveGuardingToTheEngine() {
        withRecorder { spy in
            _ = ScenePlaybackLifecycleActions.handleIOSScenePhase(.active, client: makeClient())
            _ = ScenePlaybackLifecycleActions.handleMacScenePhase(.active, client: makeClient())

            #expect(spy.calls == expectedRestore + expectedRestore,
                    "a restore request was suppressed at the call site rather than by the engine")
        }
    }

    // MARK: - Construction and activation

    /// Driving every phase repeatedly must start nothing and must not touch the audio session.
    @Test func lifecycleTransitionsStartNothing() {
        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let categoryBefore = AVAudioSession.sharedInstance().category
        let modeBefore = AVAudioSession.sharedInstance().mode
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        withRecorder { spy in
            for _ in 0..<20 {
                _ = ScenePlaybackLifecycleActions.handleIOSScenePhase(.active, client: makeClient())
                _ = ScenePlaybackLifecycleActions.handleIOSScenePhase(.inactive, client: makeClient())
                _ = ScenePlaybackLifecycleActions.handleIOSScenePhase(.background, client: makeClient())
                _ = ScenePlaybackLifecycleActions.handleMacScenePhase(.active, client: makeClient())
                _ = ScenePlaybackLifecycleActions.handleMacScenePhase(.inactive, client: makeClient())
            }
            #expect(spy.playCalls.isEmpty, "a lifecycle transition started a track")
        }

        #expect(engine.isPlaying == playingBefore, "a lifecycle transition started playback")
        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "a lifecycle transition changed the audio session category")
        #expect(AVAudioSession.sharedInstance().mode == modeBefore,
                "a lifecycle transition changed the audio session mode")
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore,
                "a lifecycle transition registered remote command handlers")
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "a lifecycle transition constructed a persistent playback controller")
    }

    /// Constructing the views that own these callbacks starts nothing either.
    @Test func constructingTheLifecycleViewsStartsNothing() {
        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let queueBefore = engine.queue.count
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        for _ in 0..<100 {
            _ = ContentView()
            #expect(ScenePlaybackLifecycleActions.playback === ApplicationPlayback.shared,
                    "a second façade was created")
        }

        #expect(engine.isPlaying == playingBefore, "constructing ContentView started playback")
        #expect(engine.queue.count == queueBefore)
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore)
        #expect(GaplessDiagnosticsRegistry.current == nil)
    }

    /// The DEBUG override defaults to nil, falls back to the composition point, and is restored.
    @Test func testSeamDefaultsToProductionWiring() {
        #expect(ScenePlaybackLifecycleActions.playbackOverride == nil,
                "the lifecycle façade override leaked out of a previous test")
        #expect(ScenePlaybackLifecycleActions.playback === ApplicationPlayback.shared)

        withRecorder { spy in
            #expect(ScenePlaybackLifecycleActions.playback === spy)
        }
        #expect(ScenePlaybackLifecycleActions.playback === ApplicationPlayback.shared,
                "the override was not restored after use")
    }

    /// Lane 2D-B1 moves two call sites. The persistent engine stays unwired.
    @Test func persistentPlaybackRemainsUnwired() {
        #expect(GaplessDiagnosticsRegistry.current == nil)
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the façade resolved to something other than the legacy adapter")
    }
}
