import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Queue, repeat, shuffle, mutation and transport behaviour for the persistent engine.
///
/// Everything here is driven by *rendered frames*, never by preparation, so the tests exercise the
/// same decision path production will: a track becomes audible when its frames are rendered, and
/// completion and scrobble eligibility follow from what was actually heard.
@MainActor
struct GaplessPlaybackSessionTests {
    static let sampleRate = 44_100.0
    /// 10-second tracks, so scrobble thresholds land at 5 s (half), well inside the 240 s cap.
    static let trackFrames = AVAudioFramePosition(441_000)
    static let trackSeconds: TimeInterval = 10

    static func makeSession(_ songIDs: [String]) -> GaplessPlaybackSession {
        let session = GaplessPlaybackSession(sampleRate: sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = trackSeconds }
        session.play()
        return session
    }

    /// Render `count` whole tracks, emitting each item's boundary at its start frame — the shape the
    /// engine's render loop produces.
    @discardableResult
    static func renderTracks(_ session: GaplessPlaybackSession, itemIDs: [GaplessQueueItemID],
                             fraction: Double = 1.0) -> AVAudioFramePosition {
        var frame: AVAudioFramePosition = 0
        for itemID in itemIDs {
            session.advance(renderedFrames: 1, boundaries: [(itemID, frame)])
            let remaining = AVAudioFramePosition(Double(trackFrames) * fraction) - 1
            if remaining > 0 { session.advance(renderedFrames: remaining, boundaries: []) }
            frame += AVAudioFramePosition(Double(trackFrames) * fraction)
        }
        return frame
    }

    static func audibleOrder(_ session: GaplessPlaybackSession) -> [String] {
        session.events.compactMap {
            if case .becameAudible(_, let songID, _) = $0 { return songID }
            return nil
        }
    }

    static func scrobbledSongs(_ session: GaplessPlaybackSession) -> [String] {
        session.events.compactMap {
            if case .completed(_, let songID, _, let eligible) = $0, eligible { return songID }
            return nil
        }
    }

    // MARK: - Queue identity and generation

    /// The same song can occupy two slots; scheduling state must not be shared between them.
    @Test func duplicateSongsGetDistinctQueueIdentities() {
        var queue = GaplessPlaybackQueue()
        queue.replace(songIDs: ["a", "b", "a"])

        let ids = queue.items.map(\.id)
        #expect(Set(ids).count == 3)
        #expect(queue.items[0].songID == queue.items[2].songID)
        #expect(queue.items[0].id != queue.items[2].id)
    }

    @Test func structuralChangesBumpTheGenerationAndAdvancingDoesNot() {
        var queue = GaplessPlaybackQueue()
        queue.replace(songIDs: ["a", "b", "c"])
        let afterReplace = queue.generation

        queue.setCurrentIndex(1)
        // Advancing through the queue is not a structural change — bumping here would needlessly
        // invalidate preparation that is still correct.
        #expect(queue.generation == afterReplace)

        queue.playNext(songID: "x")
        #expect(queue.generation == afterReplace + 1)
        queue.remove(id: queue.items[0].id)
        #expect(queue.generation == afterReplace + 2)
    }

    @Test func staleGenerationIsRejected() {
        var queue = GaplessPlaybackQueue()
        queue.replace(songIDs: ["a", "b"])
        let stale = queue.generation
        queue.replace(songIDs: ["c", "d"])

        #expect(!queue.isCurrent(generation: stale))
        #expect(queue.isCurrent(generation: queue.generation))
    }

    /// Removing an earlier item must not change what is playing.
    @Test func removingAnEarlierItemKeepsTheSameItemCurrent() {
        var queue = GaplessPlaybackQueue()
        queue.replace(songIDs: ["a", "b", "c"])
        queue.setCurrentIndex(2)
        let currentID = queue.currentItem?.id

        queue.remove(id: queue.items[0].id)

        #expect(queue.currentItem?.id == currentID)
        #expect(queue.currentIndex == 1)
    }

