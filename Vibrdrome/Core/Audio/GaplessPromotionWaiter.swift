import Combine
import Foundation

/// How to advance when a gapless item reaches its end. Pure, side-effect-free so the branch
/// selection is unit-testable without a live `AVQueuePlayer`.
enum GaplessAdvanceDecision: Equatable {
    /// The queue player already promoted the next item — take the existing gapless path.
    case autoAdvance
    /// The queue player has a prepared, queued, ready lookahead but hasn't synchronously
    /// promoted it yet — wait for the real promotion event before deciding (the end-of-track
    /// race). Avoids reloading an already-buffered track.
    case awaitPromotion
    /// No usable lookahead (end of queue, repeat-one, not queued, or not ready) — reload.
    case reload

    /// Preserves the original auto-advance/reload semantics and carves out `awaitPromotion`
    /// from what was previously the reload case.
    static func decide(currentItemIsEndItem: Bool,
                       hasLookahead: Bool,
                       lookaheadQueued: Bool,
                       lookaheadReady: Bool) -> GaplessAdvanceDecision {
        if !currentItemIsEndItem && hasLookahead { return .autoAdvance }
        if currentItemIsEndItem && hasLookahead && lookaheadQueued && lookaheadReady {
            return .awaitPromotion
        }
        return .reload
    }
}

/// One-shot wait for the gapless lookahead to be promoted to `AVQueuePlayer.currentItem`.
///
/// Encapsulates the minimum state for the end-of-track promotion race: an event subscription,
/// a timeout, and a resolved latch. Resolves **exactly once** — on the promotion event or on
/// timeout — and can be cancelled (playback replaced/stopped/skipped or generation change).
/// The promotion signal is injected as a publisher so the resolution logic is testable with a
/// `PassthroughSubject` (no live player needed).
@MainActor
final class GaplessPromotionWaiter {
    private var subscription: AnyCancellable?
    private var timeoutTask: Task<Void, Never>?
    private var onResolve: ((Bool) -> Void)?
    /// Starts idle (`true`) so a stray resolve before `arm` is a no-op.
    private var resolved = true

    /// Whether a wait is currently armed and unresolved.
    var isWaiting: Bool { !resolved }

    /// Arm the wait. `promotion` emits `true` when the lookahead becomes `currentItem`.
    /// Calls `onResolve(true)` on the first such emission, or `onResolve(false)` after
    /// `timeoutSeconds`. Re-arming cancels any prior wait.
    func arm(promotion: AnyPublisher<Bool, Never>,
             timeoutSeconds: TimeInterval,
             onResolve: @escaping (Bool) -> Void) {
        cancel()
        resolved = false
        self.onResolve = onResolve
        subscription = promotion.sink { [weak self] promoted in
            guard promoted else { return }
            self?.resolve(true)
        }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            guard !Task.isCancelled else { return }
            self?.resolve(false)
        }
    }

    /// Cancel a pending wait without resolving (no callback).
    func cancel() {
        resolved = true
        subscription?.cancel()
        subscription = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        onResolve = nil
    }

    private func resolve(_ promoted: Bool) {
        guard !resolved else { return }
        resolved = true
        let callback = onResolve
        onResolve = nil
        subscription?.cancel()
        subscription = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        callback?(promoted)
    }
}
