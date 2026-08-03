import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Now Playing and scrobble accounting driven from audible evidence.
///
/// The property under test throughout: nothing is published or submitted because a track was
/// prepared, decoded or scheduled — only because it was *heard*. On this architecture those moments
/// are a whole track apart.
@MainActor
struct GaplessSystemIntegrationTests {
    static let sampleRate = 44_100.0

    static func update(song: String, item: UInt64, instance: UInt64, queueGeneration: UInt64 = 1,
                       tailGeneration: UInt64 = 1, index: Int = 0,
                       startFrame: AVAudioFramePosition = 0) -> GaplessNowPlayingUpdate {
        GaplessNowPlayingUpdate(
            songID: song, itemID: GaplessQueueItemID(rawValue: item),
            playInstance: GaplessPlayInstanceID(rawValue: instance),
            queueGeneration: queueGeneration, tailGeneration: tailGeneration,
            scheduledStartFrame: startFrame, observedRenderFrame: startFrame,
            queueIndex: index, elapsedSeconds: 0, isPlaying: true)
    }

    // MARK: - Now Playing at the audible boundary

    @Test func metadataPublishesOnlyWhenATrackBecomesAudible() {
        let bridge = GaplessNowPlayingBridge()
        var published: [String] = []
        bridge.publishMetadata = { published.append($0.songID) }

        // Preparing and scheduling publish nothing — there is simply no entry point for them.
        #expect(published.isEmpty)

        bridge.trackBecameAudible(Self.update(song: "a", item: 1, instance: 1))
        #expect(published == ["a"])

        bridge.trackBecameAudible(Self.update(song: "b", item: 2, instance: 2, index: 1,
                                              startFrame: 441_000))
        #expect(published == ["a", "b"])
        #expect(bridge.lastUpdate?.songID == "b")
        #expect(bridge.lastUpdate?.queueIndex == 1)
    }

    /// A boundary from a superseded tail describes audio that will never be heard.
    @Test func staleTailUpdateIsRejected() {
        let bridge = GaplessNowPlayingBridge()
        var published: [String] = []
        bridge.publishMetadata = { published.append($0.songID) }
        bridge.trackBecameAudible(Self.update(song: "current", item: 1, instance: 1,
                                              tailGeneration: 5))

        bridge.trackBecameAudible(Self.update(song: "stale", item: 2, instance: 2,
                                              tailGeneration: 4))

        #expect(published == ["current"])
        #expect(bridge.rejectedStaleUpdates == 1)
    }

    @Test func staleQueueGenerationUpdateIsRejected() {
        let bridge = GaplessNowPlayingBridge()
        var published: [String] = []
        bridge.publishMetadata = { published.append($0.songID) }
        bridge.trackBecameAudible(Self.update(song: "current", item: 1, instance: 1,
                                              queueGeneration: 3))

        bridge.trackBecameAudible(Self.update(song: "stale", item: 2, instance: 2,
                                              queueGeneration: 2, tailGeneration: 99))

        #expect(published == ["current"])
        #expect(bridge.rejectedStaleUpdates == 1)
    }

    // MARK: - Elapsed time

    /// `MPNowPlayingInfoCenter` is a system-wide service; a per-render-slice update would be
    /// thousands of writes a second.
    @Test func elapsedPublishingIsRateLimited() {
        let bridge = GaplessNowPlayingBridge()
        var writes = 0
        bridge.publishElapsed = { _, _ in writes += 1 }
        let start = Date()

        #expect(bridge.publishElapsed(seconds: 1, isPlaying: true, now: start))
        // Immediately after, suppressed.
        #expect(!bridge.publishElapsed(seconds: 1.05, isPlaying: true, now: start.addingTimeInterval(0.05)))
        #expect(!bridge.publishElapsed(seconds: 1.5, isPlaying: true, now: start.addingTimeInterval(0.5)))
        // Past the interval, allowed again.
        #expect(bridge.publishElapsed(seconds: 2, isPlaying: true, now: start.addingTimeInterval(1.1)))
        #expect(writes == 2)
    }