    // MARK: - Acceptance: basic queue

    @Test func basicQueuePlaysInOrderThenEnds() {
        let session = Self.makeSession(["1", "2", "3"])
        let ids = session.queue.items.map(\.id)

        Self.renderTracks(session, itemIDs: ids)
        // Nothing further is planned under Repeat Off.
        #expect(session.nextIndex(after: 2, manual: false) == nil)
        #expect(Self.audibleOrder(session) == ["1", "2", "3"])
    }

    // MARK: - Acceptance: Repeat All

    @Test func repeatAllWrapsAndKeepsPlaying() {
        let session = Self.makeSession(["1", "2", "3"])
        session.setRepeatMode(.all)
        let ids = session.queue.items.map(\.id)

        // 1 → 2 → 3 → 1 → 2
        Self.renderTracks(session, itemIDs: ids + [ids[0], ids[1]])

        #expect(Self.audibleOrder(session) == ["1", "2", "3", "1", "2"])
        // The wrap is planned before the final boundary, not discovered at it.
        #expect(session.nextIndex(after: 2, manual: false) == 0)
    }

    @Test func repeatAllPlansTheWrappedItemInTheWindow() {
        let session = Self.makeSession(["1", "2", "3"])
        session.setRepeatMode(.all)
        session.setCurrentIndex(2)

        let planned = session.plannedItemIDs(depth: 3).compactMap { session.queue.item(id: $0)?.songID }

        #expect(planned == ["3", "1", "2"])
    }

    // MARK: - Acceptance: Repeat One

    @Test func repeatOneRepeatsTheCurrentItem() {
        let session = Self.makeSession(["1", "2", "3"])
        session.setRepeatMode(.one)

        #expect(session.nextIndex(after: 0, manual: false) == 0)
        let planned = session.plannedItemIDs(depth: 3).compactMap { session.queue.item(id: $0)?.songID }
        #expect(planned == ["1", "1", "1"])
    }

    /// Manual navigation overrides Repeat One, and the newly selected item then repeats.
    @Test func manualNextOverridesRepeatOneAndTheNewItemRepeats() {
        let session = Self.makeSession(["1", "2", "3"])
        session.setRepeatMode(.one)
        let ids = session.queue.items.map(\.id)
        Self.renderTracks(session, itemIDs: [ids[0]])

        session.skipToNext()

        #expect(session.queue.currentItem?.songID == "2")
        #expect(session.nextIndex(after: session.queue.currentIndex, manual: false) == 1)
        let planned = session.plannedItemIDs(depth: 2).compactMap { session.queue.item(id: $0)?.songID }
        #expect(planned == ["2", "2"])
    }

    /// A repeat is a genuinely new play, so a second full listen is eligible again — but scheduling
    /// a repeat is not.
    @Test func repeatOneProducesOneScrobblePerCompletedPlay() {
        let session = Self.makeSession(["1"])
        session.setRepeatMode(.one)
        let itemID = session.queue.items[0].id

        Self.renderTracks(session, itemIDs: [itemID, itemID, itemID])

        #expect(Self.scrobbledSongs(session) == ["1", "1"])   // two completed, third still audible
        #expect(Self.audibleOrder(session).count == 3)
    }

    // MARK: - Repeat-mode changes during playback

    @Test(arguments: [(RepeatMode.off, RepeatMode.all), (.all, .one), (.one, .off), (.one, .all)])
    func repeatModeChangesDoNotDisturbTheAudibleTrack(transition: (from: RepeatMode, to: RepeatMode)) {
        let session = Self.makeSession(["1", "2", "3"])
        session.setRepeatMode(transition.from)
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        session.advance(renderedFrames: Self.trackFrames / 2, boundaries: [])
        let audibleBefore = session.audibleItemID

        session.setRepeatMode(transition.to)

        // Only the planned future is re-planned; the audible item keeps playing.
        #expect(session.audibleItemID == audibleBefore)
        #expect(session.queue.repeatMode == transition.to)
        #expect(session.queue.item(id: ids[0])?.state == .audible)
    }

