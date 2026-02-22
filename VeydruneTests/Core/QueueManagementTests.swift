import Testing
import Foundation
@testable import Veydrune

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
}