    /// Pause, resume and seek must not wait for the next tick — the lock screen would be visibly
    /// wrong for up to a second.
    @Test func immediatePublishBypassesTheRateLimit() {
        let bridge = GaplessNowPlayingBridge()
        var values: [TimeInterval] = []
        bridge.publishElapsed = { seconds, _ in values.append(seconds) }

        bridge.publishElapsed(seconds: 5, isPlaying: true)
        bridge.publishElapsedImmediately(seconds: 0, isPlaying: false)   // a seek to zero
        bridge.publishElapsedImmediately(seconds: 0, isPlaying: true)    // resume

        #expect(values == [5, 0, 0])
    }

    /// A new audible track resets the rate limit, so its elapsed time appears at once.
    @Test func aNewTrackPublishesElapsedImmediately() {
        let bridge = GaplessNowPlayingBridge()
        var writes = 0
        bridge.publishElapsed = { _, _ in writes += 1 }
        bridge.publishElapsed(seconds: 10, isPlaying: true)
        #expect(writes == 1)

        bridge.trackBecameAudible(Self.update(song: "next", item: 2, instance: 2))
        #expect(bridge.publishElapsed(seconds: 0, isPlaying: true))
        #expect(writes == 2)
    }

    // MARK: - Artwork races

    /// Artwork is fetched ahead and can complete after the user has moved on.
    @Test func lateArtworkForAPreviousPlayIsDiscarded() {
        let bridge = GaplessNowPlayingBridge()
        var artworkFor: [String] = []
        bridge.publishArtwork = { artworkFor.append($0) }
        bridge.trackBecameAudible(Self.update(song: "first", item: 1, instance: 1))
        let firstInstance = GaplessPlayInstanceID(rawValue: 1)

        // User skips; a new track becomes audible.
        bridge.trackBecameAudible(Self.update(song: "second", item: 2, instance: 2))

        // The first track's artwork finally arrives — far too late.
        #expect(!bridge.publishArtwork(songID: "first", for: firstInstance))
        #expect(artworkFor.isEmpty)
        // The current track's artwork is accepted.
        #expect(bridge.publishArtwork(songID: "second", for: GaplessPlayInstanceID(rawValue: 2)))
        #expect(artworkFor == ["second"])
    }

    /// The same song in two queue slots, and the same slot replayed, are different plays — so
    /// artwork keyed on song ID would accept a stale completion.
    @Test func artworkIsKeyedOnPlayInstanceNotSong() {
        let bridge = GaplessNowPlayingBridge()
        var artworkFor: [String] = []
        bridge.publishArtwork = { artworkFor.append($0) }
        // Same song, same slot, replayed under Repeat One → different instances.
        bridge.trackBecameAudible(Self.update(song: "loop", item: 1, instance: 1))
        bridge.trackBecameAudible(Self.update(song: "loop", item: 1, instance: 2))

        #expect(!bridge.publishArtwork(songID: "loop", for: GaplessPlayInstanceID(rawValue: 1)))
        #expect(bridge.publishArtwork(songID: "loop", for: GaplessPlayInstanceID(rawValue: 2)))
        #expect(artworkFor == ["loop"])
    }

    // MARK: - Scrobble policy parity