    // MARK: - Shuffle

    /// Seeded shuffle is reproducible, and every item is played before any repeats within a cycle.
    @Test func seededShuffleIsDeterministicAndCoversTheQueue() {
        func order(seed: UInt64) -> [String] {
            let session = Self.makeSession(["1", "2", "3", "4"])
            session.shuffleSeed = seed
            session.setShuffleEnabled(true)
            session.setRepeatMode(.all)
            var visited = [session.queue.currentItem!.songID]
            var index = session.queue.currentIndex
            for _ in 0..<3 {
                guard let next = session.nextIndex(after: index,
                                                   plannedSongIDs: Set(visited), manual: false) else { break }
                visited.append(session.queue.items[next].songID)
                index = next
            }
            return visited
        }

        let first = order(seed: 42)
        #expect(order(seed: 42) == first)                 // reproducible
        #expect(Set(first).count == first.count)          // no repeat inside one cycle
        #expect(Set(first) == ["1", "2", "3", "4"])       // nothing omitted
    }

    /// Repeat One wins over shuffle: the current track repeats rather than jumping.
    @Test func repeatOneOverridesShuffle() {
        let session = Self.makeSession(["1", "2", "3"])
        session.shuffleSeed = 7
        session.setShuffleEnabled(true)
        session.setRepeatMode(.one)

        #expect(session.nextIndex(after: 0, manual: false) == 0)
    }

    /// A single-item queue under shuffle + Repeat All replays itself instead of stalling.
    @Test func shuffleWithSingleItemQueueReplaysUnderRepeatAll() {
        let session = Self.makeSession(["only"])
        session.shuffleSeed = 3
        session.setShuffleEnabled(true)
        session.setRepeatMode(.all)

        #expect(session.nextIndex(after: 0, manual: false) == 0)
        session.setRepeatMode(.off)
        #expect(session.nextIndex(after: 0, manual: false) == nil)
    }

    @Test func disablingShuffleResumesSequentialAdvance() {
        let session = Self.makeSession(["1", "2", "3"])
        session.shuffleSeed = 11
        session.setShuffleEnabled(true)
        session.setShuffleEnabled(false)

        #expect(session.nextIndex(after: 0, manual: false) == 1)
    }

    // MARK: - Acceptance: queue mutation (Play Next)

    /// 1 playing, 2 scheduled, Play Next inserts X → 1 → X → 2.
    @Test func playNextBecomesTheImmediateSuccessor() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        session.advance(renderedFrames: Self.trackFrames / 2, boundaries: [])

        let insertedID = session.playNext(songID: "X")
        session.songDurations["X"] = Self.trackSeconds

