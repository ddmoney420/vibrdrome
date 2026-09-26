#if os(iOS)
import Foundation
import Testing
@testable import Vibrdrome

import AVFoundation

/// Lane 2C-A: `CarPlayManager` now reaches playback through `ApplicationPlayback.shared`.
///
/// **What is and is not testable here.** `CPInterfaceController` has no public initialiser, so
/// `CarPlayManager` itself cannot be constructed in a test. Every playback-triggering handler in it
/// therefore calls a named method on `CarPlayPlaybackActions` and does nothing else, and those
/// methods are what this suite drives — the same code path a tap in the car runs. Template
/// construction, navigation and the `CPInterfaceController` hierarchy are not reachable from a unit
/// test and are unchanged by this lane.
///
/// **CarPlay has no transport handlers.** Play, pause, toggle, next and previous never reach
/// `CarPlayManager`: CarPlay raises them through `MPRemoteCommandCenter`, which
/// `RemoteCommandManager` owns and Lane 2B already migrated. That is also why this migration cannot
/// double-dispatch — there is no second path for a transport command to travel. The actions below
/// are CarPlay's entire playback surface.
///
/// **No real audio.** The façade is overridden with a recorder; `play` and `skipToIndex` would
/// otherwise start AVQueuePlayer while the gapless real-time suites are running.
@Suite(.serialized)
@MainActor
struct CarPlayPlaybackMigrationTests {

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

    /// Runs `body` with a recording façade installed, and always restores production wiring.
    private func withRecorder(_ body: (PlaybackSpy) -> Void) {
        let spy = PlaybackSpy()
        CarPlayPlaybackActions.playbackOverride = spy
        defer { CarPlayPlaybackActions.playbackOverride = nil }
        body(spy)
    }

    // MARK: - Routing and exactly-once

    /// Each CarPlay action produces exactly one façade operation and nothing else.
    ///
    /// This also proves the routing: with the façade overridden, an action that still called
    /// `AudioEngine.shared` directly would record nothing at all here.
    @Test func eachCarPlayActionDelegatesExactlyOnce() {
        let song = makeSong(id: "a")
        let queue = [song, makeSong(id: "b")]
        let station = InternetRadioStation(
            id: "s1", name: "Probe FM", streamUrl: "https://example.invalid/s",
            homePageUrl: nil, coverArt: nil
        )

        let cases: [(name: String, action: @MainActor () -> Void)] = [
            ("toggleShuffle", { CarPlayPlaybackActions.toggleShuffle() }),
            ("cycleRepeatMode", { CarPlayPlaybackActions.cycleRepeatMode() }),
            ("skipToIndex", { CarPlayPlaybackActions.selectUpNext(offset: 0) }),
            ("playRadio", { CarPlayPlaybackActions.playRadio(station: station) }),
            ("startRadio", { CarPlayPlaybackActions.startRadio(artistName: "Probe") })
        ]

        for testCase in cases {
            withRecorder { spy in
                testCase.action()
                #expect(spy.calls == [testCase.name],
                        "\(testCase.name) produced \(spy.calls) instead of exactly one call")
                #expect(spy.playCalls.isEmpty, "\(testCase.name) also started a track")
            }
        }

