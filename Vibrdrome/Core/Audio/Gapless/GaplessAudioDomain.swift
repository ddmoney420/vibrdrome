import AVFoundation
import Foundation

/// The serial execution domain that owns Persistent PCM scheduling.
///
/// **Why this exists.** Every part of the refill path was `@MainActor`: the buffer scheduler was
/// main-actor isolated and the recycle inbox reacted to a render-thread deposit with a hop back to
/// the main actor. iOS keeps a `UIBackgroundModes: audio` app alive while it plays but deprioritises
/// ordinary main-actor work, so once the ~372 ms already scheduled on the player node had been
/// rendered, nothing refilled it. Measured: a 1 s main-actor stall produced four render-side recycle
/// deposits where continuous playback needed eleven — the node ran dry, which is the click-and-pause
/// heard on device when the app was backgrounded.
///
/// Audio continuity therefore cannot depend on the main actor being serviced. It depends on *this*
/// domain being serviced, and this domain does nothing but produce and schedule PCM.
///
/// **Serial, and singular.** One assembly gets one domain gets one scheduler. Refill is a strictly
/// ordered pipeline — recycle, produce, schedule — over a fixed buffer pool whose accounting only
/// balances if exactly one thing mutates it at a time. Parallelism here would not make audio arrive
/// sooner; it would make the pool's books unprovable.
@globalActor
actor GaplessAudioActor {
    static let shared = GaplessAudioActor()
}

/// Carries the persistent graph's AVFoundation references into the audio domain.
///
/// **On the `@unchecked Sendable`.** This is not a claim that `AVAudioEngine` or
/// `AVAudioPlayerNode` are generally thread-safe, and it is deliberately not a reusable wrapper —
/// it exists for exactly one crossing.
///
/// What makes it sound is ownership, not the types:
///
/// - The handle crosses into **one** `GaplessAudioDomain` and is not shared with another.
/// - Every player-node mutation reached through that domain — `scheduleBuffer`, `play`, `pause`,
///   `stop` — is isolated to `GaplessAudioActor`, so those calls are serialized with each other and
///   with the scheduler and pool mutations they interleave with.
/// - The engine reference is carried for lifecycle *reads* the domain needs (`isRunning`); starting
///   and stopping the engine, and activating the audio session, remain the application's job and
///   stay outside this actor.
///
/// Production honours this: `GaplessRealTimeBackend` constructs exactly one domain over its graph
/// and routes every Persistent node mutation through it — the backend itself no longer calls
/// `scheduleBuffer`, `play`, `pause` or `stop` on the node. (The one deliberate exception is the
/// DEBUG-only file-segment comparison substrate, which cannot be selected in a release build.)
struct GaplessGraphHandle: @unchecked Sendable {
    let engine: AVAudioEngine
    let player: AVAudioPlayerNode
    let renderFormat: AVAudioFormat
}

/// An immutable readout of the domain, safe to hand to the main actor.
///
/// A value rather than a view onto the scheduler: exposing the live objects across the boundary is
/// what "do not expose mutable scheduler state cross-actor" exists to prevent, and a snapshot is
/// also what lets the Debug screen read this without blocking on the audio domain.
struct GaplessAudioDomainSnapshot: Sendable, Equatable {
    var isPlaying = false
    var scheduledDepth = 0
    var poolCapacity = 0
    var poolAvailable = 0
    var poolInFlight = 0
    var liveSources = 0
    var activeConverters = 0
    var openFiles = 0
    var scheduledSegments = 0
    /// Deposited by the render thread; the only starvation evidence that is not main-actor
    /// bookkeeping.
    var renderDeposits = 0
    var reconciledDeposits = 0
    var unreconciledDeposits: Int { max(0, renderDeposits - reconciledDeposits) }
    var refillExecutions = 0
    var chunksScheduled = 0
    var poolStarvations = 0
    var accountingBalances = true
    /// Recycle callbacks that named a superseded tail. Diagnostic, not an error: buffers are
    /// released regardless of staleness.
    var staleRecycles = 0
    var chunksRecycled = 0
    /// Chunks whose buffer came back because the node was stopped rather than because it finished
    /// playing them — the third term of the scheduled == recycled + reclaimed identity.
    var chunksReclaimedAtStop = 0
    /// Recycle tokens deposited by the render thread but not yet drained. Zero at rest.
    var pendingRecycleTokens = 0
    /// Tracks that failed during decode or conversion.
    var sourceFailures = 0
}

/// Everything the main actor may know about the domain's timeline, as one immutable value.
///
/// The production backend caches one of these and answers its synchronous reads — `scheduledSegments`,
/// `openFileCount`, boundary scanning — from the cache, refreshing it after every awaited domain
/// operation and on every heartbeat tick. Boundary observation tolerates that staleness by design:
/// a boundary not visible this tick is observed on the next, and events from a superseded tail are
/// dropped by generation. **A teardown or resource decision must never be made from this value** —
/// for strong ordering, await the domain directly.
struct GaplessAudioDomainReadout: Sendable {
    var snapshot = GaplessAudioDomainSnapshot()
    /// Segment records in play order, lengths reconciled to actually-produced output.
    var segments: [GaplessScheduledSegment] = []
    /// Play instances whose PCM has genuinely been scheduled — the only starts boundaries may be
    /// observed against.
    var materializedInstances: Set<GaplessPlayInstanceID> = []
    /// The scheduler's own tail generation. A schedule batch carrying an older value is refused,
    /// which is what stops work suspended across a stop or tail reset from landing in the
    /// replacement tail.
    var tailGeneration: UInt64 = 1
}

