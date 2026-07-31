import Testing
@testable import Vibrdrome

/// Repeat-mode next-index policy (fix/repeat-all-advances-queue). Tests the pure
/// `AudioEngine.nextSequentialIndex` helper that drives both auto-advance and the gapless
/// lookahead, so Repeat All cycles the whole queue instead of re-looping the current track.
struct RepeatModeIndexTests {

    // 1. Two-item queue, Repeat Off: 0 -> 1, final item -> no next.
    @Test func twoItemRepeatOff() {
        #expect(AudioEngine.nextSequentialIndex(current: 0, count: 2, repeatMode: .off) == 1)
        #expect(AudioEngine.nextSequentialIndex(current: 1, count: 2, repeatMode: .off) == nil)
    }

    // 2. Two-item queue, Repeat All: 0 -> 1, 1 -> 0 (cycle the queue).
    @Test func twoItemRepeatAll() {
        #expect(AudioEngine.nextSequentialIndex(current: 0, count: 2, repeatMode: .all) == 1)
        #expect(AudioEngine.nextSequentialIndex(current: 1, count: 2, repeatMode: .all) == 0)
    }

    // 3. Two-item queue, Repeat One: 0 -> 0, 1 -> 1 (same track).
    @Test func twoItemRepeatOne() {
        #expect(AudioEngine.nextSequentialIndex(current: 0, count: 2, repeatMode: .one) == 0)
        #expect(AudioEngine.nextSequentialIndex(current: 1, count: 2, repeatMode: .one) == 1)
    }

    // 4. One-item queue: All -> 0, One -> 0, Off -> no next.
    @Test func oneItemQueue() {
        #expect(AudioEngine.nextSequentialIndex(current: 0, count: 1, repeatMode: .all) == 0)
        #expect(AudioEngine.nextSequentialIndex(current: 0, count: 1, repeatMode: .one) == 0)
        #expect(AudioEngine.nextSequentialIndex(current: 0, count: 1, repeatMode: .off) == nil)
    }

    // 5. Three-item queue, Repeat All cycles 0 -> 1 -> 2 -> 0.
    @Test func threeItemRepeatAllCycles() {
        #expect(AudioEngine.nextSequentialIndex(current: 0, count: 3, repeatMode: .all) == 1)
        #expect(AudioEngine.nextSequentialIndex(current: 1, count: 3, repeatMode: .all) == 2)
        #expect(AudioEngine.nextSequentialIndex(current: 2, count: 3, repeatMode: .all) == 0)
    }

    // Empty queue -> no next, every mode.
    @Test func emptyQueue() {
        #expect(AudioEngine.nextSequentialIndex(current: 0, count: 0, repeatMode: .off) == nil)
        #expect(AudioEngine.nextSequentialIndex(current: 0, count: 0, repeatMode: .all) == nil)
        #expect(AudioEngine.nextSequentialIndex(current: 0, count: 0, repeatMode: .one) == nil)
    }

    // Regression for the fixed bug: Repeat All previously returned `current` everywhere and never
    // advanced. Confirm it now advances off every index in a multi-item queue.
    @Test func repeatAllNeverStaysOnCurrentForMultiItem() {
        for current in 0..<3 {
            let next = AudioEngine.nextSequentialIndex(current: current, count: 3, repeatMode: .all)
            #expect(next != current, "Repeat All must advance off index \(current) in a 3-item queue")
        }
    }
}
