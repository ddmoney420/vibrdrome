import Testing
import Foundation
@testable import Veydrune

/// Tests for radio deduplication logic.
/// Mirrors AudioEngine.deduplicateRadioSongs() to verify filtering.
struct RadioDeduplicationTests {

    // MARK: - Deduplication Logic

    /// Mirrors AudioEngine.deduplicateRadioSongs()
    private func deduplicateRadioSongs(
        _ songs: [Song], against existing: [Song], skippedIds: Set<String> = []
    ) -> [Song] {
        let existingIds = Set(existing.map(\.id))
        var seen = existingIds.union(skippedIds)
        return songs.filter { song in
            guard !seen.contains(song.id) else { return false }
            seen.insert(song.id)
            return true
        }
    }

    @Test func noDuplicatesPassThrough() {
        let songs = [makeSong(id: "1"), makeSong(id: "2"), makeSong(id: "3")]
        let result = deduplicateRadioSongs(songs, against: [])
        #expect(result.count == 3)
    }

    @Test func removeDuplicatesInBatch() {
        let songs = [makeSong(id: "1"), makeSong(id: "2"), makeSong(id: "1"), makeSong(id: "3")]
        let result = deduplicateRadioSongs(songs, against: [])
        #expect(result.count == 3)
        #expect(result.map(\.id) == ["1", "2", "3"])
    }

    @Test func removeExistingQueueDuplicates() {
        let existing = [makeSong(id: "1"), makeSong(id: "2")]
        let songs = [makeSong(id: "2"), makeSong(id: "3"), makeSong(id: "4")]
        let result = deduplicateRadioSongs(songs, against: existing)
        #expect(result.count == 2)
        #expect(result.map(\.id) == ["3", "4"])
    }

    @Test func removeSkippedSongs() {
        let songs = [makeSong(id: "1"), makeSong(id: "2"), makeSong(id: "3")]
        let result = deduplicateRadioSongs(songs, against: [], skippedIds: ["2"])
        #expect(result.count == 2)
        #expect(result.map(\.id) == ["1", "3"])
    }

    @Test func allDuplicatesReturnsEmpty() {
        let existing = [makeSong(id: "1"), makeSong(id: "2")]
        let songs = [makeSong(id: "1"), makeSong(id: "2")]
        let result = deduplicateRadioSongs(songs, against: existing)
        #expect(result.isEmpty)
    }

    @Test func emptyInputReturnsEmpty() {
        let result = deduplicateRadioSongs([], against: [makeSong(id: "1")])
        #expect(result.isEmpty)
    }

    @Test func combinedFilteringExistingAndSkipped() {
        let existing = [makeSong(id: "1")]
        let songs = [makeSong(id: "1"), makeSong(id: "2"), makeSong(id: "3"), makeSong(id: "4")]
        let result = deduplicateRadioSongs(songs, against: existing, skippedIds: ["3"])
        #expect(result.count == 2)
        #expect(result.map(\.id) == ["2", "4"])
    }

    @Test func preservesFirstOccurrenceOrder() {
        let songs = [makeSong(id: "c"), makeSong(id: "a"), makeSong(id: "b"), makeSong(id: "a")]
        let result = deduplicateRadioSongs(songs, against: [])
        #expect(result.map(\.id) == ["c", "a", "b"])
    }

    // MARK: - Radio Refill Threshold

    /// Mirrors refillRadioIfNeeded() trigger condition
    private func shouldRefill(currentIndex: Int, queueCount: Int) -> Bool {
        currentIndex >= queueCount - 5
    }

    @Test func refillNotNeededEarlyInQueue() {
        #expect(!shouldRefill(currentIndex: 0, queueCount: 20))
    }

    @Test func refillNeededNearEnd() {
        #expect(shouldRefill(currentIndex: 16, queueCount: 20))
    }

    @Test func refillNeededAtThreshold() {
        #expect(shouldRefill(currentIndex: 15, queueCount: 20))
    }

    @Test func refillNotNeededJustBeforeThreshold() {
        #expect(!shouldRefill(currentIndex: 14, queueCount: 20))
    }

    @Test func refillNeededWithSmallQueue() {
        #expect(shouldRefill(currentIndex: 0, queueCount: 3))
    }

    // MARK: - Interleave Logic

    /// Mirrors AudioEngine.interleaveRadioSongs() — 2 primary per 1 secondary
    private func interleaveRadioSongs(primary: [Song], secondary: [Song]) -> [Song] {
        var result: [Song] = []
        var pIdx = 0
        var sIdx = 0
        while pIdx < primary.count || sIdx < secondary.count {
            for _ in 0..<2 where pIdx < primary.count {
                result.append(primary[pIdx])
                pIdx += 1
            }
            if sIdx < secondary.count {
                result.append(secondary[sIdx])
                sIdx += 1
            }
        }
        return result
    }

    @Test func interleaveEqualLists() {
        let primary = (1...6).map { makeSong(id: "p\($0)") }
        let secondary = (1...3).map { makeSong(id: "s\($0)") }
        let result = interleaveRadioSongs(primary: primary, secondary: secondary)
        // Pattern: p1 p2 s1 p3 p4 s2 p5 p6 s3
        #expect(result.map(\.id) == ["p1", "p2", "s1", "p3", "p4", "s2", "p5", "p6", "s3"])
    }

    @Test func interleaveMoreSecondaryThanPrimary() {
        let primary = (1...2).map { makeSong(id: "p\($0)") }
        let secondary = (1...5).map { makeSong(id: "s\($0)") }
        let result = interleaveRadioSongs(primary: primary, secondary: secondary)
        // p1 p2 s1 — then only secondary left: s2 s3 s4 s5
        #expect(result.map(\.id) == ["p1", "p2", "s1", "s2", "s3", "s4", "s5"])
    }

    @Test func interleaveEmptySecondary() {
        let primary = (1...4).map { makeSong(id: "p\($0)") }
        let result = interleaveRadioSongs(primary: primary, secondary: [])
        #expect(result.map(\.id) == ["p1", "p2", "p3", "p4"])
    }

    @Test func interleaveEmptyPrimary() {
        let secondary = (1...3).map { makeSong(id: "s\($0)") }
        let result = interleaveRadioSongs(primary: [], secondary: secondary)
        #expect(result.map(\.id) == ["s1", "s2", "s3"])
    }

    @Test func interleaveBothEmpty() {
        let result = interleaveRadioSongs(primary: [], secondary: [])
        #expect(result.isEmpty)
    }

    @Test func interleaveRatioApproximately2to1() {
        let primary = (1...20).map { makeSong(id: "p\($0)") }
        let secondary = (1...10).map { makeSong(id: "s\($0)") }
        let result = interleaveRadioSongs(primary: primary, secondary: secondary)
        #expect(result.count == 30)
        // Every 3rd item (index 2, 5, 8...) should be a secondary
        for i in stride(from: 2, to: 30, by: 3) {
            #expect(result[i].id.hasPrefix("s"), "Index \(i) should be a similar-artist track")
        }
    }

    // MARK: - Helpers

    private func makeSong(id: String) -> Song {
        Song(
            id: id, parent: nil, title: "Song \(id)",
            album: nil, artist: nil, albumId: nil, artistId: nil,
            track: nil, year: nil, genre: nil, coverArt: nil,
            size: nil, contentType: nil, suffix: nil, duration: 200,
            bitRate: nil, path: nil, discNumber: nil, created: nil,
            starred: nil, bpm: nil, replayGain: nil, musicBrainzId: nil
        )
    }
}
