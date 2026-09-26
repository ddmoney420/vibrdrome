#if os(iOS)
import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Lane 2D-A: `CarPlaySceneDelegate`'s connect-time playback work now goes through
/// `ApplicationPlayback.shared`.
///
/// **What is reachable.** `CPInterfaceController` and `CPTemplateApplicationScene` have no public
/// initialisers, so `templateApplicationScene(_:didConnect:)` cannot be invoked from a test. The
/// scene delegate's own responsibilities — interface-controller ownership, `CarPlayManager`
/// construction and teardown, and the order of those steps — are therefore not exercised here and
/// are unchanged by this lane. What *is* exercised is the last step of connection, the only part
/// that touches playback.
///
/// **The property that matters most: connecting CarPlay must not start audible playback.** Plugging
/// in a phone must not interrupt whatever the car was already playing. Restoration deliberately
/// restores a *paused* queue — it never activates the audio session and never calls `play()`
/// (#134) — and the tests below pin that nothing in this path changes session category, session
/// mode, or playing state.
@Suite(.serialized)
@MainActor
struct CarPlayScenePlaybackMigrationTests {

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

    /// A client that is never actually called: the recorder swallows `restorePlayQueue`, so no
    /// request is issued.
    private func makeClient() -> SubsonicClient {
        SubsonicClient(
            baseURL: URL(string: "https://example.invalid")!,
            username: "probe", password: "probe"
        )
    }

    private func withRecorder(_ body: (PlaybackSpy) -> Void) {
        let spy = PlaybackSpy()
        CarPlayScenePlaybackActions.playbackOverride = spy
        defer { CarPlayScenePlaybackActions.playbackOverride = nil }
        body(spy)
    }

    // MARK: - Routing

