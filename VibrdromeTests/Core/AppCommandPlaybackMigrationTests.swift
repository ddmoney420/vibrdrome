import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Lane 2D-B2: `Vibrdrome.swift`, the app entry point, now reaches playback through
/// `ApplicationPlayback.shared`. This is the last application-facing caller.
///
/// **The audit's headline finding: there is no cold-launch playback path in this file.**
/// `VibrdromeApp.init()` runs credential/visualizer migrations, prunes legacy widget keys and calls
/// `BackgroundSyncScheduler.registerTasks()`. The scenes' `.onAppear` installs the image pipeline,
/// calls `RemoteCommandManager.setup()`, resumes downloads, schedules background sync and starts
/// library sync. **Neither touches playback at all.** Queue restoration lives in `ContentView` /
/// `MacContentView` and `CarPlaySceneDelegate`, migrated in earlier lanes.
///
/// Every one of the 15 references sat behind an explicit user action: a `vibrdrome://song/<id>` deep
/// link, or a macOS Playback-menu item with a keyboard shortcut. So the zero-activation gate here is
/// not "the launch path was made safe" — it is "the launch path never had a playback call to make
/// unsafe", and these tests pin that it stays that way.
///
/// **No real audio.** The command bodies are driven against an injected recorder.
@Suite(.serialized)
@MainActor
struct AppCommandPlaybackMigrationTests {

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

    private func withRecorder(_ body: (PlaybackSpy) -> Void) {
        let spy = PlaybackSpy()
        AppCommandPlaybackActions.playbackOverride = spy
        defer { AppCommandPlaybackActions.playbackOverride = nil }
        body(spy)
    }

    // MARK: - Explicit commands, exactly once

