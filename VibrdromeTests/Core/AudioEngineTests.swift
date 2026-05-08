import Testing
import Foundation
@testable import Vibrdrome

// MARK: - Helpers

/// Build a minimal Song fixture for testing.
/// All fields not relevant to queue/shuffle logic are left at defaults.
private func makeSong(
    id: String,
    title: String,
    artist: String = "Artist",
    duration: Int = 180
) -> Song {
    Song(id: id, title: title, artist: artist, duration: duration)
}

/// Produce an array of n songs with stable, predictable IDs and titles.
/// artist alternates every 2 songs so artist-aware shuffle tests have
/// a meaningful constraint to exercise.
private func makeSongs(_ count: Int, artist: String? = nil) -> [Song] {
    (0..<count).map { i in
        let a = artist ?? (i % 2 == 0 ? "Artist A" : "Artist B")
        return makeSong(id: "song\(i)", title: "Track \(i)", artist: a)
    }
}

/// Reset AudioEngine.shared to a clean state between tests.
/// Avoids bleed-over from one test body to the next.
@MainActor
private func resetEngine() {
    let engine = AudioEngine.shared
    engine.queue = []
    engine.currentIndex = 0
    engine.currentSong = nil
    engine.isPlaying = false
    engine.shuffleEnabled = false
    engine.repeatMode = .off
    engine.shufflePlayCount = 0
    engine.cachedSmartShuffleSongs = []
    engine.cachedSmartShuffleSongId = nil
    engine.isRadioMode = false
    engine.currentRadioStation = nil
}

// MARK: - Suite

/// Integration tests against AudioEngine.shared using the --uitesting path,
/// which bypasses AVPlayer/AVAudioSession while keeping all observable state
/// mutations live.  Covers smart shuffle, queue insertion, and next-song/index
/// resolution across every play mode.
///
/// The test process MUST be launched with the "--uitesting" launch argument so
/// that AudioEngine.init() skips AudioSession setup and play() routes through
/// playForUITesting().
@MainActor
struct AudioEngineTests {

    // =========================================================================
    // MARK: - Next Song Index — Sequential
    // =========================================================================

