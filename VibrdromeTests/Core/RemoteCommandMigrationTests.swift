import Foundation
import MediaPlayer
import Testing
@testable import Vibrdrome

#if os(iOS)
import AVFoundation
#endif

/// Lane 2B: `RemoteCommandManager` now drives playback through `ApplicationPlayback.shared`.
///
/// The property worth protecting here is narrower than in the view lane: **one press must produce
/// exactly one engine operation.** A duplicated handler makes a single lock-screen tap skip two
/// tracks, and it is invisible in a build — it only shows up in the car or on a headphone button.
/// So this suite proves the count, not just the effect.
///
/// The routing under test:
///
///     MPRemoteCommandCenter -> RemoteCommandManager -> ApplicationPlayback.shared
///                           -> LegacyAudioEngineAdapter -> AudioEngine.shared -> AVQueuePlayer
///
/// **Why the command bodies are called directly.** `MPRemoteCommandCenter` has no API to fire a
/// registered command, and `MPRemoteCommandEvent` has no public initialiser, so a test cannot go in
/// through MediaPlayer. `RemoteCommandManager` exposes one method per command and the registered
/// closures do nothing but call them, so these tests exercise the exact code a real press runs.
/// Production registration and `MPRemoteCommandCenter` ownership are untouched.
///
/// **No real audio.** `resume`, `next` and `previous` would start AVQueuePlayer, which cannot happen
/// while the gapless real-time suites are running. They are driven against an injected recorder.
/// The one test that uses the live façade uses `seek`, which `AudioEngine` treats as a guarded
/// no-op when nothing is playing.
@Suite(.serialized)
@MainActor
struct RemoteCommandMigrationTests {

    /// Runs `body` with a recording façade installed, and always restores production wiring.
    private func withRecorder(_ body: (RemoteCommandManager, PlaybackSpy) -> Void) {
        let manager = RemoteCommandManager.shared
        let spy = PlaybackSpy()
        manager.playbackOverride = spy
        defer { manager.playbackOverride = nil }
        body(manager, spy)
    }

    // MARK: - One command, one operation

