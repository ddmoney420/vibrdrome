#if os(iOS)
import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Lane 2C-B: `WatchSessionManager` now reaches playback through `ApplicationPlayback.shared`.
///
/// **What the Watch protocol actually is**, established by auditing both sides before migrating —
/// several of the commands one might expect simply do not exist:
///
/// - Transport is **`togglePlayPause` only**. There is no `play` and no `pause` command.
/// - There is **no `seek` command**. The sole numeric payload in the whole protocol is
///   `setVolume`'s `volume`, so that is what the payload tests below exercise.
/// - Replies are **always `[:]`**. State never travels in a reply; it goes out in the
///   `sendNowPlayingUpdate` application context, which is what the freshness tests cover.
///
/// **No paired Watch and no real audio.** `WCSession` messages cannot be synthesised reliably and
/// `WatchSessionManager.init` activates a live session, so every command runs through
/// `WatchPlaybackActions` — the same code an incoming message executes — against an injected
/// recorder.
@Suite(.serialized)
@MainActor
struct WatchPlaybackMigrationTests {

    private func makeSong(id: String, title: String = "Probe", starred: String? = nil) -> Song {
        Song(
            id: id, parent: nil, title: title,
            album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
            track: nil, year: nil, genre: nil, coverArt: nil,
            size: nil, contentType: nil, suffix: nil,
            duration: 180, bitRate: nil, path: nil,
            discNumber: nil, created: nil, starred: starred, userRating: nil,
            bpm: nil, replayGain: nil, musicBrainzId: nil
        )
    }

    private func withRecorder(_ body: (PlaybackSpy) -> Void) {
        let spy = PlaybackSpy()
        WatchPlaybackActions.playbackOverride = spy
        defer { WatchPlaybackActions.playbackOverride = nil }
        body(spy)
    }

    // MARK: - Exactly-once routing