    /// Production policy: half the effective duration, capped at 240 s.
    @Test func thresholdMatchesProduction() {
        let reporter = GaplessScrobbleReporter(sampleRate: Self.sampleRate)

        #expect(reporter.thresholdFrames(durationSeconds: 200)
                == AVAudioFramePosition(100 * Self.sampleRate))
        // The 240 s cap applies to long tracks.
        #expect(reporter.thresholdFrames(durationSeconds: 1_200)
                == AVAudioFramePosition(240 * Self.sampleRate))
    }

    @Test func aFullPlaySubmitsOnceAndASkippedPlayDoesNot() {
        let reporter = GaplessScrobbleReporter(sampleRate: Self.sampleRate)
        var submitted: [String] = []
        reporter.submit = { submitted.append($0.songID) }
        let duration: TimeInterval = 100

        // Skipped early — under the 50 s threshold.
        _ = reporter.playEnded(songID: "skipped", itemID: GaplessQueueItemID(rawValue: 1),
                               playInstance: GaplessPlayInstanceID(rawValue: 1),
                               audibleFrames: AVAudioFramePosition(20 * Self.sampleRate),
                               durationSeconds: duration)
        #expect(submitted.isEmpty)

        // Played past the threshold.
        _ = reporter.playEnded(songID: "played", itemID: GaplessQueueItemID(rawValue: 2),
                               playInstance: GaplessPlayInstanceID(rawValue: 2),
                               audibleFrames: AVAudioFramePosition(60 * Self.sampleRate),
                               durationSeconds: duration)
        #expect(submitted == ["played"])
    }

    /// The core guarantee: one submission per play instance, ever.
    @Test func aPlayInstanceNeverSubmitsTwice() {
        let reporter = GaplessScrobbleReporter(sampleRate: Self.sampleRate)
        var submitted = 0
        reporter.submit = { _ in submitted += 1 }
        let instance = GaplessPlayInstanceID(rawValue: 7)

        for _ in 0..<5 {
            _ = reporter.playEnded(songID: "s", itemID: GaplessQueueItemID(rawValue: 1),
                                   playInstance: instance,
                                   audibleFrames: AVAudioFramePosition(60 * Self.sampleRate),
                                   durationSeconds: 100)
        }

        #expect(submitted == 1)
    }

    /// Repeat One: the same slot, played fully three times, is three plays and three scrobbles.
    @Test func repeatOneScrobblesOncePerCompletedReplay() {
        let reporter = GaplessScrobbleReporter(sampleRate: Self.sampleRate)
        var submitted: [String] = []
        reporter.submit = { submitted.append($0.songID) }
        let slot = GaplessQueueItemID(rawValue: 1)

        for instance in UInt64(1)...3 {
            _ = reporter.playEnded(songID: "loop", itemID: slot,
                                   playInstance: GaplessPlayInstanceID(rawValue: instance),
                                   audibleFrames: AVAudioFramePosition(60 * Self.sampleRate),
                                   durationSeconds: 100)
        }

        #expect(submitted == ["loop", "loop", "loop"])
        #expect(reporter.submissionCount(forSongID: "loop") == 3)
    }

    /// The same song in two different queue slots is two independent plays.
    @Test func duplicateSongInTwoSlotsScrobblesTwice() {
        let reporter = GaplessScrobbleReporter(sampleRate: Self.sampleRate)
        var submitted = 0
        reporter.submit = { _ in submitted += 1 }

        _ = reporter.playEnded(songID: "same", itemID: GaplessQueueItemID(rawValue: 1),
                               playInstance: GaplessPlayInstanceID(rawValue: 1),
                               audibleFrames: AVAudioFramePosition(60 * Self.sampleRate),
                               durationSeconds: 100)
        _ = reporter.playEnded(songID: "same", itemID: GaplessQueueItemID(rawValue: 2),
                               playInstance: GaplessPlayInstanceID(rawValue: 2),
                               audibleFrames: AVAudioFramePosition(60 * Self.sampleRate),
                               durationSeconds: 100)

        #expect(submitted == 2)
    }

    /// Seeking backwards resets what has been heard, so a play that was past the threshold and is
    /// then rewound must not submit on the strength of audio it no longer played.
    @Test func seekBackwardBelowThresholdDoesNotSubmit() {
        let reporter = GaplessScrobbleReporter(sampleRate: Self.sampleRate)
        var submitted = 0
        reporter.submit = { _ in submitted += 1 }

        // After a backward seek the audible-frame count restarts, which is what the session does.
        _ = reporter.playEnded(songID: "rewound", itemID: GaplessQueueItemID(rawValue: 1),
                               playInstance: GaplessPlayInstanceID(rawValue: 1),
                               audibleFrames: AVAudioFramePosition(10 * Self.sampleRate),
                               durationSeconds: 100)

        #expect(submitted == 0)
    }

    /// Seeking forward must not credit audio that was skipped over.
    @Test func seekForwardDoesNotCreditUnheardAudio() {
        let reporter = GaplessScrobbleReporter(sampleRate: Self.sampleRate)
        var submitted = 0
        reporter.submit = { _ in submitted += 1 }

        // Jumped to 90 s in, then heard 5 s: 5 s of audible evidence, not 95 s.
        _ = reporter.playEnded(songID: "jumped", itemID: GaplessQueueItemID(rawValue: 1),
                               playInstance: GaplessPlayInstanceID(rawValue: 1),
                               audibleFrames: AVAudioFramePosition(5 * Self.sampleRate),
                               durationSeconds: 100)

        #expect(submitted == 0)
    }

    /// Preparation, decode and scheduling are not plays. Zero audible frames never counts.
    @Test func nothingIsSubmittedWithoutAudibleFrames() {
        let reporter = GaplessScrobbleReporter(sampleRate: Self.sampleRate)
        var submitted = 0
        reporter.submit = { _ in submitted += 1 }

        _ = reporter.playEnded(songID: "never-heard", itemID: GaplessQueueItemID(rawValue: 1),
                               playInstance: GaplessPlayInstanceID(rawValue: 1),
                               audibleFrames: 0, durationSeconds: 100)
        // A track with no known duration cannot be judged, so it is not submitted.
        _ = reporter.playEnded(songID: "unknown-duration", itemID: GaplessQueueItemID(rawValue: 2),
                               playInstance: GaplessPlayInstanceID(rawValue: 2),
                               audibleFrames: AVAudioFramePosition(60 * Self.sampleRate),
                               durationSeconds: 0)

        #expect(submitted == 0)
    }

    /// "Now playing" fires once per play, at the boundary — not once per song.
    @Test func nowPlayingAnnouncementIsOncePerPlayInstance() {
        let reporter = GaplessScrobbleReporter(sampleRate: Self.sampleRate)
        var announced: [String] = []
        reporter.announceNowPlaying = { announced.append($0) }

        #expect(reporter.announce(songID: "a", playInstance: GaplessPlayInstanceID(rawValue: 1)))
        #expect(!reporter.announce(songID: "a", playInstance: GaplessPlayInstanceID(rawValue: 1)))
        // A replay of the same song is a new play, so it announces again.
        #expect(reporter.announce(songID: "a", playInstance: GaplessPlayInstanceID(rawValue: 2)))

        #expect(announced == ["a", "a"])
    }

    // MARK: - Session wiring: the two agree

    /// The session's completion events and the reporter must agree, since both derive from the same
    /// audible-frame accounting.
    @Test func sessionCompletionEventsDriveScrobblingConsistently() {
        let session = GaplessPlaybackSession(sampleRate: Self.sampleRate)
        session.replaceQueue(songIDs: ["one", "two"])
        session.songDurations = ["one": 10, "two": 10]
        session.play()
        let ids = session.queue.items.map(\.id)
        let reporter = GaplessScrobbleReporter(sampleRate: Self.sampleRate)
        var submitted: [String] = []
        reporter.submit = { submitted.append($0.songID) }

        // Play track one fully, then let track two start.
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        session.advance(renderedFrames: AVAudioFramePosition(9 * Self.sampleRate), boundaries: [])
        session.advance(renderedFrames: 1,
                        boundaries: [(ids[1], AVAudioFramePosition(9 * Self.sampleRate) + 1)])

        // Feed the session's own completion events into the reporter.
        var instance: UInt64 = 0
        for event in session.events {
            if case .completed(let itemID, let songID, let frames, let eligible) = event {
                instance += 1
                let submission = reporter.playEnded(
                    songID: songID, itemID: itemID,
                    playInstance: GaplessPlayInstanceID(rawValue: instance),
                    audibleFrames: frames, durationSeconds: 10)
                // The session's own eligibility verdict and the reporter's must match.
                #expect((submission != nil) == eligible, "disagreement for \(songID)")
            }
        }
        #expect(submitted == ["one"])
    }
}
