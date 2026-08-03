import Foundation

/// Pure rolling-window policy for the persistent gapless engine: which upcoming tracks must already
/// be decoded from a local file, and which prepared tracks can be released.
///
/// The window is **current + next fully ready + one more preparing**. The next track has to be local
/// and openable *before* the current one ends, because the engine schedules it into the running
/// player node ahead of the boundary — a network fetch at the boundary is exactly the underrun this
/// architecture exists to remove. The third slot absorbs the fetch time of the one after that, so a
/// slow download has a whole track's duration to complete rather than a few seconds.
///
/// Deliberately has no networking, no `AVAudioEngine`, and no queue-model dependency — it works on
/// track IDs so the policy is unit-testable in isolation.
struct GaplessPrefetchWindow: Equatable {
    /// Tracks after the current one that must be fully prepared (local file open, frames known).
    let readyAhead: Int
    /// Tracks beyond those that may be fetching in the background.
    let preparingAhead: Int

    init(readyAhead: Int = 1, preparingAhead: Int = 1) {
        self.readyAhead = max(0, readyAhead)
        self.preparingAhead = max(0, preparingAhead)
    }

    /// Total tracks the window covers, including the current one.
    var size: Int { 1 + readyAhead + preparingAhead }

    /// The window's track IDs, current first, clamped to the queue's bounds.
    /// Returns empty for an out-of-range index so a stale current-index can't schedule audio.
    func trackIDs(queue: [String], currentIndex: Int) -> [String] {
        guard queue.indices.contains(currentIndex) else { return [] }
        let end = min(queue.count, currentIndex + size)
        return Array(queue[currentIndex..<end])
    }

    /// The subset that must be *fully ready* (current + `readyAhead`) — the boundary-critical ones.
    /// If any of these is missing when its boundary arrives, playback underruns.
    func mustBeReadyTrackIDs(queue: [String], currentIndex: Int) -> [String] {
        guard queue.indices.contains(currentIndex) else { return [] }
        let end = min(queue.count, currentIndex + 1 + readyAhead)
        return Array(queue[currentIndex..<end])
    }

    /// Which tracks to start preparing now: in the window, not already prepared, not already
    /// in flight. Returned in play order so the most imminent boundary is fetched first.
    func trackIDsToPrepare(queue: [String], currentIndex: Int,
                           prepared: Set<String>, inFlight: Set<String>) -> [String] {
        trackIDs(queue: queue, currentIndex: currentIndex)
            .filter { !prepared.contains($0) && !inFlight.contains($0) }
    }

    /// Prepared tracks that have fallen outside the window and can be released.
    ///
    /// Tracks *behind* the current index are included: once a track has been rendered its decoded
    /// state is dead weight, and holding it pins cache files that the rolling cache wants to reap.
    func trackIDsToRelease(queue: [String], currentIndex: Int, prepared: Set<String>) -> [String] {
        let keep = Set(trackIDs(queue: queue, currentIndex: currentIndex))
        return prepared.subtracting(keep).sorted()
    }

    /// Whether every boundary-critical track is prepared — the precondition for a gapless join.
    /// False means the next transition will not be gapless, which the engine must report rather
    /// than disguise.
    func isBoundarySafe(queue: [String], currentIndex: Int, prepared: Set<String>) -> Bool {
        let required = mustBeReadyTrackIDs(queue: queue, currentIndex: currentIndex)
        guard !required.isEmpty else { return false }
        return required.allSatisfy { prepared.contains($0) }
    }
}