    /// Every transport and mode command the Watch can send delegates exactly once and delegates
    /// nothing else. This doubles as the routing proof: a command still calling `AudioEngine.shared`
    /// directly would record nothing at all against an overridden façade.
    @Test func eachWatchCommandDelegatesExactlyOnce() {
        let cases: [(command: String, delegated: String)] = [
            ("togglePlayPause", "togglePlayPause"),
            ("next", "next"),
            ("previous", "previous"),
            ("toggleShuffle", "toggleShuffle"),
            ("cycleRepeat", "cycleRepeatMode")
        ]

        for testCase in cases {
            withRecorder { spy in
                let handled = WatchPlaybackActions.handlePlaybackCommand(testCase.command, volume: nil)
                #expect(handled, "\(testCase.command) was not recognised as a playback command")
                #expect(spy.calls == [testCase.delegated],
                        "\(testCase.command) produced \(spy.calls) instead of exactly one call")
                #expect(spy.playCalls.isEmpty, "\(testCase.command) also started a track")
            }
        }
    }

    /// `startRadio` seeds from the current track, and is a handled no-op when nothing is playing.
    @Test func startRadioDelegatesOnceOnlyWhenSomethingIsPlaying() {
        withRecorder { spy in
            spy.currentSong = nil
            #expect(WatchPlaybackActions.handlePlaybackCommand("startRadio", volume: nil))
            #expect(spy.calls.isEmpty, "startRadio delegated with no current song")
        }
        withRecorder { spy in
            spy.currentSong = makeSong(id: "seed")
            #expect(WatchPlaybackActions.handlePlaybackCommand("startRadio", volume: nil))
            #expect(spy.calls == ["startRadioFromSong"])
        }
    }

    /// `toggleStar` is metadata, never transport, and reports as handled even with no current song.
    @Test func toggleStarNeverDelegatesTransport() {
        withRecorder { spy in
            spy.currentSong = nil
            #expect(WatchPlaybackActions.handlePlaybackCommand("toggleStar", volume: nil),
                    "toggleStar with no song must still count as handled, not fall through")
            #expect(spy.calls.isEmpty)
            #expect(spy.playCalls.isEmpty)
        }
    }

    /// An unknown command falls through so the library and timer handlers get their turn.
    @Test func unknownCommandFallsThroughWithoutDelegating() {
        withRecorder { spy in
            #expect(WatchPlaybackActions.handlePlaybackCommand("playFavorites", volume: nil) == false,
                    "a library command was swallowed by the playback handler")
            #expect(WatchPlaybackActions.handlePlaybackCommand("sleepTimer15", volume: nil) == false)
            #expect(WatchPlaybackActions.handlePlaybackCommand("nonsense", volume: nil) == false)
            #expect(spy.calls.isEmpty, "an unhandled command still delegated")
        }
    }

    /// Delivering the same message twice performs the operation twice — once per delivery, never
    /// more. WatchConnectivity can redeliver, and a handler that fired twice per message would make
    /// one wrist tap skip two tracks.
    @Test func repeatedDeliveryProducesOneOperationPerDelivery() {
        withRecorder { spy in
            WatchPlaybackActions.handlePlaybackCommand("next", volume: nil)
            #expect(spy.calls == ["next"])
            WatchPlaybackActions.handlePlaybackCommand("next", volume: nil)
            #expect(spy.calls == ["next", "next"])
            WatchPlaybackActions.handlePlaybackCommand("next", volume: nil)
            #expect(spy.calls == ["next", "next", "next"],
                    "delivery count and operation count diverged")
        }
    }

    // MARK: - setVolume payload (the protocol's only numeric payload)

    /// Valid, missing and out-of-range volume payloads. There is no seek command in this protocol,
    /// so `setVolume` is the equivalent numeric-payload surface.
    @Test func volumePayloadHandlingIsUnchanged() {
        // Valid.
        withRecorder { spy in
            #expect(WatchPlaybackActions.handlePlaybackCommand("setVolume", volume: 0.5))
            #expect(spy.volume == 0.5, "a valid volume payload did not reach the façade")
        }
        // Missing: `message["volume"] as? Float` yields nil, and the level is left untouched.
        withRecorder { spy in
            spy.volume = 0.25
            #expect(WatchPlaybackActions.handlePlaybackCommand("setVolume", volume: nil),
                    "setVolume with no payload must still count as handled")
            #expect(spy.volume == 0.25, "a missing volume payload changed the level")
            #expect(spy.calls.isEmpty)
        }
        // Out of range: passed through as-is. Clamping is the engine's job and none was added here.
        withRecorder { spy in
            WatchPlaybackActions.handlePlaybackCommand("setVolume", volume: -1)
            #expect(spy.volume == -1, "the migration added clamping that did not exist before")
        }
        withRecorder { spy in
            WatchPlaybackActions.handlePlaybackCommand("setVolume", volume: 4)
            #expect(spy.volume == 4, "the migration added clamping that did not exist before")
        }
    }

    /// The engine — not the watch layer — is where the range is enforced, and it still is.
    @Test func volumeClampingRemainsTheEnginesJob() {
        let engine = AudioEngine.shared
        let original = engine.userVolume
        defer { engine.userVolume = original }

        ApplicationPlayback.shared.volume = 4
        #expect(engine.userVolume == 1.0, "the engine stopped clamping an over-range volume")
        ApplicationPlayback.shared.volume = -1
        #expect(engine.userVolume == 0.0, "the engine stopped clamping a negative volume")
    }

    // MARK: - skipToIndex mapping

    /// `skipToIndex:<n>` is relative to the track *after* the current one — the same mapping CarPlay
    /// uses — and is unchanged by the migration.
    @Test func skipToIndexMappingIsRelativeToTheCurrentTrack() {
        #expect(WatchPlaybackActions.skipToIndexAbsolute(currentIndex: 0, relative: 0) == 1)
        #expect(WatchPlaybackActions.skipToIndexAbsolute(currentIndex: 0, relative: 2) == 3)
        #expect(WatchPlaybackActions.skipToIndexAbsolute(currentIndex: 4, relative: 1) == 6)
        #expect(WatchPlaybackActions.skipToIndexAbsolute(currentIndex: -1, relative: 0) == 0)
    }

    /// Selection re-seeds the queue with itself at the target position, via `play`, not
    /// `skipToIndex` — preserved exactly, because the Watch queue list depends on it.
    @Test func skipToIndexPlaysTheTargetPositionAndReadsIndexAtCommandTime() {
        withRecorder { spy in
            spy.queue = [makeSong(id: "q0"), makeSong(id: "q1"), makeSong(id: "q2")]
            spy.currentIndex = 0

            WatchPlaybackActions.skipToIndex(relative: 0)

            #expect(spy.playCalls.count == 1, "queue selection did not delegate exactly once")
            #expect(spy.playCalls.first?.songId == "q1", "selection resolved to the wrong track")
            #expect(spy.playCalls.first?.index == 1)
            #expect(spy.calls.isEmpty, "queue selection used skipToIndex instead of play")

            // The current index is read when the command runs, not captured earlier.
            spy.currentIndex = 1
            WatchPlaybackActions.skipToIndex(relative: 0)
            #expect(spy.playCalls.last?.songId == "q2")
            #expect(spy.playCalls.last?.index == 2)
        }
    }

    /// The upper-bound guard still rejects an out-of-range row silently, as before.
    @Test func skipToIndexBeyondTheQueueDoesNothing() {
        withRecorder { spy in
            spy.queue = [makeSong(id: "only")]
            spy.currentIndex = 0

            WatchPlaybackActions.skipToIndex(relative: 50)

            #expect(spy.playCalls.isEmpty, "an out-of-range queue row still started playback")
            #expect(spy.calls.isEmpty)
        }
    }

    // MARK: - skipToIndex bounds hardening

    /// The crash this closes: `currentIndex + 1 + n` with a negative `n` used to reach
    /// `queue[negative]` and trap, because only the upper bound was checked. A watch message is
    /// just a dictionary on a wire — `skipToIndex:-1` is as deliverable as `skipToIndex:3`.
    ///
    /// Every rejected value must perform **nothing**, never clamp onto a different track.
    @Test func negativeAndOverflowingIndexesAreRejectedWithoutPlaying() {
        let rejected: [(name: String, currentIndex: Int, relative: Int)] = [
            ("minus one", 0, -1),
            ("far negative", 0, -50),
            ("Int.min", 0, .min),
            ("negative past the queue start", 2, -10),
            ("current index overflow", .max, 0),
            ("absolute index overflow", Int.max - 1, 5)
        ]

        for testCase in rejected {
            #expect(WatchPlaybackActions.skipToIndexAbsolute(
                currentIndex: testCase.currentIndex, relative: testCase.relative) == nil,
                    "\(testCase.name) produced an addressable index")

            withRecorder { spy in
                spy.queue = (0..<5).map { makeSong(id: "q\($0)") }
                spy.currentIndex = testCase.currentIndex
                WatchPlaybackActions.skipToIndex(relative: testCase.relative)
                #expect(spy.playCalls.isEmpty, "\(testCase.name) still started playback")
                #expect(spy.calls.isEmpty, "\(testCase.name) delegated an operation")
            }
        }
    }

    /// Malformed index text is still a *handled* command — it must not fall through to the timer
    /// handler — but it performs nothing.
    @Test func malformedIndexTextIsHandledAndPerformsNothing() {
        let malformed = [
            "skipToIndex:", "skipToIndex:abc", "skipToIndex:1.5",
            "skipToIndex: 2", "skipToIndex:--1", "skipToIndex:99999999999999999999"
        ]
        for command in malformed {
            withRecorder { spy in
                spy.queue = (0..<5).map { makeSong(id: "q\($0)") }
                spy.currentIndex = 0
                #expect(WatchPlaybackActions.handleSkipToIndexCommand(command),
                        "\(command) fell through instead of being handled")
                #expect(spy.playCalls.isEmpty, "\(command) started playback")
                #expect(spy.calls.isEmpty)
            }
        }
        // A command without the prefix must still fall through.
        #expect(WatchPlaybackActions.handleSkipToIndexCommand("next") == false)
    }

    /// The negative case that used to crash, driven through the real command string.
    @Test func negativeIndexCommandPerformsNothing() {
        withRecorder { spy in
            spy.queue = (0..<5).map { makeSong(id: "q\($0)") }
            spy.currentIndex = 0
            #expect(WatchPlaybackActions.handleSkipToIndexCommand("skipToIndex:-1"))
            #expect(WatchPlaybackActions.handleSkipToIndexCommand("skipToIndex:-9223372036854775808"))
            #expect(spy.playCalls.isEmpty, "a negative index reached the queue")
            #expect(spy.calls.isEmpty)
        }
    }

    /// Valid selection still delegates exactly once, through the command string, and the hardening
    /// changed none of the accepted mappings.
    @Test func validIndexCommandStillDelegatesExactlyOnce() {
        withRecorder { spy in
            spy.queue = (0..<5).map { makeSong(id: "q\($0)") }
            spy.currentIndex = 0
            #expect(WatchPlaybackActions.handleSkipToIndexCommand("skipToIndex:2"))
            #expect(spy.playCalls.count == 1, "a valid selection did not delegate exactly once")
            #expect(spy.playCalls.first?.songId == "q3")
            #expect(spy.playCalls.first?.index == 3)
        }
        // Nothing playing yet: row 0 is queue position 0.
        withRecorder { spy in
            spy.queue = [makeSong(id: "first"), makeSong(id: "second")]
            spy.currentIndex = -1
            #expect(WatchPlaybackActions.handleSkipToIndexCommand("skipToIndex:0"))
            #expect(spy.playCalls.count == 1)
            #expect(spy.playCalls.first?.songId == "first")
            #expect(spy.playCalls.first?.index == 0)
        }
    }

    /// Empty queue and last-track cases: addressable arithmetic, but no such position exists.
    @Test func emptyQueueAndFinalPositionPerformNothing() {
        withRecorder { spy in
            spy.queue = []
            spy.currentIndex = -1
            WatchPlaybackActions.skipToIndex(relative: 0)
            #expect(spy.playCalls.isEmpty, "an empty queue still started playback")
        }
        withRecorder { spy in
            spy.queue = [makeSong(id: "a"), makeSong(id: "b")]
            spy.currentIndex = 1                       // already the last track
            WatchPlaybackActions.skipToIndex(relative: 0)
            #expect(spy.playCalls.isEmpty, "selecting past the final track started playback")
        }
    }

    /// A rejected index must not reach the remote-command path either.
    @Test func rejectedIndexDoesNotDispatchThroughRemoteCommands() {
        #expect(RemoteCommandManager.shared.playbackOverride == nil,
                "a previous test leaked a remote-command override")
        let remoteSpy = PlaybackSpy()
        RemoteCommandManager.shared.playbackOverride = remoteSpy
        defer { RemoteCommandManager.shared.playbackOverride = nil }
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        withRecorder { watchSpy in
            watchSpy.queue = (0..<3).map { makeSong(id: "q\($0)") }
            watchSpy.currentIndex = 0
            WatchPlaybackActions.handleSkipToIndexCommand("skipToIndex:-1")
            WatchPlaybackActions.handleSkipToIndexCommand("skipToIndex:1")   // valid

            #expect(watchSpy.playCalls.count == 1, "only the valid selection should have played")
            #expect(remoteSpy.calls.isEmpty, "a Watch index selection dispatched through remote commands")
            #expect(remoteSpy.playCalls.isEmpty)
        }
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore)
    }

    /// Duplicate song ids across queue positions stay distinct: the mapping is positional.
    @Test func duplicateSongIdsDoNotCollapseWatchQueuePositions() {
        withRecorder { spy in
            let duplicate = makeSong(id: "same")
            spy.queue = [makeSong(id: "current"), duplicate, makeSong(id: "other"), duplicate]
            spy.currentIndex = 0

            WatchPlaybackActions.skipToIndex(relative: 0)
            WatchPlaybackActions.skipToIndex(relative: 2)

            #expect(spy.playCalls.map(\.index) == [1, 3],
                    "two rows holding the same song id resolved to the same queue position")
        }
    }

    // MARK: - Outbound state freshness

    /// The Now Playing context is rebuilt from live state on every send, and its keys are the wire
    /// contract with the Watch app.
    @Test func nowPlayingContextIsBuiltFromLiveState() {
        withRecorder { spy in
            spy.currentTime = 12
            spy.duration = 200
            spy.shuffleEnabled = false
            spy.repeatMode = .off
            spy.currentSong = makeSong(id: "a", starred: nil)
            spy.upNext = [makeSong(id: "b", title: "Next One")]

            let first = WatchPlaybackActions.nowPlayingContext(
                title: "T", artist: "A", album: "Al", isPlaying: true
            )

            // Wire contract: exactly these keys, unchanged.
            #expect(Set(first.keys) == [
                "title", "artist", "album", "isPlaying", "elapsed", "duration",
                "isStarred", "isShuffleOn", "repeatMode", "sleepTimerActive", "queue"
            ], "the Now Playing payload shape changed")
            #expect(first["elapsed"] as? TimeInterval == 12)
            #expect(first["duration"] as? TimeInterval == 200)
            #expect(first["isStarred"] as? Bool == false)
            #expect(first["isShuffleOn"] as? Bool == false)
            #expect(first["repeatMode"] as? String == "off")
            #expect((first["queue"] as? [[String: String]])?.count == 1)

            // Everything moves; the next payload must reflect it rather than a snapshot.
            spy.currentTime = 99
            spy.duration = 250
            spy.shuffleEnabled = true
            spy.repeatMode = .one
            spy.currentSong = makeSong(id: "a", starred: "2026-01-01T00:00:00Z")
            spy.upNext = [makeSong(id: "b"), makeSong(id: "c")]

            let second = WatchPlaybackActions.nowPlayingContext(
                title: "T", artist: "A", album: "Al", isPlaying: false
            )
            #expect(second["elapsed"] as? TimeInterval == 99, "elapsed came from a cached snapshot")
            #expect(second["duration"] as? TimeInterval == 250)
            #expect(second["isStarred"] as? Bool == true)
            #expect(second["isShuffleOn"] as? Bool == true)
            #expect(second["repeatMode"] as? String == "one")
            #expect((second["queue"] as? [[String: String]])?.count == 2,
                    "the queue payload came from a cached snapshot")
        }
    }

    /// The Watch queue list is capped at 20 entries, unchanged.
    @Test func nowPlayingQueuePayloadIsCappedAtTwenty() {
        withRecorder { spy in
            spy.upNext = (0..<40).map { makeSong(id: "t\($0)") }
            let context = WatchPlaybackActions.nowPlayingContext(
                title: "T", artist: "A", album: "Al", isPlaying: true
            )
            #expect((context["queue"] as? [[String: String]])?.count == 20,
                    "the Watch queue cap changed")
        }
    }

    /// The lighter play/pause payload keeps its three keys and reads elapsed live.
    @Test func playbackStateContextShapeIsUnchanged() {
        withRecorder { spy in
            spy.currentTime = 7
            let context = WatchPlaybackActions.playbackStateContext(isPlaying: true)
            #expect(Set(context.keys) == ["isPlaying", "elapsed", "sleepTimerActive"],
                    "the playback-state payload shape changed")
            #expect(context["isPlaying"] as? Bool == true)
            #expect(context["elapsed"] as? TimeInterval == 7)
        }
    }

    /// A track change after the manager exists must show up in the next payload — proving the
    /// manager holds no snapshot of its own.
    @Test func stateChangesAfterConstructionAppearInTheNextPayload() {
        _ = WatchSessionManager.shared
        withRecorder { spy in
            spy.currentSong = makeSong(id: "before")
            spy.currentTime = 1
            #expect(WatchPlaybackActions.nowPlayingContext(
                title: "T", artist: "A", album: "Al", isPlaying: true)["elapsed"] as? TimeInterval == 1)

            spy.currentSong = makeSong(id: "after")
            spy.currentTime = 42
            #expect(WatchPlaybackActions.nowPlayingContext(
                title: "T", artist: "A", album: "Al", isPlaying: true)["elapsed"] as? TimeInterval == 42,
                    "the manager reported state captured at construction time")
        }
    }

    // MARK: - Double dispatch

    /// A Watch message must not also travel the remote-command path. The two expose the same user
    /// actions but are independent routes, and one incoming event must use exactly one of them.
    @Test func watchCommandDoesNotAlsoInvokeRemoteCommandManager() {
        let registrationsBefore = RemoteCommandManager.shared.registrationCount
        #expect(RemoteCommandManager.shared.playbackOverride == nil,
                "a previous test leaked a remote-command override")

        // The remote path gets its own recorder. If a watch command reached it, this would record.
        let remoteSpy = PlaybackSpy()
        RemoteCommandManager.shared.playbackOverride = remoteSpy
        defer { RemoteCommandManager.shared.playbackOverride = nil }

        withRecorder { watchSpy in
            WatchPlaybackActions.handlePlaybackCommand("togglePlayPause", volume: nil)
            WatchPlaybackActions.handlePlaybackCommand("next", volume: nil)
            WatchPlaybackActions.handlePlaybackCommand("previous", volume: nil)

            #expect(watchSpy.calls == ["togglePlayPause", "next", "previous"])
            #expect(remoteSpy.calls.isEmpty,
                    "a Watch command also dispatched through RemoteCommandManager")
            #expect(remoteSpy.playCalls.isEmpty)
        }

        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore,
                "handling a Watch command registered remote command handlers")
    }

    /// One Watch command produces exactly one legacy engine operation through the real production
    /// wiring. `updateQueueSongRating` against an absent id is used because it is a guarded no-op in
    /// the engine, so the delegation is counted without touching audio.
    @Test func oneWatchCommandProducesOneLegacyOperation() {
        guard let adapter = ApplicationPlayback.legacyAdapter else {
            Issue.record("the façade did not resolve to the legacy adapter")
            return
        }
        #expect(WatchPlaybackActions.playbackOverride == nil, "a previous test leaked an override")
        #expect(WatchPlaybackActions.playback === ApplicationPlayback.shared,
                "the Watch layer resolved a second façade")

        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        adapter.resetDelegationCounts()

        // Shuffle is safe to drive live: it mutates a flag, starts no audio, and is restored below.
        let shuffleBefore = engine.shuffleEnabled
        WatchPlaybackActions.handlePlaybackCommand("toggleShuffle", volume: nil)
        #expect(adapter.delegatedCallCounts["toggleShuffle"] == 1,
                "one Watch command produced \(adapter.delegatedCallCounts["toggleShuffle"] ?? 0) engine calls")
        #expect(engine.shuffleEnabled != shuffleBefore, "the command did not reach the engine")
        WatchPlaybackActions.handlePlaybackCommand("toggleShuffle", volume: nil)   // restore
        #expect(engine.shuffleEnabled == shuffleBefore)
        #expect(engine.isPlaying == playingBefore, "a Watch command started playback")
        adapter.resetDelegationCounts()
    }

    // MARK: - Construction

    /// Resolving the Watch layer must start nothing. `WatchSessionManager.shared` activates a real
    /// `WCSession`; that is watch connectivity, not audio, and it must stay that way.
    @Test func resolvingTheWatchLayerStartsNothing() {
        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let queueBefore = engine.queue.count
        let indexBefore = engine.currentIndex
        let categoryBefore = AVAudioSession.sharedInstance().category
        let modeBefore = AVAudioSession.sharedInstance().mode
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        let manager = WatchSessionManager.shared
        for _ in 0..<50 {
            #expect(WatchSessionManager.shared === manager, "a second WatchSessionManager appeared")
            #expect(WatchPlaybackActions.playback === ApplicationPlayback.shared,
                    "a second façade was created")
        }

        #expect(engine.isPlaying == playingBefore, "resolving the Watch layer started playback")
        #expect(engine.queue.count == queueBefore)
        #expect(engine.currentIndex == indexBefore)
        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "resolving the Watch layer configured the audio session")
        #expect(AVAudioSession.sharedInstance().mode == modeBefore)
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore,
                "the Watch layer registered a second set of remote command handlers")
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "the Watch layer constructed a persistent playback controller")
    }

    /// The DEBUG override defaults to nil, falls back to the composition point, and is restored.
    @Test func testSeamDefaultsToProductionWiring() {
        #expect(WatchPlaybackActions.playbackOverride == nil,
                "the Watch façade override leaked out of a previous test")
        #expect(WatchPlaybackActions.playback === ApplicationPlayback.shared)

        withRecorder { spy in
            #expect(WatchPlaybackActions.playback === spy)
        }
        #expect(WatchPlaybackActions.playback === ApplicationPlayback.shared,
                "the override was not restored after use")
    }

    /// Lane 2C-B moves one file. The persistent engine stays unwired.
    @Test func persistentPlaybackRemainsUnwired() {
        #expect(GaplessDiagnosticsRegistry.current == nil)
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the façade resolved to something other than the legacy adapter")
    }
}
#endif