        let planned = session.plannedItemIDs(depth: 3).compactMap { session.queue.item(id: $0)?.songID }
        #expect(planned == ["1", "X", "2"])
        #expect(session.queue.index(of: insertedID) == 1)
        // The audible track is untouched by the edit.
        #expect(session.audibleItemID == ids[0])
    }

    /// The previously scheduled successor is cancelled, so its gain event and metadata boundary go
    /// with it — it never became audible, so it never counts as played.
    @Test func supersededItemIsCancelledNotCompleted() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        session.markScheduled(ids[1], startFrame: Self.trackFrames, generation: session.queue.generation)

        session.playNext(songID: "X")

        #expect(session.queue.item(id: ids[1])?.state == .cancelled)
        #expect(Self.scrobbledSongs(session).isEmpty)
    }

    @Test func removingAnUpcomingItemRePlansWithoutTouchingTheAudibleOne() {
        let session = Self.makeSession(["1", "2", "3"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        session.markScheduled(ids[1], startFrame: Self.trackFrames, generation: session.queue.generation)

        session.remove(itemID: ids[1])

        #expect(session.audibleItemID == ids[0])
        let planned = session.plannedItemIDs(depth: 3).compactMap { session.queue.item(id: $0)?.songID }
        #expect(planned == ["1", "3"])
    }

    @Test func clearingTheQueueStopsEverything() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])

        session.clearQueue()

        #expect(session.queue.isEmpty)
        #expect(session.audibleItemID == nil)
        #expect(session.plannedItemIDs().isEmpty)
    }

    // MARK: - Manual transport

    @Test func manualNextBeforeThresholdDoesNotScrobble() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        // 2 s of a 10 s track — well under the 5 s (half) threshold.
        session.advance(renderedFrames: AVAudioFramePosition(2 * Self.sampleRate), boundaries: [])

        session.skipToNext()

        #expect(Self.scrobbledSongs(session).isEmpty)
        #expect(session.queue.currentItem?.songID == "2")
    }

    @Test func manualNextAfterThresholdScrobblesExactlyOnce() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        // 8 s of a 10 s track — past the 5 s threshold.
        session.advance(renderedFrames: AVAudioFramePosition(8 * Self.sampleRate), boundaries: [])

        session.skipToNext()

        #expect(Self.scrobbledSongs(session) == ["1"])
    }

    /// Production semantics, preserved: more than 3 s in, Previous restarts the current track.
    @Test func previousRestartsCurrentTrackPastTheThreshold() {
        let session = Self.makeSession(["1", "2", "3"])
        session.setCurrentIndex(1)

        let destination = session.skipToPrevious(elapsedSeconds: 5)

        #expect(destination == .restartCurrent)
        #expect(session.queue.currentItem?.songID == "2")
    }

    @Test func previousGoesBackWithinTheThreshold() {
        let session = Self.makeSession(["1", "2", "3"])
        session.setCurrentIndex(1)

        let destination = session.skipToPrevious(elapsedSeconds: 1)

        #expect(destination == .item(index: 0))
        #expect(session.queue.currentItem?.songID == "1")
    }

    /// At the first item there is nowhere back to, so Previous restarts instead.
    @Test func previousAtTheStartOfTheQueueRestarts() {
        let session = Self.makeSession(["1", "2"])

        #expect(session.skipToPrevious(elapsedSeconds: 0.5) == .restartCurrent)
    }

    /// A track finished but paused should go back a track rather than restart itself.
    @Test func previousWhenPausedAtTheEndGoesBackATrack() {
        let session = Self.makeSession(["1", "2"])
        session.setCurrentIndex(1)
        session.pause()

        let destination = session.skipToPrevious(elapsedSeconds: Self.trackSeconds)

        #expect(destination == .item(index: 0))
    }

    @Test func pauseAndResumePreserveQueueAndAudibleItem() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        session.advance(renderedFrames: Self.trackFrames / 2, boundaries: [])

        session.pause()
        #expect(!session.isPlaying)
        #expect(session.audibleItemID == ids[0])
        #expect(session.queue.count == 2)

        session.play()
        #expect(session.isPlaying)
        #expect(session.audibleItemID == ids[0])
    }

    @Test func stopClearsTheScheduleButKeepsTheQueueReusable() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])

        session.stop()

        #expect(!session.isPlaying)
        #expect(session.audibleItemID == nil)
        #expect(session.queue.count == 2)             // queue preserved
        #expect(!session.plannedItemIDs().isEmpty)    // immediately reusable
    }

    // MARK: - Seek

    /// Seeking backward past the threshold must not leave the track already counted, and must not
    /// change the queue position.
    @Test func seekBackwardResetsCompletionAccountingWithoutChangingQueuePosition() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        session.advance(renderedFrames: AVAudioFramePosition(8 * Self.sampleRate), boundaries: [])

        session.seek(toFrame: 0)

        #expect(session.queue.currentIndex == 0)
        #expect(session.audibleItemID == ids[0])
        #expect(session.queue.item(id: ids[0])?.audibleFrames == 0)
        #expect(session.queue.item(id: ids[0])?.scrobbleSubmitted == false)
        #expect(session.seekOffsetFrames == 0)
    }

    /// Seeking forward must not credit audio that was never heard.
    @Test func seekForwardDoesNotCreditUnheardAudio() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])

        session.seek(toFrame: AVAudioFramePosition(9 * Self.sampleRate))
        // Only a second of real playback after the seek.
        session.advance(renderedFrames: AVAudioFramePosition(Self.sampleRate), boundaries: [])
        session.skipToNext()

        #expect(Self.scrobbledSongs(session).isEmpty)
    }

    /// Acceptance: seek within track 1, then transition correctly to track 2.
    @Test func seekThenTransitionSelectsTheCorrectNextTrack() {
        let session = Self.makeSession(["1", "2", "3"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])
        session.seek(toFrame: AVAudioFramePosition(5 * Self.sampleRate))

        session.advance(renderedFrames: Self.trackFrames, boundaries: [])
        session.advance(renderedFrames: 1, boundaries: [(ids[1], session.renderFrame)])

        #expect(session.audibleItemID == ids[1])
        #expect(session.queue.currentItem?.songID == "2")
        #expect(Self.audibleOrder(session) == ["1", "2"])
    }

    @Test func rapidRepeatedSeeksLeaveConsistentState() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])

        for target in [1, 5, 2, 9, 0] {
            session.seek(toFrame: AVAudioFramePosition(Double(target) * Self.sampleRate))
        }

        #expect(session.audibleItemID == ids[0])
        #expect(session.queue.currentIndex == 0)
        #expect(session.seekOffsetFrames == 0)
    }

    // MARK: - Completion accounting

    @Test func completionUsesAudibleFramesNotScheduling() {
        let policy = GaplessCompletionPolicy(sampleRate: Self.sampleRate)

        // Half of a 10 s track is the threshold.
        #expect(policy.scrobbleThresholdFrames(effectiveDurationSeconds: 10) == 220_500)
        #expect(!policy.isEligible(audibleFrames: 220_500, effectiveDurationSeconds: 10))
        #expect(policy.isEligible(audibleFrames: 220_501, effectiveDurationSeconds: 10))
        // Nothing scheduled but unheard can qualify.
        #expect(!policy.isEligible(audibleFrames: 0, effectiveDurationSeconds: 10))
    }

    /// The 240 s cap is preserved from production: a long track qualifies at 4 minutes, not halfway.
    @Test func longTracksUseThe240SecondCap() {
        let policy = GaplessCompletionPolicy(sampleRate: Self.sampleRate)
        let frames = policy.scrobbleThresholdFrames(effectiveDurationSeconds: 1_200)

        #expect(frames == AVAudioFramePosition(240 * Self.sampleRate))
    }

    @Test func noDuplicateScrobbleForOneCompletedPlay() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        Self.renderTracks(session, itemIDs: [ids[0]])
        session.skipToNext()

        #expect(Self.scrobbledSongs(session) == ["1"])
    }

    // MARK: - Diagnostics

    #if DEBUG
    @Test func snapshotReportsSchedulingStateWithoutSensitiveData() {
        let session = Self.makeSession(["1", "2"])
        let ids = session.queue.items.map(\.id)
        session.advance(renderedFrames: 1, boundaries: [(ids[0], 0)])

        let snapshot = session.snapshot

        #expect(snapshot.currentIndex == 0)
        #expect(snapshot.audibleItem == ids[0])
        #expect(snapshot.states.count == 2)
        #expect(snapshot.states.first?.1 == .audible)
        #expect(snapshot.shuffleEnabled == false)
    }
    #endif
}