    /// Nothing loaded: the connection requests a queue restore, exactly once, and does nothing else.
    /// With the façade overridden, an operation still calling `AudioEngine.shared` directly would
    /// record nothing here — so this doubles as the routing proof.
    @Test func connectingWithNothingLoadedRequestsRestoreExactlyOnce() {
        withRecorder { spy in
            spy.currentSong = nil

            let outcome = CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(client: makeClient())

            #expect(outcome == .requestedQueueRestore)
            #expect(spy.calls == ["restorePlayQueue"],
                    "connection produced \(spy.calls) instead of exactly one restore")
            #expect(spy.playCalls.isEmpty, "connecting CarPlay started a track")
        }
    }

    /// Something already loaded: Now Playing is refreshed and **no restore is requested**. This is
    /// the reconnect-safety property — a head unit reconnecting mid-session must not disturb the
    /// queue that is already in place.
    @Test func connectingWithSomethingLoadedRefreshesWithoutRestoring() {
        withRecorder { spy in
            spy.currentSong = makeSong(id: "loaded")
            spy.currentTime = 42
            spy.isPlaying = true

            let outcome = CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(client: makeClient())

            #expect(outcome == .refreshedNowPlaying)
            #expect(spy.calls.isEmpty,
                    "connecting with a loaded track delegated \(spy.calls) — it must not restore")
            #expect(spy.playCalls.isEmpty)
        }
    }

    /// The migrated path must not talk to both authorities. With the recorder installed, the real
    /// singleton must be untouched.
    @Test func theMigratedPathDoesNotAlsoTouchTheSingleton() {
        let engine = AudioEngine.shared
        let queueBefore = engine.queue.map(\.id)
        let indexBefore = engine.currentIndex
        let playingBefore = engine.isPlaying

        withRecorder { spy in
            spy.currentSong = nil
            CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(client: makeClient())
            #expect(spy.calls == ["restorePlayQueue"])
        }

        #expect(engine.queue.map(\.id) == queueBefore,
                "the migrated path reached AudioEngine.shared as well as the façade")
        #expect(engine.currentIndex == indexBefore)
        #expect(engine.isPlaying == playingBefore)
    }

    /// The scene delegate performs no save and no stop — those live in the main app's scene-phase
    /// handling, which is Lane 2D-B. Pinned so a later lane does not quietly add one here.
    @Test func theSceneDelegatePerformsNoSaveOrStop() {
        withRecorder { spy in
            spy.currentSong = nil
            CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(client: makeClient())
            #expect(spy.calls.contains("stop") == false, "CarPlay connection stopped playback")
            #expect(spy.calls.contains("pause") == false, "CarPlay connection paused playback")
            #expect(spy.calls == ["restorePlayQueue"])
        }
    }

    // MARK: - Reconnection

    /// Each connection callback performs its operation once — never twice for one callback — and a
    /// reconnect repeats it, which is the existing behaviour rather than a once-per-process rule.
    @Test func eachConnectionPerformsItsOperationExactlyOnce() {
        withRecorder { spy in
            spy.currentSong = nil

            CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(client: makeClient())
            #expect(spy.calls == ["restorePlayQueue"])

            // Disconnect and reconnect: the same callback runs again.
            CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(client: makeClient())
            #expect(spy.calls == ["restorePlayQueue", "restorePlayQueue"],
                    "callback count and operation count diverged: \(spy.calls)")
        }
    }

    /// Repeated restore is self-limiting at the engine, not at the call site: once anything is
    /// loaded, every later connection takes the refresh branch instead. That is what stops a
    /// reconnect from double-restoring, and it is preserved.
    @Test func reconnectingAfterRestoreStopsRequestingRestore() {
        withRecorder { spy in
            spy.currentSong = nil
            #expect(CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(client: makeClient())
                    == .requestedQueueRestore)

            // Restoration landed a track, exactly as the engine would have.
            spy.currentSong = makeSong(id: "restored")

            for _ in 0..<5 {
                #expect(CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(client: makeClient())
                        == .refreshedNowPlaying)
            }
            #expect(spy.calls == ["restorePlayQueue"],
                    "a reconnect restored again over a queue that was already loaded")
        }
    }

    /// Against the real engine: with a queue already loaded, connection takes the refresh branch and
    /// leaves the queue exactly as it was. Drives no restore, so no network request is issued.
    @Test func liveEngineWithLoadedQueueIsUntouchedByConnection() {
        #expect(CarPlayScenePlaybackActions.playbackOverride == nil,
                "a previous test leaked a façade override")
        let engine = AudioEngine.shared
        let queueBefore = engine.queue
        let indexBefore = engine.currentIndex
        let songBefore = engine.currentSong
        defer {
            engine.queue = queueBefore
            engine.currentIndex = indexBefore
            engine.currentSong = songBefore
        }

        engine.queue = [makeSong(id: "a"), makeSong(id: "b")]
        engine.currentIndex = 0
        engine.currentSong = makeSong(id: "a")

        let outcome = CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(client: makeClient())

        #expect(outcome == .refreshedNowPlaying)
        #expect(engine.queue.map(\.id) == ["a", "b"], "connection mutated a loaded queue")
        #expect(engine.currentIndex == 0)
        #expect(engine.currentSong?.id == "a")
    }

    // MARK: - Construction and activation

    /// The load-bearing safety property: connecting CarPlay starts nothing audible and does not
    /// touch the audio session. Restoration restores paused queue metadata only.
    @Test func connectingStartsNothingAudible() {
        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let categoryBefore = AVAudioSession.sharedInstance().category
        let modeBefore = AVAudioSession.sharedInstance().mode
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        withRecorder { spy in
            spy.currentSong = nil
            for _ in 0..<25 {
                CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(client: makeClient())
            }
            #expect(spy.playCalls.isEmpty, "connecting CarPlay started a track")
            #expect(spy.calls.allSatisfy { $0 == "restorePlayQueue" },
                    "connecting CarPlay performed something other than restore: \(spy.calls)")
        }

        #expect(engine.isPlaying == playingBefore, "connecting CarPlay started playback")
        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "connecting CarPlay changed the audio session category")
        #expect(AVAudioSession.sharedInstance().mode == modeBefore,
                "connecting CarPlay changed the audio session mode")
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore,
                "the connect-time sync registered remote command handlers")
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "connecting CarPlay constructed a persistent playback controller")
    }

    /// Resolving the scene seam repeatedly yields the one shared façade — no second authority, and
    /// remote-command registration stays at exactly one for the process.
    @Test func resolvingTheSceneSeamCreatesNoSecondAuthority() {
        #expect(CarPlayScenePlaybackActions.playbackOverride == nil,
                "a previous test leaked a façade override")
        RemoteCommandManager.shared.setup()

        for _ in 0..<100 {
            #expect(CarPlayScenePlaybackActions.playback === ApplicationPlayback.shared,
                    "the scene seam resolved a second façade")
        }
        // CarPlayManager's own seam and the scene's seam must be the same object.
        #expect(CarPlayScenePlaybackActions.playback === CarPlayPlaybackActions.playback,
                "the CarPlay scene and manager resolved different playback authorities")
        #expect(RemoteCommandManager.shared.registrationCount == 1,
                "remote commands were registered \(RemoteCommandManager.shared.registrationCount) times")
        #expect(GaplessDiagnosticsRegistry.current == nil)
    }

    /// The DEBUG override defaults to nil, falls back to the composition point, and is restored.
    @Test func testSeamDefaultsToProductionWiring() {
        #expect(CarPlayScenePlaybackActions.playbackOverride == nil,
                "the scene façade override leaked out of a previous test")
        #expect(CarPlayScenePlaybackActions.playback === ApplicationPlayback.shared)

        withRecorder { spy in
            #expect(CarPlayScenePlaybackActions.playback === spy)
        }
        #expect(CarPlayScenePlaybackActions.playback === ApplicationPlayback.shared,
                "the override was not restored after use")
    }

    /// Lane 2D-A moves one file. The persistent engine stays unwired.
    @Test func persistentPlaybackRemainsUnwired() {
        #expect(GaplessDiagnosticsRegistry.current == nil)
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the façade resolved to something other than the legacy adapter")
    }
}
#endif
