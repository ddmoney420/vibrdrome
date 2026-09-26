import AVFoundation
import Foundation
import os.log

/// What a planned queue occurrence needs preparing *as*.
///
/// Deliberately not the song ID, and not the queue-slot ID alone. Repeat All wraps back to a slot,
/// Repeat One replays it, a queue can hold the same song in two slots, and a seek re-prepares the
/// same slot from a different position — all of which are genuinely distinct occurrences that must
/// not share one another's failure state. Equally, a pump cycle that changes nothing must produce
/// the *same* identity, or the retry counter would reset every tick and the storm would return.
struct GaplessPreparationIdentity: Hashable, Sendable {
    let itemID: GaplessQueueItemID
    let songID: String
    let queueGeneration: UInt64
    /// Where in the track this occurrence starts — a seek makes a new occurrence of the same slot.
    let sourceStartOffsetFrames: AVAudioFramePosition
    /// Which *play* of this slot this is.
    ///
    /// Advanced when the slot is successfully scheduled — so a Repeat All wrap or a Repeat One
    /// replay is a genuinely new occurrence that gets its own clean attempt — and when the user
    /// explicitly retries. Crucially it does **not** advance on an ordinary pump cycle or an
    /// unchanged tail rebuild, which is what keeps a failing item from being retried constantly.
    ///
    /// A permanently failed item is never scheduled, so its epoch never advances and it stays
    /// blocked; a playing item's epoch advances every time it is scheduled, so playback continues.
    let occurrenceEpoch: UInt64

    init(itemID: GaplessQueueItemID, songID: String, queueGeneration: UInt64,
         sourceStartOffsetFrames: AVAudioFramePosition = 0, occurrenceEpoch: UInt64 = 0) {
        self.itemID = itemID
        self.songID = songID
        self.queueGeneration = queueGeneration
        self.sourceStartOffsetFrames = sourceStartOffsetFrames
        self.occurrenceEpoch = occurrenceEpoch
    }
}

/// Whether a failure is worth trying again on its own.
enum GaplessFailureClassification: String, Sendable {
    /// Will fail identically however many times it is retried. One attempt, then stop.
    case permanent
    /// Might succeed later — a provider hiccup, a cache file being replaced, a network timeout.
    case transient
}

enum GaplessFailurePolicy {
    /// Classify a preparation or scheduling failure.
    ///
    /// The default is `.transient`: an unrecognised error retried a few times under backoff costs
    /// little, whereas wrongly calling something permanent makes a recoverable track unplayable
    /// until the user intervenes. Only failures that are *known* to be deterministic are permanent.
    static func classify(_ error: Error) -> GaplessFailureClassification {
        if error is CancellationError { return .transient }

        if let conversion = error as? GaplessConversionError {
            switch conversion {
            // The tail was superseded; the replacement occurrence gets its own clean attempt.
            case .cancelled: return .transient
            // A format pair the converter refuses, or a channel count the policy rejects, will be
            // refused identically every time.
            case .converterUnavailable, .unsupportedChannelCount, .unsupportedChannelLayout,
                 .conversionFailed:
                return .permanent
            }
        }
        if let source = error as? GaplessChunkSourceError {
            switch source {
            case .unsupportedFormat, .seekFailed: return .permanent
            // A read that failed once may be a cache file being swapped underneath us.
            case .readFailed: return .transient
            }
        }
        if let preparation = error as? GaplessPreparationError {
            switch preparation {
            // No local file yet is the provider's problem, and providers recover.
            case .noLocalFile: return .transient
            // The decoder has looked at the bytes and cannot read them.
            case .unreadable, .emptyAudio: return .permanent
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .unsupportedURL, .badURL, .fileDoesNotExist, .cannotDecodeContentData:
                return .permanent
            default: return .transient
            }
        }
        return .transient
    }
}

/// Serialises preparation attempts for planned occurrences, and stops a failing one from being
/// retried on every pump.
///
/// **The defect this exists to remove.** `replenishTail` re-attempted any not-yet-ready occurrence
/// on every `tick()`. A permanently unplayable source therefore produced 172–450 preparation
/// attempts in ~1.5 s — spinning CPU, flooding logs, and re-opening files or re-issuing requests
/// each time, indefinitely.
///
/// The pump may observe a failed occurrence as often as it likes; what is rationed is *work*. Both
/// numbers are recorded, so "no storm" is a measurement rather than a claim.
@MainActor
final class GaplessPreparationGate {
    enum State: Equatable {
        case idle
        case preparing
        case ready
        case scheduled
        /// Retryable, but not before `nextRetryAt` on the monotonic clock.
        case transientFailure(attempt: Int, nextRetryAt: TimeInterval)
        /// Will not be retried automatically at all.
        case permanentFailure(reason: String)
        case cancelled
    }