/// Why the domain refused an operation.
enum GaplessAudioDomainError: Error, Equatable {
    /// The batch was planned against a tail that a stop or reset has since replaced.
    case supersededTail(expected: UInt64, current: UInt64)
}

/// Owns the persistent graph's player node and its PCM pipeline, on `GaplessAudioActor`.
///
/// **Sole owner.** Within this architecture every `scheduleBuffer`, `play`, `pause` and `stop` on
/// the player node happens in a method of this class, and every method of this class is isolated to
/// `GaplessAudioActor`. That is the property the ownership test pins: it fails if one of those
/// mutations is ever reachable from anywhere else.
///
/// **Wired.** `GaplessRealTimeBackend` constructs exactly one of these over the production graph on
/// first use and retains it for the backend's lifetime, so a Persistent session's refill keeps
/// running when iOS deprioritises main-actor work in the background.
@GaplessAudioActor
final class GaplessAudioDomain {

    private let graph: GaplessGraphHandle
    private let scheduler: GaplessBufferScheduler

    private(set) var isPlaying = false
    private(set) var refillExecutions = 0
    private(set) var reconciledDeposits = 0

    /// Every player-node mutation this domain performed, in order. The ownership proof reads it.
    ///
    /// Deliberately not `#if DEBUG`: a seam that exists in one configuration and not the other is a
    /// seam that can rot in the one nobody compiles, and this one is a bounded array of small enum
    /// values recorded only when the kind of operation changes.
    private(set) var playerOperations: [PlayerOperation] = []

    enum PlayerOperation: String, Sendable, Equatable {
        case scheduleBuffer, play, pause, stop
    }

    init(graph: GaplessGraphHandle,
         chunkFrames: AVAudioFrameCount = 4_096,
         targetScheduledChunks: Int = 4,
         poolHeadroom: Int = 2) {
        self.graph = graph
        scheduler = GaplessBufferScheduler(
            player: graph.player, renderFormat: graph.renderFormat,
            chunkFrames: chunkFrames, targetScheduledChunks: targetScheduledChunks,
            poolHeadroom: poolHeadroom)
        // The wakeup lands here, not on the main actor. This one hop is the fix: the render
        // thread's deposit reaches the code that refills the node without waiting for main-actor
        // time that iOS need not grant while the app is backgrounded. Capturing `self` is safe
        // precisely because `self` is isolated to the same actor the Task runs on.
        scheduler.installRecycleWakeup { [weak self] in
            Task { @GaplessAudioActor [weak self] in self?.refill() }
        }
    }

    // MARK: - Scheduling

    /// Add a prepared track to the streaming order. Produces no audio by itself.
    @discardableResult
    func enqueue(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
                 generation: UInt64) throws -> GaplessScheduledSegment {
        try scheduler.enqueue(track: track, itemID: itemID, generation: generation)
    }

    /// Enqueue a prepared batch and produce immediately, as one atomic domain operation.
    ///
    /// `expectedTailGeneration` is the fence: the caller captures it before its awaits, and a batch
    /// whose tail has since been replaced — a stop or reset ran while the caller was suspended — is
    /// refused whole rather than scheduled into a tail it was never planned against. The check and
    /// the enqueue happen in one actor turn, so nothing can replace the tail between them.
    func schedule(batch: [(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
                           generation: UInt64)],
                  expectedTailGeneration: UInt64) throws -> [GaplessScheduledSegment] {
        guard scheduler.tailGeneration == expectedTailGeneration else {
            throw GaplessAudioDomainError.supersededTail(expected: expectedTailGeneration,
                                                         current: scheduler.tailGeneration)
        }
        var created: [GaplessScheduledSegment] = []
        for entry in batch {
            created.append(try scheduler.enqueue(track: entry.track, itemID: entry.itemID,
                                                 generation: entry.generation))
        }
        // Produce immediately so the lead is filled before the boundary rather than at it.
        refill()
        return created
    }

    /// Recycle finished buffers and top the schedule back up to its target depth.
    ///
    /// Called by the render-thread wakeup and directly at start. Serial by actor isolation, so two
    /// refills can never interleave over the pool.
    func refill() {
        refillExecutions += 1
        let before = scheduler.inbox.totalDeposits
        let scheduledBefore = scheduler.chunksScheduled
        scheduler.pump()
        // `pump` drains the inbox as its first step, so everything deposited before it ran has been
        // reconciled by the time it returns.
        reconciledDeposits = max(reconciledDeposits, before)
        if scheduler.chunksScheduled > scheduledBefore { record(.scheduleBuffer) }
    }

