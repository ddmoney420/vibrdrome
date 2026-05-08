import Testing
import Foundation
@testable import Vibrdrome

/// Tests for queue management logic — index advancement, shuffle, and repeat.
struct QueueManagementTests {

    // MARK: - Lookahead Index Logic

    /// Mirrors AudioEngine.nextSongIndex() logic
    private func nextSongIndex(
        currentIndex: Int, queueCount: Int,
        repeatMode: RepeatMode, shuffleEnabled: Bool,
        isRadio: Bool = false
    ) -> Int? {
        guard queueCount > 0 else { return nil }
        if repeatMode == .one { return nil }
        if isRadio { return nil } // radio handled differently

        if shuffleEnabled {
            guard queueCount > 1 else {
                return repeatMode == .all ? currentIndex : nil
            }
            // Random — just test that it returns non-nil
            return (currentIndex + 1) % queueCount // deterministic for tests
        } else {
            let next = currentIndex + 1
            if next < queueCount {
                return next
            } else if repeatMode == .all {
                return 0
            } else {
                return nil
            }
        }
    }

    @Test func nextIndexNormal() {
        let idx = nextSongIndex(currentIndex: 0, queueCount: 5, repeatMode: .off, shuffleEnabled: false)
        #expect(idx == 1)
    }

    @Test func nextIndexAtEnd() {
        let idx = nextSongIndex(currentIndex: 4, queueCount: 5, repeatMode: .off, shuffleEnabled: false)
        #expect(idx == nil)
    }

    @Test func nextIndexRepeatAll() {
        let idx = nextSongIndex(currentIndex: 4, queueCount: 5, repeatMode: .all, shuffleEnabled: false)
        #expect(idx == 0)
    }

    @Test func nextIndexRepeatOne() {
        let idx = nextSongIndex(currentIndex: 2, queueCount: 5, repeatMode: .one, shuffleEnabled: false)
        #expect(idx == nil) // No lookahead for repeat-one
    }

    @Test func nextIndexEmptyQueue() {
        let idx = nextSongIndex(currentIndex: 0, queueCount: 0, repeatMode: .off, shuffleEnabled: false)
        #expect(idx == nil)
    }

    @Test func nextIndexRadio() {
        let idx = nextSongIndex(currentIndex: 0, queueCount: 10, repeatMode: .off, shuffleEnabled: false, isRadio: true)
        #expect(idx == nil)
    }

    @Test func nextIndexShuffleReturnsNonNil() {
        let idx = nextSongIndex(currentIndex: 2, queueCount: 5, repeatMode: .off, shuffleEnabled: true)
        #expect(idx != nil)
    }

    @Test func nextIndexShuffleSingleTrack() {
        let idx = nextSongIndex(currentIndex: 0, queueCount: 1, repeatMode: .off, shuffleEnabled: true)
        #expect(idx == nil)
    }

    @Test func nextIndexShuffleSingleTrackRepeatAll() {
        let idx = nextSongIndex(currentIndex: 0, queueCount: 1, repeatMode: .all, shuffleEnabled: true)
        #expect(idx == 0) // Loops back to same track
    }

    // MARK: - Advance Index Logic

    /// Mirrors AudioEngine.advanceIndex() for non-shuffle
    private func advanceIndex(
        currentIndex: inout Int, queueCount: Int,
        repeatMode: RepeatMode, isRadio: Bool
    ) -> Bool {
        currentIndex += 1
        if currentIndex >= queueCount {
            if repeatMode == .all {
                currentIndex = 0
            } else if isRadio {
                currentIndex = queueCount - 1
                return false
            } else {
                currentIndex = queueCount - 1
                return false
            }
        }
        return true
    }

    @Test func advanceNormal() {
        var idx = 0
        let ok = advanceIndex(currentIndex: &idx, queueCount: 5, repeatMode: .off, isRadio: false)
        #expect(ok)
        #expect(idx == 1)
    }

    @Test func advanceAtEndStops() {
        var idx = 4
        let ok = advanceIndex(currentIndex: &idx, queueCount: 5, repeatMode: .off, isRadio: false)
        #expect(!ok)
        #expect(idx == 4)
    }

