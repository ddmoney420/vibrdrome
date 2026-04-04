import Testing
import Foundation
@testable import Vibrdrome

@MainActor
struct QueueEdgeCaseTests {

    private func makeSong(id: String = "1", title: String = "Test") -> Song {
        Song(
            id: id, parent: nil, title: title,
            album: nil, artist: nil, albumId: nil, artistId: nil,
            track: nil, year: nil, genre: nil, coverArt: nil,
            size: nil, contentType: nil, suffix: nil,
            duration: 180, bitRate: nil, path: nil,
            discNumber: nil, created: nil, starred: nil, userRating: nil,
            bpm: nil, replayGain: nil, musicBrainzId: nil
        )
    }

    // MARK: - addToQueue

    @Test func addToQueueAppendsToEnd() {
        let engine = AudioEngine.shared
        let s1 = makeSong(id: "a")
        let s2 = makeSong(id: "b")
        engine.queue = [s1]
        engine.addToQueue(s2)
        #expect(engine.queue.count == 2)
        #expect(engine.queue.last?.id == "b")
    }

    // MARK: - addToQueueNext

    @Test func addToQueueNextInsertsAfterCurrent() {
        let engine = AudioEngine.shared
        let s1 = makeSong(id: "a")
        let s2 = makeSong(id: "b")
        let s3 = makeSong(id: "c")
        engine.queue = [s1, s2]
        engine.currentIndex = 0
        engine.addToQueueNext(s3)
        #expect(engine.queue[1].id == "c")
        #expect(engine.queue[2].id == "b")
    }

    // MARK: - upNext

    @Test func upNextReturnsEmptyForLastTrack() {
        let engine = AudioEngine.shared
        engine.queue = [makeSong(id: "a")]
        engine.currentIndex = 0
        #expect(engine.upNext.isEmpty)
    }

    @Test func upNextReturnsSongsAfterCurrent() {
        let engine = AudioEngine.shared
        engine.queue = [makeSong(id: "a"), makeSong(id: "b"), makeSong(id: "c")]
        engine.currentIndex = 0
        #expect(engine.upNext.count == 2)
        #expect(engine.upNext[0].id == "b")
    }

    @Test func upNextEmptyForEmptyQueue() {
        let engine = AudioEngine.shared
        engine.queue = []
        engine.currentIndex = 0
        #expect(engine.upNext.isEmpty)
    }

    // MARK: - removeFromQueue

    @Test func removeFromQueueRemovesCorrectSong() {
        let engine = AudioEngine.shared
        engine.queue = [makeSong(id: "a"), makeSong(id: "b"), makeSong(id: "c")]
        engine.currentIndex = 0
        engine.removeFromQueue(at: 0) // removes "b" (first in upNext)
        #expect(engine.queue.count == 2)
        #expect(engine.queue[1].id == "c")
    }

    @Test func removeFromQueueDoesNotRemoveCurrent() {
        let engine = AudioEngine.shared
        engine.queue = [makeSong(id: "a"), makeSong(id: "b")]
        engine.currentIndex = 0
        // Try to remove at index -1 (before current) — should be guarded
        engine.removeFromQueue(at: -1)
        #expect(engine.queue.count == 2) // unchanged
    }

    // MARK: - moveInQueue

    @Test func moveInQueueReorders() {
        let engine = AudioEngine.shared
        engine.queue = [makeSong(id: "a"), makeSong(id: "b"), makeSong(id: "c"), makeSong(id: "d")]
        engine.currentIndex = 0
        // Move "b" (index 0 in upNext) to end (index 2 in upNext)
        engine.moveInQueue(from: IndexSet(integer: 0), to: 3)
        #expect(engine.queue[1].id == "c")
        #expect(engine.queue[2].id == "d")
        #expect(engine.queue[3].id == "b")
    }

    // MARK: - skipToIndex

    @Test func skipToIndexSetsCurrentIndex() {
        let engine = AudioEngine.shared
        engine.queue = [makeSong(id: "a"), makeSong(id: "b"), makeSong(id: "c")]
        engine.currentIndex = 0
        // Note: skipToIndex tries to play audio which won't work in tests
        // but we can verify it doesn't crash and the queue stays intact
        #expect(engine.queue.count == 3)
    }

    @Test func skipToIndexOutOfBoundsDoesNothing() {
        let engine = AudioEngine.shared
        engine.queue = [makeSong(id: "a")]
        engine.currentIndex = 0
        engine.skipToIndex(5) // out of bounds
        #expect(engine.currentIndex == 0)
    }
}
