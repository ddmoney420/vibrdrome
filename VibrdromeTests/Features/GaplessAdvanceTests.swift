import Testing
import Combine
import Foundation
@testable import Vibrdrome

/// Pure branch-selection tests for the gapless end-of-track advance decision (Lane 1).
struct GaplessAdvanceDecisionTests {

    @Test func immediateAdvanceWhenAlreadyPromoted() {
        #expect(GaplessAdvanceDecision.decide(
            currentItemIsEndItem: false, hasLookahead: true,
            lookaheadQueued: true, lookaheadReady: true) == .autoAdvance)
    }

    @Test func immediateAdvancePreservesOriginalSemantics() {
        // Original behavior: currentItem advanced + hasLookahead -> auto path, regardless of
        // whether the queued lookahead is "ready". The new "await" case must not steal this.
        #expect(GaplessAdvanceDecision.decide(
            currentItemIsEndItem: false, hasLookahead: true,
            lookaheadQueued: false, lookaheadReady: false) == .autoAdvance)
    }

    @Test func awaitWhenReadyQueuedLookaheadNotYetPromoted() {
        #expect(GaplessAdvanceDecision.decide(
            currentItemIsEndItem: true, hasLookahead: true,
            lookaheadQueued: true, lookaheadReady: true) == .awaitPromotion)
    }

    @Test func reloadWhenNoLookahead() {
        #expect(GaplessAdvanceDecision.decide(
            currentItemIsEndItem: true, hasLookahead: false,
            lookaheadQueued: false, lookaheadReady: false) == .reload)
    }

    @Test func reloadWhenLookaheadNotReady() {
        #expect(GaplessAdvanceDecision.decide(
            currentItemIsEndItem: true, hasLookahead: true,
            lookaheadQueued: true, lookaheadReady: false) == .reload)
    }

    @Test func reloadWhenLookaheadNotQueued() {
        #expect(GaplessAdvanceDecision.decide(
            currentItemIsEndItem: true, hasLookahead: true,
            lookaheadQueued: false, lookaheadReady: true) == .reload)
    }
}

/// Resolution-mechanism tests for the one-shot promotion waiter (Lane 1).
@MainActor
struct GaplessPromotionWaiterTests {

    /// Delayed promotion: the wait is armed, then the promotion event arrives.
    @Test func resolvesTrueOnPromotion() {
        let waiter = GaplessPromotionWaiter()
        let subject = PassthroughSubject<Bool, Never>()
        var results: [Bool] = []
        waiter.arm(promotion: subject.eraseToAnyPublisher(), timeoutSeconds: 10) { results.append($0) }
        subject.send(false)   // not promoted yet -> ignored
        subject.send(true)    // promotion
        #expect(results == [true])
        #expect(waiter.isWaiting == false)
    }

    /// Duplicate end/promotion events must resolve exactly once.
    @Test func duplicatePromotionResolvesExactlyOnce() {
        let waiter = GaplessPromotionWaiter()
        let subject = PassthroughSubject<Bool, Never>()
        var results: [Bool] = []
        waiter.arm(promotion: subject.eraseToAnyPublisher(), timeoutSeconds: 10) { results.append($0) }
        subject.send(true)
        subject.send(true)   // duplicate -> ignored
        #expect(results == [true])
    }

    /// Cancellation (playback replaced / stopped / skipped / generation change) prevents resolve.
    @Test func cancelPreventsResolution() {
        let waiter = GaplessPromotionWaiter()
        let subject = PassthroughSubject<Bool, Never>()
        var results: [Bool] = []
        waiter.arm(promotion: subject.eraseToAnyPublisher(), timeoutSeconds: 10) { results.append($0) }
        waiter.cancel()
        subject.send(true)   // after cancel -> ignored
        #expect(results.isEmpty)
        #expect(waiter.isWaiting == false)
    }

    /// Timeout fallback: no promotion -> resolves false (the existing reload path).
    @Test func timeoutResolvesFalse() async {
        let waiter = GaplessPromotionWaiter()
        let subject = PassthroughSubject<Bool, Never>()
        var results: [Bool] = []
        waiter.arm(promotion: subject.eraseToAnyPublisher(), timeoutSeconds: 0.05) { results.append($0) }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(results == [false])
        #expect(waiter.isWaiting == false)
    }

    /// A promotion suppresses the pending timeout (no double resolution).
    @Test func promotionSuppressesTimeout() async {
        let waiter = GaplessPromotionWaiter()
        let subject = PassthroughSubject<Bool, Never>()
        var results: [Bool] = []
        waiter.arm(promotion: subject.eraseToAnyPublisher(), timeoutSeconds: 0.1) { results.append($0) }
        subject.send(true)
        try? await Task.sleep(for: .milliseconds(250))   // well past the timeout
        #expect(results == [true])
    }
}