        // Playing a song from a CarPlay list, both overloads.
        withRecorder { spy in
            CarPlayPlaybackActions.play(song: song, from: queue, at: 1)
            #expect(spy.playCalls.count == 1, "song selection did not delegate exactly once")
            #expect(spy.playCalls.first?.songId == "a")
            #expect(spy.playCalls.first?.index == 1)
            #expect(spy.calls.isEmpty, "song selection delegated an unrelated operation")
        }
        withRecorder { spy in
            CarPlayPlaybackActions.play(song: song, from: queue)
            #expect(spy.playCalls.count == 1, "Play All did not delegate exactly once")
            #expect(spy.playCalls.first?.index == 0, "Play All must start at index 0")
        }
    }

    // MARK: - Queue index mapping

    /// The Up Next mapping is `currentIndex + 1 + offset`, unchanged by the migration. Selecting the
    /// first row plays the next track, not the current one.
    @Test func upNextMappingIsUnchangedPositionalArithmetic() {
        #expect(CarPlayPlaybackActions.upNextAbsoluteIndex(currentIndex: 0, offset: 0) == 1)
        #expect(CarPlayPlaybackActions.upNextAbsoluteIndex(currentIndex: 0, offset: 1) == 2)
        #expect(CarPlayPlaybackActions.upNextAbsoluteIndex(currentIndex: 4, offset: 3) == 8)
        // Nothing playing yet: currentIndex is -1, so the first up-next row is queue position 0.
        #expect(CarPlayPlaybackActions.upNextAbsoluteIndex(currentIndex: -1, offset: 0) == 0)
    }

    /// `currentIndex` is read when the row is tapped, not when the template was built — so a queue
    /// that advanced while the list was on screen resolves against the queue as it is now. That is
    /// the pre-existing behaviour and the migration must not "fix" it.
    @Test func upNextSelectionReadsCurrentIndexAtTapTime() {
        withRecorder { spy in
            spy.currentIndex = 2
            CarPlayPlaybackActions.selectUpNext(offset: 0)
            #expect(spy.skipToIndexCalls == [3])

            // Playback moves on while the same template is still displayed. The same row (offset 0)
            // must now resolve to 5 + 1 + 0 = 6, not to the 3 it would give if currentIndex had been
            // captured when the template was built.
            spy.currentIndex = 5
            CarPlayPlaybackActions.selectUpNext(offset: 0)
            #expect(spy.skipToIndexCalls == [3, 6],
                    "the row resolved against a stale currentIndex captured at build time")
        }
    }

    /// The mapping is positional, never identity-based. Two queue positions holding the same song id
    /// must stay distinct — matching by id would collapse both rows onto the first occurrence.
    @Test func duplicateSongIdsDoNotCollapseQueuePositions() {
        withRecorder { spy in
            let duplicate = makeSong(id: "same")
            spy.currentIndex = 0
            spy.queue = [makeSong(id: "current"), duplicate, makeSong(id: "other"), duplicate]
            spy.upNext = [duplicate, makeSong(id: "other"), duplicate]

            CarPlayPlaybackActions.selectUpNext(offset: 0)   // first copy  -> absolute 1
            CarPlayPlaybackActions.selectUpNext(offset: 2)   // second copy -> absolute 3

            #expect(spy.skipToIndexCalls == [1, 3],
                    "two rows holding the same song id resolved to the same queue position")
        }
    }

    /// A stale or out-of-range row passes its computed index straight through, exactly as before.
    /// Range handling belongs to the engine; the migration must not introduce clamping of its own.
    @Test func staleSelectionPassesThroughWithoutNewClamping() {
        withRecorder { spy in
            spy.currentIndex = 0
            spy.queue = [makeSong(id: "only")]
            spy.upNext = []

            CarPlayPlaybackActions.selectUpNext(offset: 99)

            #expect(spy.skipToIndexCalls == [100],
                    "the migration added clamping that did not exist before")
        }
    }

    // MARK: - Live state

    /// CarPlay reads state live off the singleton rather than snapshotting it into a second model.
    @Test func carPlayReadsPlaybackStateLive() {
        let engine = AudioEngine.shared
        #expect(CarPlayPlaybackActions.playbackOverride == nil, "a previous test leaked an override")

        let queueBefore = engine.queue
        let indexBefore = engine.currentIndex
        let contextBefore = engine.playingFromContext
        defer {
            engine.queue = queueBefore
            engine.currentIndex = indexBefore
            engine.playingFromContext = contextBefore
        }

        let facade = CarPlayPlaybackActions.playback
        #expect(facade === ApplicationPlayback.shared, "CarPlay resolved a second façade")

        // Queue updates are visible through the same façade instance — no re-resolution needed.
        engine.queue = [makeSong(id: "q0"), makeSong(id: "q1"), makeSong(id: "q2")]
        engine.currentIndex = 0
        #expect(facade.queue.count == 3, "CarPlay is holding a stale queue snapshot")
        #expect(facade.currentIndex == 0)
        #expect(facade.upNext.map(\.id) == ["q1", "q2"], "upNext did not follow the live queue")

        engine.currentIndex = 1
        #expect(facade.upNext.map(\.id) == ["q2"], "upNext did not follow the moving current index")
        #expect(facade.currentSong?.id == engine.currentSong?.id)
        #expect(facade.isPlaying == engine.isPlaying)
        #expect(facade.repeatMode == engine.repeatMode)
        #expect(facade.shuffleEnabled == engine.shuffleEnabled)

        engine.playingFromContext = "CarPlay probe"
        #expect(facade.playingFromContext == "CarPlay probe")
    }

    /// `upNext` and `upNextEntries` are different members and must stay that way: under shuffle,
    /// `upNextEntries` returns true playback order capped at five, while CarPlay's list is the raw
    /// linear tail. Reading the wrong one would silently reorder and truncate the Up Next screen.
    @Test func upNextIsTheLinearTailNotTheShuffleAwareEntries() {
        let engine = AudioEngine.shared
        let queueBefore = engine.queue
        let indexBefore = engine.currentIndex
        defer {
            engine.queue = queueBefore
            engine.currentIndex = indexBefore
        }

        engine.queue = (0..<9).map { makeSong(id: "t\($0)") }
        engine.currentIndex = 0

        let facade = ApplicationPlayback.shared
        #expect(facade.upNext.count == 8, "upNext is not the full linear tail")
        #expect(facade.upNext.map(\.id) == (1..<9).map { "t\($0)" },
                "upNext is not in linear queue order")
    }

    // MARK: - Construction and ownership

    /// Resolving CarPlay's playback seam must start nothing. `CarPlayManager` itself cannot be
    /// constructed here (`CPInterfaceController` has no public initialiser), so this covers the part
    /// of its construction that touches playback: the façade resolution its init performs via
    /// `configureNowPlayingTemplate`.
    @Test func resolvingCarPlayPlaybackStartsNothing() {
        let engine = AudioEngine.shared
        let playingBefore = engine.isPlaying
        let queueBefore = engine.queue.count
        let indexBefore = engine.currentIndex
        let categoryBefore = AVAudioSession.sharedInstance().category
        let modeBefore = AVAudioSession.sharedInstance().mode
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        for _ in 0..<100 {
            let facade = CarPlayPlaybackActions.playback
            _ = facade.currentSong
            _ = facade.isPlaying
            _ = facade.currentTime
            _ = facade.upNext
            #expect(facade === ApplicationPlayback.shared, "a second façade was created")
        }

        #expect(engine.isPlaying == playingBefore, "resolving CarPlay playback started playback")
        #expect(engine.queue.count == queueBefore)
        #expect(engine.currentIndex == indexBefore)
        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "resolving CarPlay playback configured the audio session")
        #expect(AVAudioSession.sharedInstance().mode == modeBefore)
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore,
                "CarPlay registered a second set of remote command handlers")
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "CarPlay constructed a persistent playback controller")
    }

    /// The DEBUG override defaults to nil, falls back to the composition point, and does not leak
    /// between tests.
    @Test func testSeamDefaultsToProductionWiring() {
        #expect(CarPlayPlaybackActions.playbackOverride == nil,
                "the CarPlay façade override leaked out of a previous test")
        #expect(CarPlayPlaybackActions.playback === ApplicationPlayback.shared)

        withRecorder { spy in
            #expect(CarPlayPlaybackActions.playback === spy)
        }
        #expect(CarPlayPlaybackActions.playback === ApplicationPlayback.shared,
                "the override was not restored after use")
    }

    /// Lane 2C-A moves one file. The persistent engine stays unwired.
    @Test func persistentPlaybackRemainsUnwired() {
        #expect(GaplessDiagnosticsRegistry.current == nil)
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the façade resolved to something other than the legacy adapter")
    }
}
#endif
