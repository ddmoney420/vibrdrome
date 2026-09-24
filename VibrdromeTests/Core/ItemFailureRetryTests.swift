import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// The bounded legacy item-failure retry: the initial failure plus (max-1) reloads for the same
/// song, then an honest give-up — replacing the old unbounded 2s loop that spun forever when every
/// rebuilt item failed instantly (the -11819 media-services-reset storm). Budget logic is pure and
/// covered here; the give-up side effects and 2s reload are exercised on-device.
@Suite(.serialized)
@MainActor
struct ItemFailureRetryTests {

    // MARK: - Threshold policy

    /// No song context → stop cleanly, never retry.
    @Test func noSongStops() {
        #expect(AudioEngine.itemFailureDecision(hasSong: false, failureCount: 1) == .stopNoSong)
        #expect(AudioEngine.itemFailureDecision(hasSong: false, failureCount: 9) == .stopNoSong)
    }

    /// The initial failure and the first reload stay under budget → retry.
    @Test func underBudgetRetries() {
        #expect(AudioEngine.itemFailureDecision(hasSong: true, failureCount: 1) == .retry)
        #expect(AudioEngine.itemFailureDecision(hasSong: true, failureCount: 2) == .retry)
    }

    /// The third consecutive failure (initial + 2 retries) exhausts the budget → honest give-up.
    @Test func atBudgetGivesUp() {
        #expect(AudioEngine.maxConsecutiveItemFailures == 3)
        #expect(AudioEngine.itemFailureDecision(hasSong: true, failureCount: 3) == .giveUp)
        #expect(AudioEngine.itemFailureDecision(hasSong: true, failureCount: 4) == .giveUp)
    }

    // MARK: - Per-song counting

    /// The same song accumulates failures; a different song resets to its own first failure.
    @Test func countAccumulatesPerSong() {
        #expect(AudioEngine.nextFailureCount(priorCount: 0, priorSongId: nil, currentSongId: "A") == 1)
        #expect(AudioEngine.nextFailureCount(priorCount: 1, priorSongId: "A", currentSongId: "A") == 2)
        #expect(AudioEngine.nextFailureCount(priorCount: 2, priorSongId: "A", currentSongId: "A") == 3)
        // Song changed → fresh budget starting at this song's first failure.
        #expect(AudioEngine.nextFailureCount(priorCount: 2, priorSongId: "A", currentSongId: "B") == 1)
        #expect(AudioEngine.nextFailureCount(priorCount: 3, priorSongId: "A", currentSongId: nil) == 1)
    }

    /// Two failures on song A then one on song B ends with B at failure #1 (A's count discarded).
    @Test func countResetsOnSongChange() {
        var count = 0
        count = AudioEngine.nextFailureCount(priorCount: count, priorSongId: nil, currentSongId: "A")
        count = AudioEngine.nextFailureCount(priorCount: count, priorSongId: "A", currentSongId: "A")
        #expect(count == 2)
        count = AudioEngine.nextFailureCount(priorCount: count, priorSongId: "A", currentSongId: "B")
        #expect(count == 1)
    }

    // MARK: - Reset mechanism

    /// resetFailedItemRetries clears the budget — the mechanism used on success/new-song/Stop/
    /// give-up recovery.
    @Test func resetClearsBudget() {
        let engine = AudioEngine.shared
        engine.failedRetryCount = 5
        engine.failedRetrySongId = "stale"

        engine.resetFailedItemRetries()

        #expect(engine.failedRetryCount == 0)
        #expect(engine.failedRetrySongId == nil)
    }
}