    /// Every transport command delegates exactly once, and delegates nothing else.
    @Test func eachTransportCommandDelegatesExactlyOnce() {
        let expectations: [(name: String, call: (RemoteCommandManager) -> MPRemoteCommandHandlerStatus)] = [
            ("resume", { $0.handlePlay() }),
            ("pause", { $0.handlePause() }),
            ("togglePlayPause", { $0.handleTogglePlayPause() }),
            ("next", { $0.handleNextTrack() }),
            ("previous", { $0.handlePreviousTrack() }),
            ("seek", { $0.handleChangePlaybackPosition(to: 42) })
        ]

        for expectation in expectations {
            withRecorder { manager, spy in
                let status = expectation.call(manager)
                #expect(status == .success, "\(expectation.name) did not report .success")
                #expect(spy.calls == [expectation.name],
                        "\(expectation.name) produced \(spy.calls) instead of exactly one call")
                #expect(spy.playCalls.isEmpty, "\(expectation.name) started a new track")
            }
        }
    }

    /// A seek event that is not an `MPChangePlaybackPositionCommandEvent` keeps the original
    /// `.commandFailed` mapping, and must not move the player.
    @Test func invalidSeekFailsWithoutDelegating() {
        withRecorder { manager, spy in
            let status = manager.handleChangePlaybackPosition(to: nil)
            #expect(status == .commandFailed, "an invalid seek event stopped reporting .commandFailed")
            #expect(spy.calls.isEmpty, "an invalid seek still moved the player")
        }
    }

    /// Like and dislike are metadata commands: they report `.success` and must never touch
    /// transport. With no current item they take the existing no-action path, which is also the
    /// only path that can be driven here — the starred path issues a real network request through
    /// the shared client.
    @Test func ratingCommandsDoNotTouchTransport() {
        withRecorder { manager, spy in
            spy.currentSong = nil

            #expect(manager.handleLike() == .success)
            #expect(manager.handleDislike() == .success)
            #expect(spy.calls.isEmpty, "a rating command delegated a transport operation")
            #expect(spy.playCalls.isEmpty)
        }
    }

    /// The rating commands must re-read the current item on **every** press rather than caching it.
    /// A cached song would star whatever was playing when the handler was registered, so the Like
    /// button would favourite the wrong track for the rest of the session.
    @Test func ratingCommandsReReadCurrentSongOnEveryPress() {
        withRecorder { manager, spy in
            spy.currentSong = nil
            let before = spy.currentSongReads

            _ = manager.handleLike()
            _ = manager.handleDislike()

            #expect(spy.currentSongReads == before + 2,
                    "two presses did not produce two reads — the current song is being cached")
        }
    }

    // MARK: - One command, one legacy operation

    /// End to end through the production wiring: no override, so the command runs
    /// `ApplicationPlayback.shared` -> `LegacyAudioEngineAdapter` -> `AudioEngine.shared`. `seek` is
    /// used because `AudioEngine.seek` returns before touching a player when nothing is playing, so
    /// the delegation is counted without moving audio.
    @Test func oneRemoteCommandProducesExactlyOneLegacyOperation() {
        guard let adapter = ApplicationPlayback.legacyAdapter else {
            Issue.record("the façade did not resolve to the legacy adapter")
            return
        }
        let manager = RemoteCommandManager.shared
        let engine = AudioEngine.shared
        #expect(manager.playbackOverride == nil, "a previous test leaked a façade override")

        adapter.resetDelegationCounts()
        let playingBefore = engine.isPlaying
        let queueBefore = engine.queue.count

        let status = manager.handleChangePlaybackPosition(to: 30)

        #expect(status == .success)
        #expect(adapter.delegatedCallCounts["seek"] == 1,
                "one remote command produced \(adapter.delegatedCallCounts["seek"] ?? 0) engine calls")
        #expect(engine.isPlaying == playingBefore, "a remote seek started playback")
        #expect(engine.queue.count == queueBefore)
        adapter.resetDelegationCounts()
    }

    // MARK: - Registration ownership

    /// The `isSetup` guard is the only thing standing between one press and two skips.
    @Test func repeatedSetupDoesNotRegisterHandlersTwice() {
        let manager = RemoteCommandManager.shared
        manager.setup()                                  // may be the first call in this process
        let after = manager.registrationCount

        for _ in 0..<10 { manager.setup() }

        #expect(manager.registrationCount == after,
                "setup() registered a second set of remote command handlers")
        #expect(manager.registrationCount == 1,
                "remote commands were registered \(manager.registrationCount) times for the process")
    }

    /// Rebuilding unrelated app and scene objects must not attach another set of handlers. SwiftUI
    /// recreates view structs constantly, and a registration hidden behind one of them would
    /// duplicate silently.
    @Test func recreatingAppObjectsDoesNotRegisterHandlersAgain() {
        let manager = RemoteCommandManager.shared
        manager.setup()
        let before = manager.registrationCount

        for _ in 0..<50 {
            _ = MiniPlayerView()
            _ = QueueView()
            _ = RadioView()
            _ = ApplicationPlayback.shared
        }

        #expect(manager.registrationCount == before,
                "rebuilding views registered remote command handlers again")
        #expect(RemoteCommandManager.shared === manager, "a second RemoteCommandManager appeared")
    }

    /// Registering commands is not playback. Nothing about `setup()` may activate the audio session
    /// or start audio — Build 60's cold-launch behaviour depends on nothing waking the audio stack
    /// before an explicit Play.
    @Test func registrationAloneStartsNothing() {
        let manager = RemoteCommandManager.shared
        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let queueBefore = engine.queue.count
        let indexBefore = engine.currentIndex
        #if os(iOS)
        let categoryBefore = AVAudioSession.sharedInstance().category
        let modeBefore = AVAudioSession.sharedInstance().mode
        #endif

        manager.setup()

        #expect(engine.isPlaying == playingBefore, "registering remote commands started playback")
        #expect(engine.queue.count == queueBefore)
        #expect(engine.currentIndex == indexBefore)
        #if os(iOS)
        // Configuring the session is what sets these; unchanged means setup() never reached for
        // AudioSessionManager.
        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "registering remote commands configured the audio session")
        #expect(AVAudioSession.sharedInstance().mode == modeBefore)
        #endif
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "registering remote commands constructed a persistent playback controller")
    }

    /// Lane 2B moves one file. The persistent engine stays unwired and the façade still resolves to
    /// the legacy adapter.
    @Test func persistentPlaybackRemainsUnwired() {
        #expect(GaplessDiagnosticsRegistry.current == nil)
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the façade resolved to something other than the legacy adapter")
    }
}