    /// Every macOS Playback-menu command delegates exactly once and delegates nothing else. With the
    /// façade overridden, a command still calling `AudioEngine.shared` would record nothing here.
    @Test func eachMenuCommandDelegatesExactlyOnce() {
        let cases: [(name: String, action: @MainActor () -> Void)] = [
            ("togglePlayPause", { AppCommandPlaybackActions.togglePlayPause() }),
            ("next", { AppCommandPlaybackActions.nextTrack() }),
            ("previous", { AppCommandPlaybackActions.previousTrack() }),
            ("seek", { AppCommandPlaybackActions.seekForward(by: 10) }),
            ("seek", { AppCommandPlaybackActions.seekBackward(by: 10) }),
            ("toggleShuffle", { AppCommandPlaybackActions.toggleShuffle() }),
            ("cycleRepeatMode", { AppCommandPlaybackActions.cycleRepeatMode() })
        ]

        for testCase in cases {
            withRecorder { spy in
                testCase.action()
                #expect(spy.calls == [testCase.name],
                        "\(testCase.name) produced \(spy.calls) instead of exactly one call")
                #expect(spy.playCalls.isEmpty, "\(testCase.name) started a new track")
            }
        }
    }

    /// The deep-link command starts the fetched song with no queue, at index 0 — the engine's own
    /// defaults, unchanged.
    @Test func deepLinkSongCommandDelegatesExactlyOnce() {
        withRecorder { spy in
            AppCommandPlaybackActions.playSong(makeSong(id: "deep-linked"))

            #expect(spy.playCalls.count == 1, "the deep link did not delegate exactly once")
            #expect(spy.playCalls.first?.songId == "deep-linked")
            #expect(spy.playCalls.first?.queueCount == nil, "the deep link replaced the queue")
            #expect(spy.playCalls.first?.index == 0)
            #expect(spy.calls.isEmpty, "the deep link delegated an unrelated operation")
        }
    }

    /// Seek clamping is preserved verbatim: forward stops at the track end, backward at zero.
    @Test func seekClampingIsUnchanged() {
        withRecorder { spy in
            spy.duration = 100
            spy.currentTime = 95
            AppCommandPlaybackActions.seekForward(by: 10)
            #expect(spy.seekTargets == [100], "seek forward stopped clamping at the track end")
        }
        withRecorder { spy in
            spy.duration = 100
            spy.currentTime = 40
            AppCommandPlaybackActions.seekForward(by: 10)
            #expect(spy.seekTargets == [50])
        }
        withRecorder { spy in
            spy.currentTime = 4
            AppCommandPlaybackActions.seekBackward(by: 10)
            #expect(spy.seekTargets == [0], "seek backward stopped clamping at zero")
        }
        withRecorder { spy in
            spy.currentTime = 40
            AppCommandPlaybackActions.seekBackward(by: 10)
            #expect(spy.seekTargets == [30])
        }
    }

    /// Volume step and clamping are preserved verbatim.
    @Test func volumeSteppingIsUnchanged() {
        withRecorder { spy in
            spy.volume = 0.5
            AppCommandPlaybackActions.volumeUp(by: 0.1)
            #expect(abs(spy.volume - 0.6) < 0.0001)
        }
        withRecorder { spy in
            spy.volume = 0.95
            AppCommandPlaybackActions.volumeUp(by: 0.1)
            #expect(spy.volume == 1.0, "volume up stopped clamping at 1")
        }
        withRecorder { spy in
            spy.volume = 0.05
            AppCommandPlaybackActions.volumeDown(by: 0.1)
            #expect(spy.volume == 0.0, "volume down stopped clamping at 0")
        }
    }

    /// The favourite and rating menu items read the current track and are no-ops when nothing is
    /// loaded. They must never touch transport.
    @Test func metadataCommandsReadCurrentSongAndTouchNoTransport() {
        withRecorder { spy in
            spy.currentSong = nil
            #expect(AppCommandPlaybackActions.currentSong == nil)
            #expect(spy.calls.isEmpty)

            spy.currentSong = makeSong(id: "loaded")
            #expect(AppCommandPlaybackActions.currentSong?.id == "loaded",
                    "the metadata commands are not reading through the façade")
            #expect(spy.calls.isEmpty, "a metadata command delegated a transport operation")
            #expect(spy.playCalls.isEmpty)
        }
    }

    /// Repeated menu presses perform the operation once each — never more.
    @Test func repeatedCommandsProduceOneOperationEach() {
        withRecorder { spy in
            for _ in 0..<4 { AppCommandPlaybackActions.nextTrack() }
            #expect(spy.calls == ["next", "next", "next", "next"],
                    "press count and operation count diverged: \(spy.calls)")
        }
    }

    // MARK: - Double dispatch

    /// The menu's Play/Pause and Next expose the same actions as the lock-screen buttons, but they
    /// are separate entry points. One press must travel one path.
    @Test func menuCommandsDoNotAlsoDispatchThroughRemoteCommands() {
        #expect(RemoteCommandManager.shared.playbackOverride == nil,
                "a previous test leaked a remote-command override")
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        let remoteSpy = PlaybackSpy()
        RemoteCommandManager.shared.playbackOverride = remoteSpy
        defer { RemoteCommandManager.shared.playbackOverride = nil }

        withRecorder { menuSpy in
            AppCommandPlaybackActions.togglePlayPause()
            AppCommandPlaybackActions.nextTrack()
            AppCommandPlaybackActions.previousTrack()

            #expect(menuSpy.calls == ["togglePlayPause", "next", "previous"])
            #expect(remoteSpy.calls.isEmpty,
                    "a menu command also dispatched through RemoteCommandManager")
            #expect(remoteSpy.playCalls.isEmpty)
        }
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore,
                "a menu command registered remote command handlers")
    }

    /// One command through the real production wiring produces exactly one legacy engine call.
    @Test func oneCommandProducesOneLegacyOperation() {
        guard let adapter = ApplicationPlayback.legacyAdapter else {
            Issue.record("the façade did not resolve to the legacy adapter")
            return
        }
        #expect(AppCommandPlaybackActions.playbackOverride == nil, "a previous test leaked an override")
        #expect(AppCommandPlaybackActions.playback === ApplicationPlayback.shared,
                "the command layer resolved a second façade")

        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let shuffleBefore = engine.shuffleEnabled
        adapter.resetDelegationCounts()

        AppCommandPlaybackActions.toggleShuffle()

        #expect(adapter.delegatedCallCounts["toggleShuffle"] == 1,
                "one command produced \(adapter.delegatedCallCounts["toggleShuffle"] ?? 0) engine calls")
        #expect(engine.shuffleEnabled != shuffleBefore, "the command did not reach the engine")
        AppCommandPlaybackActions.toggleShuffle()                     // restore
        #expect(engine.shuffleEnabled == shuffleBefore)
        #expect(engine.isPlaying == playingBefore, "a menu command started playback")
        adapter.resetDelegationCounts()
    }

    // MARK: - Cold launch

    /// The zero-activation gate for the launch path.
    ///
    /// **`VibrdromeApp` itself is deliberately not constructed here.** Its `init()` calls
    /// `BackgroundSyncScheduler.registerTasks()`, and `BGTaskScheduler.register(forTaskWithIdentifier:)`
    /// raises on a duplicate identifier — the host app already registered at launch, so building a
    /// second `VibrdromeApp` would take the test process down rather than prove anything. What is
    /// driven instead is everything on the launch path that *is* safely re-runnable: the scene root
    /// and the idempotent remote-command setup that `.onAppear` performs.
    ///
    /// The stronger claim — that `init()` and both `.onAppear` blocks contain no playback call at
    /// all — is a source property, verified by enumerating every reference in the file through its
    /// aliases before migrating. All 15 sat behind an explicit user action.
    ///
    /// This matters because of #134: activating the session on launch would interrupt Spotify or
    /// YouTube before the user ever pressed Play.
    @Test func launchPathStartsNothingAndActivatesNothing() {
        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let queueBefore = engine.queue.count
        let indexBefore = engine.currentIndex
        let categoryBefore = AVAudioSession.sharedInstance().category
        let modeBefore = AVAudioSession.sharedInstance().mode
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        let spy = PlaybackSpy()
        AppCommandPlaybackActions.playbackOverride = spy
        defer { AppCommandPlaybackActions.playbackOverride = nil }

        for _ in 0..<50 {
            _ = ContentView()                       // the iOS scene root
            RemoteCommandManager.shared.setup()     // what .onAppear calls; idempotent
            #expect(AppCommandPlaybackActions.playback === spy)
        }

        #expect(spy.calls.isEmpty,
                "the launch path delegated \(spy.calls) — it must touch no playback")
        #expect(spy.playCalls.isEmpty, "the launch path started a track")
        #expect(engine.isPlaying == playingBefore, "the launch path started playback")
        #expect(engine.queue.count == queueBefore, "the launch path changed the queue")
        #expect(engine.currentIndex == indexBefore)
        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "the launch path changed the audio session category")
        #expect(AVAudioSession.sharedInstance().mode == modeBefore,
                "the launch path changed the audio session mode")
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore,
                "the launch path registered remote commands again")
        #expect(RemoteCommandManager.shared.registrationCount == 1,
                "remote commands registered \(RemoteCommandManager.shared.registrationCount) times")
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "the launch path built a persistent playback controller")
    }

    /// Repeated construction of the app and its content views never yields a second façade, and the
    /// whole application resolves one playback authority across every seam.
    @Test func everySeamResolvesTheSameSingleAuthority() {
        #expect(AppCommandPlaybackActions.playbackOverride == nil)
        #expect(ScenePlaybackLifecycleActions.playbackOverride == nil)
        #expect(CarPlayScenePlaybackActions.playbackOverride == nil)
        #expect(WatchPlaybackActions.playbackOverride == nil)
        #expect(AppIntentPlaybackActions.playbackOverride == nil)
        #expect(RemoteCommandManager.shared.playbackOverride == nil)

        for _ in 0..<25 {
            _ = ContentView()
        }

        let authority = ApplicationPlayback.shared
        #expect(AppCommandPlaybackActions.playback === authority)
        #expect(ScenePlaybackLifecycleActions.playback === authority)
        #expect(CarPlayScenePlaybackActions.playback === authority)
        #expect(CarPlayPlaybackActions.playback === authority)
        #expect(WatchPlaybackActions.playback === authority)
        #expect(AppIntentPlaybackActions.playback === authority)
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the application resolved something other than the legacy adapter")
        #expect(RemoteCommandManager.shared.registrationCount == 1,
                "remote commands were registered \(RemoteCommandManager.shared.registrationCount) times")
        #expect(GaplessDiagnosticsRegistry.current == nil)
    }

    /// Background-sync work is playback-free by construction.
    ///
    /// Registration itself cannot be re-driven — `BGTaskScheduler.register` raises on a duplicate
    /// identifier and the host app already registered at launch — so what is pinned here is the
    /// scheduler's *playback* surface: it has none. `BackgroundSyncScheduler` performs library sync
    /// and predownload work and never routes a playback operation, so no background transition can
    /// start audio.
    @Test func backgroundSyncHasNoPlaybackSurface() {
        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let categoryBefore = AVAudioSession.sharedInstance().category

        withRecorder { spy in
            _ = BackgroundSyncScheduler.shared
            #expect(spy.calls.isEmpty, "resolving the background scheduler performed playback")
            #expect(spy.playCalls.isEmpty)
        }

        #expect(engine.isPlaying == playingBefore, "the background scheduler started playback")
        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "the background scheduler changed the audio session category")
        #expect(GaplessDiagnosticsRegistry.current == nil)
    }

    /// The DEBUG override defaults to nil, falls back to the composition point, and is restored.
    @Test func testSeamDefaultsToProductionWiring() {
        #expect(AppCommandPlaybackActions.playbackOverride == nil,
                "the command façade override leaked out of a previous test")
        #expect(AppCommandPlaybackActions.playback === ApplicationPlayback.shared)

        withRecorder { spy in
            #expect(AppCommandPlaybackActions.playback === spy)
        }
        #expect(AppCommandPlaybackActions.playback === ApplicationPlayback.shared,
                "the override was not restored after use")
    }

    /// The last application-facing lane. The persistent engine is still unwired.
    @Test func persistentPlaybackRemainsUnwired() {
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "the application constructed a persistent playback controller")
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the façade resolved to something other than the legacy adapter")
    }
}
