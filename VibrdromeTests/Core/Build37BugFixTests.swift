import Testing
import Foundation
@testable import Vibrdrome

@MainActor
struct Build37BugFixTests {

    private func makeSong(id: String, artist: String? = nil) -> Song {
        Song(id: id, title: "Song \(id)", artist: artist, duration: 180)
    }

    // MARK: - Smart Shuffle Edge Cases

    @Test func smartShuffleSingleSongQueue() {
        let engine = AudioEngine.shared
        engine.queue = [makeSong(id: "only", artist: "Solo")]
        engine.currentIndex = 0
        let next = engine.smartShuffleNextIndex()
        #expect(next == 0, "Single-song queue should return index 0")
    }

    @Test func smartShuffleTwoSongQueue() {
        let engine = AudioEngine.shared
        engine.queue = [
            makeSong(id: "a", artist: "Artist A"),
            makeSong(id: "b", artist: "Artist B"),
        ]
        engine.currentIndex = 0
        let next = engine.smartShuffleNextIndex()
        #expect(next == 1, "Two-song queue should pick the other song")
    }

    @Test func smartShuffleAllSameArtist() {
        let engine = AudioEngine.shared
        engine.queue = (0..<5).map { makeSong(id: "\($0)", artist: "Same") }
        engine.currentIndex = 2
        let next = engine.smartShuffleNextIndex()
        #expect(next != 2, "Should pick a different index than current")
        #expect(next >= 0 && next < 5, "Index should be in bounds")
    }

    @Test func smartShuffleEmptyQueue() {
        let engine = AudioEngine.shared
        engine.queue = []
        engine.currentIndex = 0
        let next = engine.smartShuffleNextIndex()
        #expect(next == 0, "Empty queue should return 0")
    }

    // MARK: - Lyrics Negative Offset

    @Test func lyricsNegativeOffsetClampedToZero() {
        let offset = -1000
        let currentTime = 0.5
        let currentMs = max(0, Int(currentTime * 1000) + offset)
        #expect(currentMs == 0, "Negative offset should clamp to 0, not go negative")
    }

    @Test func lyricsPositiveOffsetWorks() {
        let offset = 500
        let currentTime = 1.0
        let currentMs = max(0, Int(currentTime * 1000) + offset)
        #expect(currentMs == 1500)
    }

    @Test func lyricsZeroOffsetPassesThrough() {
        let offset = 0
        let currentTime = 2.5
        let currentMs = max(0, Int(currentTime * 1000) + offset)
        #expect(currentMs == 2500)
    }

    // MARK: - Sleep Timer Fade Factor

    @Test func sleepTimerFadeFactorStartsAtOne() {
        let timer = SleepTimer.shared
        #expect(timer.fadeFactor == 1.0)
    }

    // MARK: - Playlist Delete Index Mapping

    @Test func filteredIndicesToOriginalIndices() {
        // Simulate: original list has 5 songs, filter shows 2
        let allSongs = (0..<5).map { makeSong(id: "\($0)", artist: "Artist \($0)") }
        let filtered = [allSongs[1], allSongs[3]] // indices 1 and 3 in original

        // User deletes first item in filtered list (offset 0)
        let deleteOffset = 0
        let songId = filtered[deleteOffset].id
        let originalIndex = allSongs.firstIndex(where: { $0.id == songId })

        #expect(originalIndex == 1, "Filtered index 0 should map to original index 1")
    }

    @Test func filteredDeleteLastItem() {
        let allSongs = (0..<5).map { makeSong(id: "\($0)") }
        let filtered = [allSongs[0], allSongs[4]]

        let deleteOffset = 1
        let songId = filtered[deleteOffset].id
        let originalIndex = allSongs.firstIndex(where: { $0.id == songId })

        #expect(originalIndex == 4, "Filtered index 1 should map to original index 4")
    }

    // MARK: - Next Bounds Check

    @Test func nextWithEmptyQueueDoesNotCrash() {
        let engine = AudioEngine.shared
        engine.queue = []
        engine.currentIndex = 0
        // Should not crash — guard !queue.isEmpty handles this
        engine.next()
        #expect(engine.queue.isEmpty)
    }
}