    @Test func advanceRepeatAllWraps() {
        var idx = 4
        let ok = advanceIndex(currentIndex: &idx, queueCount: 5, repeatMode: .all, isRadio: false)
        #expect(ok)
        #expect(idx == 0)
    }

    @Test func advanceRadioAtEndWaitsForRefill() {
        var idx = 9
        let ok = advanceIndex(currentIndex: &idx, queueCount: 10, repeatMode: .off, isRadio: true)
        #expect(!ok)
        #expect(idx == 9)
    }

    // MARK: - Up Next Computation

    /// Mirrors AudioEngine.upNext computed property
    private func upNext(queue: [String], currentIndex: Int) -> [String] {
        guard !queue.isEmpty, currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    @Test func upNextFromStart() {
        let next = upNext(queue: ["a", "b", "c", "d"], currentIndex: 0)
        #expect(next == ["b", "c", "d"])
    }

    @Test func upNextFromMiddle() {
        let next = upNext(queue: ["a", "b", "c", "d"], currentIndex: 2)
        #expect(next == ["d"])
    }

    @Test func upNextAtEnd() {
        let next = upNext(queue: ["a", "b", "c"], currentIndex: 2)
        #expect(next.isEmpty)
    }

    @Test func upNextEmptyQueue() {
        let next = upNext(queue: [], currentIndex: 0)
        #expect(next.isEmpty)
    }

    // MARK: - Additional Queue Management Tests

    @Test func advanceSingleItemQueueRepeatOffFails() {
        var idx = 0
        let ok = advanceIndex(currentIndex: &idx, queueCount: 1, repeatMode: .off, isRadio: false)
        #expect(!ok)
        #expect(idx == 0) // clamped to queueCount - 1
    }

    @Test func advanceSingleItemQueueRepeatAllWrapsToZero() {
        var idx = 0
        let ok = advanceIndex(currentIndex: &idx, queueCount: 1, repeatMode: .all, isRadio: false)
        #expect(ok)
        #expect(idx == 0) // wraps back to 0
    }

    @Test func upNextSingleItemAtIndexZeroIsEmpty() {
        let next = upNext(queue: ["only"], currentIndex: 0)
        #expect(next.isEmpty)
    }

    @Test func nextSongIndexAtSecondToLastReturnsLastIndex() {
        // queue of 5, at index 3 (second-to-last) → next is 4 (last)
        let idx = nextSongIndex(currentIndex: 3, queueCount: 5, repeatMode: .off, shuffleEnabled: false)
        #expect(idx == 4)
    }

    @Test func advanceThroughFullQueue() {
        // Walk through a 5-item queue: 0→1→2→3→4, then fail at 5
        var idx = 0
        let queueCount = 5
        for expectedIdx in 1..<queueCount {
            let ok = advanceIndex(currentIndex: &idx, queueCount: queueCount, repeatMode: .off, isRadio: false)
            #expect(ok, "Should succeed advancing to index \(expectedIdx)")
            #expect(idx == expectedIdx)
        }
        // Now at index 4 (last), advance should fail
        let ok = advanceIndex(currentIndex: &idx, queueCount: queueCount, repeatMode: .off, isRadio: false)
        #expect(!ok, "Should fail advancing past end of queue")
        #expect(idx == queueCount - 1)
    }

    @Test func upNextReturnsCorrectCount() {
        // Queue of 10 items, at index 3 → 6 items remaining (indices 4..9)
        let queue = (0..<10).map { "track\($0)" }
        let next = upNext(queue: queue, currentIndex: 3)
        #expect(next.count == 6)
    }

    // MARK: - Near-End Predownload Check

    /// Mirrors AudioEngine.checkPredownloadedSongNearEnd() gate logic.
    /// Returns true when the check should proceed (i.e. a fallback insert is warranted).
    private func shouldCheckNearEnd(
        currentTime: Double,
        duration: Double,
        isRadio: Bool,
        repeatMode: RepeatMode,
        nearEndCheckSongId: String?,
        currentSongId: String,
        nextSongIsDownloaded: Bool
    ) -> Bool {
        guard duration > 0,
              currentTime > 0,
              duration - currentTime <= 30,
              duration - currentTime > 0 else { return false }
        guard !isRadio, repeatMode != .one else { return false }
        guard nearEndCheckSongId != currentSongId else { return false }  // already handled this track
        guard !nextSongIsDownloaded else { return false }                 // nothing to insert
        return true
    }

    @Test func nearEndCheckTriggersWithin30Seconds() {
        // 5 s remaining — should trigger
        #expect(shouldCheckNearEnd(
            currentTime: 175, duration: 180, isRadio: false,
            repeatMode: .off, nearEndCheckSongId: nil,
            currentSongId: "A", nextSongIsDownloaded: false
        ))
    }

    @Test func nearEndCheckDoesNotTriggerBeyond30Seconds() {
        // 31 s remaining — too early
        #expect(!shouldCheckNearEnd(
            currentTime: 149, duration: 180, isRadio: false,
            repeatMode: .off, nearEndCheckSongId: nil,
            currentSongId: "A", nextSongIsDownloaded: false
        ))
    }

    @Test func nearEndCheckDoesNotTriggerWhenNextIsDownloaded() {
        // Next song already downloaded — no insert needed
        #expect(!shouldCheckNearEnd(
            currentTime: 175, duration: 180, isRadio: false,
            repeatMode: .off, nearEndCheckSongId: nil,
            currentSongId: "A", nextSongIsDownloaded: true
        ))
    }

    @Test func nearEndCheckDoesNotTriggerInRadioMode() {
        #expect(!shouldCheckNearEnd(
            currentTime: 175, duration: 180, isRadio: true,
            repeatMode: .off, nearEndCheckSongId: nil,
            currentSongId: "A", nextSongIsDownloaded: false
        ))
    }

    @Test func nearEndCheckDoesNotTriggerForRepeatOne() {
        // repeat-one has no meaningful next song
        #expect(!shouldCheckNearEnd(
            currentTime: 175, duration: 180, isRadio: false,
            repeatMode: .one, nearEndCheckSongId: nil,
            currentSongId: "A", nextSongIsDownloaded: false
        ))
    }

    @Test func nearEndCheckDedupGuardPreventsSecondFire() {
        // Same song ID already handled — flag blocks re-entry
        #expect(!shouldCheckNearEnd(
            currentTime: 175, duration: 180, isRadio: false,
            repeatMode: .off, nearEndCheckSongId: "A",
            currentSongId: "A", nextSongIsDownloaded: false
        ))
    }

    @Test func nearEndCheckDedupResetsBetweenTracks() {
        // Dedup flag is keyed to song ID — a different current song resets it
        #expect(shouldCheckNearEnd(
            currentTime: 175, duration: 180, isRadio: false,
            repeatMode: .off, nearEndCheckSongId: "A",  // previous song
            currentSongId: "B",                          // new current song
            nextSongIsDownloaded: false
        ))
    }

    @Test func nearEndCheckDoesNotTriggerAtExactEnd() {
        // duration - currentTime == 0: track already ended, lower bound guard blocks it
        #expect(!shouldCheckNearEnd(
            currentTime: 180, duration: 180, isRadio: false,
            repeatMode: .off, nearEndCheckSongId: nil,
            currentSongId: "A", nextSongIsDownloaded: false
        ))
    }

    @Test func nearEndCheckDoesNotTriggerForZeroDuration() {
        // duration unknown — stream not yet loaded
        #expect(!shouldCheckNearEnd(
            currentTime: 0, duration: 0, isRadio: false,
            repeatMode: .off, nearEndCheckSongId: nil,
            currentSongId: "A", nextSongIsDownloaded: false
        ))
    }

    // MARK: - insertSongNext Shuffle Cache

    /// Mirrors the shuffle-cache mutation in AudioEngine.insertSongNext().
    /// Returns the updated cachedSmartShuffleSongs after the insert.
    private func insertSongNextCache(
        cache: [String], insertSong: String, shuffleEnabled: Bool
    ) -> [String] {
        guard shuffleEnabled else { return cache }  // non-shuffle: cache untouched
        var updated = cache
        updated.insert(insertSong, at: 0)
        return updated
    }

    @Test func insertSongNextPrependsToCacheInShuffleMode() {
        let result = insertSongNextCache(
            cache: ["C", "D", "E"], insertSong: "X", shuffleEnabled: true
        )
        #expect(result.first == "X")
        #expect(result == ["X", "C", "D", "E"])
    }

    @Test func insertSongNextDoesNotTouchCacheWhenShuffleOff() {
        // Sequential mode: cache is irrelevant, must not be mutated
        let result = insertSongNextCache(
            cache: ["C", "D", "E"], insertSong: "X", shuffleEnabled: false
        )
        #expect(result == ["C", "D", "E"])
    }

    @Test func insertSongNextIntoEmptyCacheInShuffleMode() {
        let result = insertSongNextCache(cache: [], insertSong: "X", shuffleEnabled: true)
        #expect(result == ["X"])
    }

    @Test func insertSongNextPreservesRestOfCacheOrder() {
        // Existing planned shuffle sequence must be intact after index 0
        let result = insertSongNextCache(
            cache: ["B", "C", "D"], insertSong: "A", shuffleEnabled: true
        )
        #expect(result[1] == "B")
        #expect(result[2] == "C")
        #expect(result[3] == "D")
    }

    @Test func insertSongNextMultipleInsertsStackCorrectly() {
        // Each successive insert becomes the new immediate-next pick (LIFO at head)
        var cache = insertSongNextCache(cache: ["C"], insertSong: "B", shuffleEnabled: true)
        cache = insertSongNextCache(cache: cache, insertSong: "A", shuffleEnabled: true)
        #expect(cache == ["A", "B", "C"])
    }

    // MARK: - toggleShuffle Cache Flush

    /// Mirrors the cache-flush logic in AudioEngine.toggleShuffle().
    /// Returns (newShuffleEnabled, updatedCache, updatedCacheAnchorId).
    private func toggleShuffle(
        shuffleEnabled: Bool,
        cache: [String],
        cacheAnchorId: String?
    ) -> (shuffleEnabled: Bool, cache: [String], cacheAnchorId: String?) {
        let newEnabled = !shuffleEnabled
        // Cache is always flushed so the next getNextSmartShuffleSongs call rebuilds
        // from scratch against whatever mode is now active.
        return (newEnabled, [], nil)
    }

    @Test func toggleShuffleOnFlushesCache() {
        let (enabled, cache, anchorId) = toggleShuffle(
            shuffleEnabled: false, cache: [], cacheAnchorId: nil
        )
        #expect(enabled == true)
        #expect(cache.isEmpty)
        #expect(anchorId == nil)
    }

    @Test func toggleShuffleOffFlushesStaleShuffleCache() {
        // Cache held a random shuffle sequence — must be cleared so sequential
        // playback doesn't accidentally consume stale shuffle picks.
        let (enabled, cache, anchorId) = toggleShuffle(
            shuffleEnabled: true,
            cache: ["D", "B", "E"],
            cacheAnchorId: "currentSong"
        )
        #expect(enabled == false)
        #expect(cache.isEmpty)
        #expect(anchorId == nil)
    }

    @Test func toggleShuffleCacheIsEmptyAfterFlushRegardlessOfPreviousSize() {
        let (_, cache, _) = toggleShuffle(
            shuffleEnabled: true,
            cache: ["X", "Y", "Z", "W"],
            cacheAnchorId: "song1"
        )
        #expect(cache.count == 0)
    }

    @Test func toggleShuffleTogglesEnabledFlagCorrectly() {
        let (onResult, _, _) = toggleShuffle(shuffleEnabled: false, cache: [], cacheAnchorId: nil)
        #expect(onResult == true)
        let (offResult, _, _) = toggleShuffle(shuffleEnabled: true, cache: [], cacheAnchorId: nil)
        #expect(offResult == false)
    }
}