    // MARK: - Player-node lifecycle — the only place these are called

    /// Begin playback on the node.
    ///
    /// The caller is responsible for the audio session and for the engine already running: this
    /// domain deliberately does not activate a session or start an engine, so the ordering
    /// (session → engine → schedule → play) stays visible in application code.
    func play() {
        guard graph.engine.isRunning else { return }
        refill()
        graph.player.play()
        isPlaying = true
        record(.play)
    }

    func pause() {
        guard isPlaying else { return }
        graph.player.pause()
        isPlaying = false
        record(.pause)
    }

    /// Resume the same session. Keeps the scheduled tail, the sources and the pool exactly as they
    /// are — this is not a restart.
    func resume() {
        guard !isPlaying, graph.engine.isRunning else { return }
        graph.player.play()
        isPlaying = true
        record(.play)
    }

    /// End the session and release everything it holds.
    ///
    /// Ordered node-first: stopping the node is what discards its pending schedules and returns
    /// their buffers, so the scheduler's reset — which reclaims the pool and closes the sources —
    /// must follow it rather than race it. Because this method is actor-isolated, a refill wakeup
    /// that arrives mid-teardown simply waits its turn and then finds nothing to do.
    func stopAndReset() {
        graph.player.stop()
        record(.stop)
        isPlaying = false
        scheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
        // Callbacks the node delivered as it stopped land just after the reset; counting them keeps
        // the deposit ledger balanced rather than leaving tokens that look unreconciled forever.
        scheduler.reconcileLateCallbacks()
        reconciledDeposits = scheduler.inbox.totalDeposits
    }

    /// Replace the scheduled tail: stop the node, discard every pending schedule, and resume the
    /// timeline from the audible frame — the seek/skip mechanism, kept whole on this actor so a
    /// refill wakeup cannot land between the stop and the reset.
    ///
    /// `resumePlaying` restarts the node immediately (the caller re-schedules from the audible
    /// offset); it is honoured only while the engine is running, same as `resume()`.
    func resetTail(resumeTimelineFrame: AVAudioFramePosition, resumePlaying: Bool) {
        graph.player.stop()
        record(.stop)
        isPlaying = false
        scheduler.resetAfterNodeStop(resumeTimelineFrame: resumeTimelineFrame)
        scheduler.reconcileLateCallbacks()
        reconciledDeposits = scheduler.inbox.totalDeposits
        if resumePlaying, graph.engine.isRunning {
            graph.player.play()
            isPlaying = true
            record(.play)
        }
    }

    /// Drop timeline records for audio already played, keeping the record bounded over a long run.
    func pruneSegments(before instance: GaplessPlayInstanceID) {
        scheduler.pruneSegments(before: instance)
    }

    // MARK: - Readout

    func snapshot() -> GaplessAudioDomainSnapshot {
        GaplessAudioDomainSnapshot(
            isPlaying: isPlaying,
            scheduledDepth: scheduler.inFlightChunks.count,
            poolCapacity: scheduler.pool.capacity,
            poolAvailable: scheduler.pool.availableCount,
            poolInFlight: scheduler.pool.inFlightCount,
            liveSources: scheduler.liveSourceCount,
            activeConverters: scheduler.activeConverterCount,
            openFiles: scheduler.openFileCount,
            scheduledSegments: scheduler.segments.count,
            renderDeposits: scheduler.inbox.totalDeposits,
            reconciledDeposits: reconciledDeposits,
            refillExecutions: refillExecutions,
            chunksScheduled: scheduler.chunksScheduled,
            poolStarvations: scheduler.poolStarvations,
            accountingBalances: scheduler.chunkAccountingBalances,
            staleRecycles: scheduler.staleRecycles,
            chunksRecycled: scheduler.chunksRecycled,
            chunksReclaimedAtStop: scheduler.chunksReclaimedAtStop,
            pendingRecycleTokens: scheduler.inbox.pendingCount,
            sourceFailures: scheduler.failures.count)
    }

    /// Fold in completion callbacks the node delivered after a reset had already reclaimed their
    /// buffers. Returns how many were folded. The drain path handles stragglers with the same
    /// accounting on its own; this exists so a caller can force the fold at a known point.
    @discardableResult
    func reconcileLateCallbacks() -> Int {
        let late = scheduler.reconcileLateCallbacks()
        reconciledDeposits = scheduler.inbox.totalDeposits
        return late
    }

    /// The full timeline readout the production backend caches on the main actor.
    func readout() -> GaplessAudioDomainReadout {
        GaplessAudioDomainReadout(snapshot: snapshot(),
                                  segments: scheduler.segments,
                                  materializedInstances: scheduler.materializedInstances,
                                  tailGeneration: scheduler.tailGeneration)
    }

    /// Bounded: the proof only needs which kinds happened and in what order, not every repetition.
    private func record(_ operation: PlayerOperation) {
        guard playerOperations.count < 512, playerOperations.last != operation else { return }
        playerOperations.append(operation)
    }
}