    /// Backoff schedule in seconds. Fixed and jitter-free so a test can assert the deadlines; any
    /// production jitter would have to be bounded and added deliberately.
    static let backoffSeconds: [TimeInterval] = [0.25, 0.5, 1, 2, 4]
    static let maximumBackoffSeconds: TimeInterval = 8

    static func backoff(forAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 1 else { return 0 }
        let index = attempt - 1
        return index < backoffSeconds.count ? backoffSeconds[index] : maximumBackoffSeconds
    }

    struct Entry: Sendable {
        var state: State
        var attempts: Int
        /// Pump observations that did not start work — the other half of the storm measurement.
        var suppressedPumps: Int
        var lastFailureAt: TimeInterval?
        var lastClassification: GaplessFailureClassification?
        var recoveredAfterAttempts: Int?
        var explicitRetries: Int
    }

    private var entries: [GaplessPreparationIdentity: Entry] = [:]
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessPrepGate")

    /// Monotonic seconds. Injectable so backoff can be tested without sleeping through it, and
    /// monotonic so a wall-clock change cannot make a retry deadline unreachable or immediate.
    var now: () -> TimeInterval = {
        TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    // MARK: - Queries

    func state(of identity: GaplessPreparationIdentity) -> State {
        entries[identity]?.state ?? .idle
    }

    func entry(for identity: GaplessPreparationIdentity) -> Entry? { entries[identity] }
    func attempts(for identity: GaplessPreparationIdentity) -> Int { entries[identity]?.attempts ?? 0 }
    func suppressedPumps(for identity: GaplessPreparationIdentity) -> Int {
        entries[identity]?.suppressedPumps ?? 0
    }

    /// Total real preparation attempts and total suppressed observations across every occurrence.
    var totalAttempts: Int { entries.values.reduce(0) { $0 + $1.attempts } }
    var totalSuppressedPumps: Int { entries.values.reduce(0) { $0 + $1.suppressedPumps } }
    var permanentFailureCount: Int {
        entries.values.filter { if case .permanentFailure = $0.state { return true } else { return false } }.count
    }

    // MARK: - The gate

    /// Whether a fresh attempt may start now. Counts a refusal as a suppressed pump.
    ///
    /// A single call decides and records, so two callers in one pump cycle cannot both be told yes.
    func beginAttemptIfAllowed(_ identity: GaplessPreparationIdentity) -> Bool {
        var entry = entries[identity] ?? Entry(state: .idle, attempts: 0, suppressedPumps: 0,
                                               lastFailureAt: nil, lastClassification: nil,
                                               recoveredAfterAttempts: nil, explicitRetries: 0)
        switch entry.state {
        case .preparing, .ready, .scheduled, .cancelled:
            // Already in flight, already done, or deliberately abandoned — no new work.
            entry.suppressedPumps += 1
            entries[identity] = entry
            return false
        case .permanentFailure:
            // Never automatically. Only an explicit retry or a new occurrence gets past this.
            entry.suppressedPumps += 1
            entries[identity] = entry
            return false
        case .transientFailure(_, let nextRetryAt):
            guard now() >= nextRetryAt else {
                entry.suppressedPumps += 1
                entries[identity] = entry
                return false
            }
        case .idle:
            break
        }
        entry.state = .preparing
        entry.attempts += 1
        entries[identity] = entry
        return true
    }

    func recordReady(_ identity: GaplessPreparationIdentity) {
        guard var entry = entries[identity] else { return }
        if entry.lastClassification != nil, entry.recoveredAfterAttempts == nil {
            entry.recoveredAfterAttempts = entry.attempts
            log.info("""
                preparation recovered for slot \(identity.itemID.rawValue, privacy: .public) \
                after \(entry.attempts, privacy: .public) attempt(s)
                """)
        }
        entry.state = .ready
        entries[identity] = entry
    }

    func recordScheduled(_ identity: GaplessPreparationIdentity) {
        guard var entry = entries[identity] else { return }
        entry.state = .scheduled
        entries[identity] = entry
    }

    /// Record a failure and decide what happens next. Returns how it was classified.
    @discardableResult
    func recordFailure(_ identity: GaplessPreparationIdentity, error: Error)
        -> GaplessFailureClassification {
        var entry = entries[identity] ?? Entry(state: .idle, attempts: 1, suppressedPumps: 0,
                                               lastFailureAt: nil, lastClassification: nil,
                                               recoveredAfterAttempts: nil, explicitRetries: 0)
        let classification = GaplessFailurePolicy.classify(error)
        let timestamp = now()
        entry.lastFailureAt = timestamp
        entry.lastClassification = classification

        switch classification {
        case .permanent:
            entry.state = .permanentFailure(reason: "\(type(of: error))")
            // Logged once, at the transition. The suppressed pumps that follow are counted, not
            // logged — logging every observation is the flood this exists to stop.
            log.error("""
                preparation permanently failed for slot \(identity.itemID.rawValue, privacy: .public): \
                \(error.localizedDescription, privacy: .public) — no automatic retry
                """)
        case .transient:
            let delay = Self.backoff(forAttempt: entry.attempts)
            entry.state = .transientFailure(attempt: entry.attempts, nextRetryAt: timestamp + delay)
            log.warning("""
                preparation attempt \(entry.attempts, privacy: .public) failed for slot \
                \(identity.itemID.rawValue, privacy: .public); retrying in \
                \(String(format: "%.2f", delay), privacy: .public)s
                """)
        }
        entries[identity] = entry
        return classification
    }

    /// User-driven retry: clears the failure and allows exactly one new attempt.
    ///
    /// Returns the identity to use for it — a *new* one, because a deliberate retry of something
    /// that permanently failed is a new occurrence, not a continuation of the failed one.
    func explicitRetry(_ identity: GaplessPreparationIdentity) -> GaplessPreparationIdentity {
        var previous = entries[identity]
        previous?.state = .cancelled
        if let previous { entries[identity] = previous }
        let fresh = GaplessPreparationIdentity(
            itemID: identity.itemID, songID: identity.songID,
            queueGeneration: identity.queueGeneration,
            sourceStartOffsetFrames: identity.sourceStartOffsetFrames,
            occurrenceEpoch: identity.occurrenceEpoch + 1)
        entries[fresh] = Entry(state: .idle, attempts: 0, suppressedPumps: 0, lastFailureAt: nil,
                               lastClassification: nil, recoveredAfterAttempts: nil,
                               explicitRetries: (previous?.explicitRetries ?? 0) + 1)
        return fresh
    }

    /// Abandon an occurrence. A pending retry deadline can never revive it.
    func cancel(_ identity: GaplessPreparationIdentity) {
        guard var entry = entries[identity] else { return }
        entry.state = .cancelled
        entries[identity] = entry
    }

    /// Abandon everything not belonging to `generation` — a queue replacement or reorder.
    func cancelAll(except generation: UInt64) {
        for (identity, var entry) in entries where identity.queueGeneration != generation {
            entry.state = .cancelled
            entries[identity] = entry
        }
    }

    /// Drop records for occurrences that can no longer be planned, so the table stays bounded across
    /// a long session. Cancelled and permanently failed entries for other generations are the ones
    /// that accumulate.
    func prune(keeping generation: UInt64, activeItems: Set<GaplessQueueItemID>) {
        entries = entries.filter { identity, _ in
            identity.queueGeneration == generation && activeItems.contains(identity.itemID)
        }
    }

    func reset() { entries.removeAll() }

    /// Compact, bounded diagnostics. Carries no URL, token or credential — only identities the app
    /// already holds.
    var diagnosticSummary: String {
        let states = entries.map { identity, entry -> String in
            let stateText: String
            switch entry.state {
            case .idle: stateText = "idle"
            case .preparing: stateText = "preparing"
            case .ready: stateText = "ready"
            case .scheduled: stateText = "scheduled"
            case .transientFailure(let attempt, let nextRetryAt):
                stateText = "transient(a\(attempt),next+\(String(format: "%.2f", nextRetryAt - now()))s)"
            case .permanentFailure(let reason): stateText = "permanent(\(reason))"
            case .cancelled: stateText = "cancelled"
            }
            let key = "slot\(identity.itemID.rawValue)/g\(identity.queueGeneration)"
            return "\(key)/o\(identity.occurrenceEpoch)=\(stateText)x\(entry.attempts)s\(entry.suppressedPumps)"
        }
        return states.sorted().joined(separator: " ")
    }
}