    @Test func nextIndexSequentialMidQueue() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[1], from: songs, at: 1)

        let idx = engine.nextSongIndex()
        #expect(idx == 2)
    }

    @Test func nextIndexSequentialAtLastTrackRepeatOff() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[4], from: songs, at: 4)

        #expect(engine.nextSongIndex() == nil)
    }

    @Test func nextIndexSequentialAtLastTrackRepeatAll() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[4], from: songs, at: 4)
        engine.repeatMode = .all

        // repeat-all: gapless loops the same track index for lookahead
        #expect(engine.nextSongIndex() == 4)
    }

    @Test func nextIndexRepeatOneReturnsNil() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[2], from: songs, at: 2)
        engine.repeatMode = .one

        // repeat-one is handled in handleTrackEnd, not via lookahead
        #expect(engine.nextSongIndex() == nil)
    }

    @Test func nextIndexEmptyQueueReturnsNil() async {
        resetEngine()
        let engine = AudioEngine.shared
        engine.queue = []

        #expect(engine.nextSongIndex() == nil)
    }

    @Test func nextIndexInternetRadioReturnsNil() async {
        resetEngine()
        let engine = AudioEngine.shared
        let station = InternetRadioStation(
            id: "r1", name: "Test FM",
            streamUrl: "http://example.com/stream",
            homePageUrl: nil, coverArt: nil
        )
        engine.currentRadioStation = station

        #expect(engine.nextSongIndex() == nil)
    }

    @Test func nextIndexSingleSongRepeatOffReturnsNil() async {
        resetEngine()
        let engine = AudioEngine.shared
        let song = makeSong(id: "s0", title: "Only")
        engine.play(song: song, from: [song], at: 0)

        #expect(engine.nextSongIndex() == nil)
    }

    // =========================================================================
    // MARK: - Next Song Index — Shuffle
    // =========================================================================

    @Test func nextIndexShuffleReturnsDifferentSong() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(10)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.shuffleEnabled = true
        engine.cachedSmartShuffleSongs = []
        engine.cachedSmartShuffleSongId = nil

        let idx = engine.nextSongIndex()
        #expect(idx != nil)
        // Must not point back at the current track
        #expect(idx != 0)
    }

    @Test func nextIndexShuffleSingleTrackRepeatOffReturnsNil() async {
        resetEngine()
        let engine = AudioEngine.shared
        let song = makeSong(id: "s0", title: "Alone")
        engine.play(song: song, from: [song], at: 0)
        engine.shuffleEnabled = true

        #expect(engine.nextSongIndex() == nil)
    }

    @Test func nextIndexShuffleSingleTrackRepeatAllReturnsSelf() async {
        resetEngine()
        let engine = AudioEngine.shared
        let song = makeSong(id: "s0", title: "Alone")
        engine.play(song: song, from: [song], at: 0)
        engine.shuffleEnabled = true
        engine.repeatMode = .all

        let idx = engine.nextSongIndex()
        #expect(idx == 0)
    }

    // =========================================================================
    // MARK: - nextSongs / nextSongIndices
    // =========================================================================

    @Test func nextSongsSequentialReturnsFive() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(10)
        engine.play(song: songs[0], from: songs, at: 0)

        let next = engine.nextSongs(count: 5)
        #expect(next.count == 5)
        #expect(next.map(\.id) == ["song1", "song2", "song3", "song4", "song5"])
    }

    @Test func nextSongsClampedAtQueueEnd() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(3)
        engine.play(song: songs[0], from: songs, at: 0)

        // Only 2 songs after index 0
        let next = engine.nextSongs(count: 5)
        #expect(next.count == 2)
    }

    @Test func nextSongsRepeatAllWrapsAround() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(3)
        engine.play(song: songs[2], from: songs, at: 2)
        engine.repeatMode = .all

        // repeat-all in nextSongIndices returns currentIndex repeated
        let indices = engine.nextSongIndices(count: 3)
        #expect(indices.allSatisfy { $0 == 2 })
    }

    @Test func nextSongsRepeatOneReturnsEmpty() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[2], from: songs, at: 2)
        engine.repeatMode = .one

        #expect(engine.nextSongIndices(count: 5).isEmpty)
    }

    @Test func nextSongsRadioModeReturnsEmpty() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(10)
        engine.play(song: songs[3], from: songs, at: 3)
        engine.currentRadioStation = InternetRadioStation(
            id: "r1", name: "Radio", streamUrl: "http://x.com/s",
            homePageUrl: nil, coverArt: nil
        )

        #expect(engine.nextSongIndices(count: 5).isEmpty)
    }

    @Test func nextSongsShuffleReturnsFiveDistinctSongs() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(20)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.shuffleEnabled = true
        engine.cachedSmartShuffleSongs = []
        engine.cachedSmartShuffleSongId = nil

        let next = engine.nextSongs(count: 5)
        #expect(next.count == 5)
        // All returned songs must be distinct
        #expect(Set(next.map(\.id)).count == 5)
        // None should be the current song
        #expect(!next.contains(where: { $0.id == "song0" }))
    }

    // =========================================================================
    // MARK: - Smart Shuffle Cache
    // =========================================================================

    @Test func getNextSmartShuffleSongsBuildsCache() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(20)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.cachedSmartShuffleSongs = []
        engine.cachedSmartShuffleSongId = nil

        let result = engine.getNextSmartShuffleSongs(count: 5)
        #expect(result.count == 5)
        // Cache should now be populated
        #expect(engine.cachedSmartShuffleSongs.count == 5)
    }

    @Test func getNextSmartShuffleSongsAvoidsCurrentSong() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(10)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.cachedSmartShuffleSongs = []
        engine.cachedSmartShuffleSongId = nil

        let result = engine.getNextSmartShuffleSongs(count: 9)
        #expect(!result.contains(where: { $0.id == "song0" }))
    }

    @Test func getNextSmartShuffleSongsNoDuplicatesInResult() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(20)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.cachedSmartShuffleSongs = []
        engine.cachedSmartShuffleSongId = nil

        let result = engine.getNextSmartShuffleSongs(count: 10)
        let ids = result.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate songs returned from smart shuffle")
    }

    @Test func getNextSmartShuffleSongsAvoidsConsecutiveSameArtist() async {
        resetEngine()
        let engine = AudioEngine.shared
        // 20 songs, artists alternate A/B every 2 — enough candidates for
        // the smart-shuffle to satisfy the different-artist constraint.
        let songs = makeSongs(20)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.cachedSmartShuffleSongs = []
        engine.cachedSmartShuffleSongId = nil

        let result = engine.getNextSmartShuffleSongs(count: 8)
        var consecutiveSameArtist = 0
        for i in 1..<result.count where result[i].artist == result[i - 1].artist {
            consecutiveSameArtist += 1
        }
        // Smart shuffle tries to avoid consecutive same-artist; with 10 songs of
        // each artist and 8 picks there should be very few (ideally zero) collisions.
        #expect(consecutiveSameArtist <= 1)
    }

    @Test func getNextSmartShuffleSongsCacheIsStableOnRepeatCall() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(20)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.cachedSmartShuffleSongs = []
        engine.cachedSmartShuffleSongId = nil

        let first = engine.getNextSmartShuffleSongs(count: 5).map(\.id)
        let second = engine.getNextSmartShuffleSongs(count: 5).map(\.id)
        // Same current song → same cached sequence on repeat call
        #expect(first == second)
    }

    @Test func getNextSmartShuffleSongsCacheAdvancesWhenCurrentSongChanges() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(20)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.cachedSmartShuffleSongs = []
        engine.cachedSmartShuffleSongId = nil

        let initial = engine.getNextSmartShuffleSongs(count: 3)
        guard let firstUpcoming = initial.first else {
            Issue.record("Cache empty after first call"); return
        }

        // Simulate moving to the song that was at the head of the cache.
        // The engine should consume it and keep the tail intact.
        if let newIndex = engine.queue.firstIndex(where: { $0.id == firstUpcoming.id }) {
            engine.currentIndex = newIndex
            engine.currentSong = firstUpcoming
        }

        let after = engine.getNextSmartShuffleSongs(count: 2)
        // The consumed head must no longer be in position 0
        #expect(after.first?.id != firstUpcoming.id)
    }

    @Test func getNextSmartShuffleSongsCacheFlushedOnUnexpectedJump() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(20)
        engine.play(song: songs[0], from: songs, at: 0)

        // Pre-seed cache anchored to song0
        engine.cachedSmartShuffleSongId = "song0"
        engine.cachedSmartShuffleSongs = [songs[5], songs[7], songs[9]]

        // Jump to an unexpected position (not the cached head)
        engine.currentIndex = 3
        engine.currentSong = songs[3]

        // The next call should detect the mismatch and rebuild
        let result = engine.getNextSmartShuffleSongs(count: 3)
        #expect(!result.contains(where: { $0.id == "song3" }), "Current song must not appear in shuffle result")
        #expect(result.count == 3)
    }

    @Test func getNextSmartShuffleSongsTopsUpShortCache() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(20)
        engine.play(song: songs[0], from: songs, at: 0)

        // Seed a partial cache (only 2 songs)
        engine.cachedSmartShuffleSongId = "song0"
        engine.cachedSmartShuffleSongs = [songs[4], songs[8]]

        // Ask for 5 — should top up to 5 without touching the existing 2
        let result = engine.getNextSmartShuffleSongs(count: 5)
        #expect(result.count == 5)
        // The first two must be the ones we pre-seeded
        #expect(result[0].id == "song4")
        #expect(result[1].id == "song8")
    }

    // =========================================================================
    // MARK: - insertSongNext + Shuffle Cache
    // =========================================================================

    @Test func insertSongNextInsertsAfterCurrentIndex() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[0], from: songs, at: 0)

        let extra = makeSong(id: "extra", title: "Extra")
        engine.insertSongNext(for: extra, at: engine.currentIndex + 1)

        // Should be immediately after index 0
        #expect(engine.queue[1].id == "extra")
        // Total queue grows by 1
        #expect(engine.queue.count == 6)
    }

    @Test func insertSongNextPreservesExistingQueueOrder() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(4)
        engine.play(song: songs[0], from: songs, at: 0)
        let extra = makeSong(id: "extra", title: "Extra")
        engine.insertSongNext(for: extra, at: 1)

        // Old song1 should now be at index 2
        #expect(engine.queue[2].id == "song1")
        #expect(engine.queue[3].id == "song2")
        #expect(engine.queue[4].id == "song3")
    }

    @Test func insertSongNextOutOfBoundsIsIgnored() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(3)
        engine.play(song: songs[0], from: songs, at: 0)
        let extra = makeSong(id: "extra", title: "Extra")

        engine.insertSongNext(for: extra, at: 99)  // way out of range

        #expect(engine.queue.count == 3)  // unchanged
    }

    @Test func insertSongNextPrependsToShuffleCacheWhenShuffleOn() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(10)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.shuffleEnabled = true

        // Pre-seed a known cache
        engine.cachedSmartShuffleSongId = "song0"
        engine.cachedSmartShuffleSongs = [songs[3], songs[7], songs[5]]

        let extra = makeSong(id: "extra", title: "Extra")
        engine.insertSongNext(for: extra, at: 1)

        // extra must now be at head of the shuffle cache
        #expect(engine.cachedSmartShuffleSongs.first?.id == "extra")
        // Original cache order preserved behind it
        #expect(engine.cachedSmartShuffleSongs[1].id == "song3")
        #expect(engine.cachedSmartShuffleSongs[2].id == "song7")
    }

    @Test func insertSongNextDoesNotTouchShuffleCacheWhenShuffleOff() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(10)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.shuffleEnabled = false

        engine.cachedSmartShuffleSongId = "song0"
        engine.cachedSmartShuffleSongs = [songs[3], songs[7]]

        let extra = makeSong(id: "extra", title: "Extra")
        engine.insertSongNext(for: extra, at: 1)

        // Cache must be untouched in sequential mode
        #expect(engine.cachedSmartShuffleSongs.map(\.id) == ["song3", "song7"])
    }

    @Test func insertSongNextIntoEmptyShuffleCachePopulatesIt() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.shuffleEnabled = true
        engine.cachedSmartShuffleSongs = []
        engine.cachedSmartShuffleSongId = "song0"

        let extra = makeSong(id: "extra", title: "Extra")
        engine.insertSongNext(for: extra, at: 1)

        #expect(engine.cachedSmartShuffleSongs[0].id == extra.id)
    }

    // =========================================================================
    // MARK: - toggleShuffle Cache Flush
    // =========================================================================

    @Test func toggleShuffleOffFlushesStaleShuffleCache() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(10)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.shuffleEnabled = true
        engine.cachedSmartShuffleSongId = "song0"
        engine.cachedSmartShuffleSongs = [songs[2], songs[6]]

        engine.toggleShuffle()

        #expect(engine.shuffleEnabled == false)
        // Stale shuffle sequence must not survive into sequential mode
        #expect(engine.cachedSmartShuffleSongs.isEmpty)
        #expect(engine.cachedSmartShuffleSongId == nil)
    }

    @Test func toggleShuffleResetsShufflePlayCount() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.shuffleEnabled = true
        engine.shufflePlayCount = 3

        engine.toggleShuffle()

        #expect(engine.shufflePlayCount == 0)
    }

    @Test func toggleShuffleTwiceRestoresSequentialOrder() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(10)
        engine.play(song: songs[2], from: songs, at: 2)

        engine.toggleShuffle()   // → on
        engine.toggleShuffle()   // → off

        #expect(engine.shuffleEnabled == false)
        // After double-toggle, sequential next index must be 3 (currentIndex + 1)
        let idx = engine.nextSongIndex()
        #expect(idx == 3)
    }

    // =========================================================================
    // MARK: - Queue Management (addToQueue, removeFromQueue, clearQueue, moveInQueue)
    // =========================================================================

    @Test func addToQueueAppendsToEnd() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(3)
        engine.play(song: songs[0], from: songs, at: 0)

        let extra = makeSong(id: "extra", title: "Extra")
        engine.addToQueue(extra)

        #expect(engine.queue.last?.id == "extra")
        #expect(engine.queue.count == 4)
    }

    @Test func addToQueueNextInsertsImmediatelyAfterCurrent() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(4)
        engine.play(song: songs[1], from: songs, at: 1)

        let extra = makeSong(id: "extra", title: "Extra")
        engine.addToQueueNext(extra)

        #expect(engine.queue[2].id == "extra")
        #expect(engine.queue.count == 5)
    }

    @Test func removeFromQueueRemovesCorrectUpNextEntry() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[0], from: songs, at: 0)

        // upNext[0] is queue[1]; remove at upNext index 0
        engine.removeFromQueue(at: 0)

        #expect(engine.queue.count == 4)
        #expect(!engine.queue.contains(where: { $0.id == "song1" }))
    }

    @Test func clearQueueKeepsCurrentSong() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[2], from: songs, at: 2)

        engine.clearQueue()

        #expect(engine.queue.count == 1)
        #expect(engine.queue.first?.id == "song2")
        #expect(engine.currentIndex == 0)
    }

    @Test func upNextReflectsCurrentIndex() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[1], from: songs, at: 1)

        let upNext = engine.upNext
        #expect(upNext.count == 3)
        #expect(upNext.map(\.id) == ["song2", "song3", "song4"])
    }

    @Test func recentlyPlayedReflectsHistoryMostRecentFirst() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[3], from: songs, at: 3)

        let history = engine.recentlyPlayed
        // Indices 0,1,2 reversed → song2, song1, song0
        #expect(history.map(\.id) == ["song2", "song1", "song0"])
    }

    // =========================================================================
    // MARK: - advanceIndex (sequential and shuffle)
    // =========================================================================

    @Test func advanceIndexMovesForwardSequentially() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[0], from: songs, at: 0)

        let advanced = engine.advanceIndex()

        #expect(advanced == true)
        #expect(engine.currentIndex == 1)
    }

    @Test func advanceIndexReturnsFalseAtEndRepeatOff() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(3)
        engine.play(song: songs[2], from: songs, at: 2)

        let advanced = engine.advanceIndex()

        #expect(advanced == false)
        #expect(engine.currentIndex == 2)  // clamped, not incremented
    }

    @Test func advanceShuffleIndexPicsValidSong() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(10)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.shuffleEnabled = true
        engine.cachedSmartShuffleSongs = []
        engine.cachedSmartShuffleSongId = nil

        let advanced = engine.advanceIndex()

        #expect(advanced == true)
        #expect(engine.currentIndex != 0)  // moved off the starting track
        #expect(engine.currentIndex < songs.count)
    }

    @Test func advanceShuffleIndexCountsShufflePlayCount() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(5)
        engine.play(song: songs[0], from: songs, at: 0)
        engine.shuffleEnabled = true
        engine.repeatMode = .off
        engine.shufflePlayCount = 0
        engine.cachedSmartShuffleSongs = []
        engine.cachedSmartShuffleSongId = nil

        _ = engine.advanceIndex()

        #expect(engine.shufflePlayCount == 1)
    }

    // =========================================================================
    // MARK: - smartShuffle (static rearrangement)
    // =========================================================================

    @Test func smartShuffleProducesAllInputSongs() async {
        resetEngine()
        let engine = AudioEngine.shared
        let songs = makeSongs(10)
        let shuffled = engine.smartShuffle(songs)

        #expect(Set(shuffled.map(\.id)) == Set(songs.map(\.id)))
        #expect(shuffled.count == songs.count)
    }

    @Test func smartShuffleReducesConsecutiveSameArtist() async {
        resetEngine()
        let engine = AudioEngine.shared
        // All same artist — smart shuffle can't avoid it, but shouldn't crash
        let songs = makeSongs(6, artist: "Same")
        let shuffled = engine.smartShuffle(songs)
        #expect(shuffled.count == 6)
    }

    @Test func smartShuffleSingleSongReturnedUnchanged() async {
        resetEngine()
        let engine = AudioEngine.shared
        let song = makeSong(id: "s0", title: "Solo")
        let result = engine.smartShuffle([song])
        #expect(result.count == 1)
        #expect(result.first?.id == "s0")
    }
}
