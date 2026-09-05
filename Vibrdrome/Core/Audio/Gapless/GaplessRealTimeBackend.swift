import AVFoundation
import Foundation
import os.log

/// A reading of the real-time playback clock, mapping hardware time all the way to a queue item.
///
/// The chain is: player node time → engine render time → scheduled timeline frame → queue item →
/// source-relative frame → elapsed seconds. Every consumer (boundary events, elapsed time, seek
/// position, completion eligibility, and later Now Playing and scrobbling) reads from this one
/// place, so they cannot disagree with each other.
struct GaplessClockReading: Sendable, Equatable {
    let hostTime: UInt64
    let sampleTime: AVAudioFramePosition
    /// Position on the scheduled timeline, which survives pause and accumulates across segments.
    let timelineFrame: AVAudioFramePosition
    let itemID: GaplessQueueItemID?
    let playInstance: GaplessPlayInstanceID?
    /// Frames into the current item's own audio.
    let sourceRelativeFrame: AVAudioFramePosition
    let elapsedSeconds: TimeInterval
    let generation: UInt64
    let isPlayerPlaying: Bool
    let engineState: GaplessEngineState
}

/// Drives the persistent graph in real time.
///
/// Nothing here activates an audio session or starts hardware except `start()` / `resume()`. Graph
/// construction, format configuration, preparation and scheduling are all deliberately passive, so
/// launching the app — or restoring a queue, or preparing the lookahead — cannot interrupt whatever
/// the user is already listening to. That is the Build 60 cold-launch behaviour, and it is preserved
/// by making activation an explicit, separate step rather than a side effect of being ready.
///
/// **Division of labour with `GaplessAudioDomain`.** This backend owns the lifecycle state machine,
/// the audio session, the engine, the render clock and boundary observation — all main-actor
/// concerns. The domain owns the PCM pipeline and is the **only** thing that mutates the player
/// node (`scheduleBuffer`, `play`, `pause`, `stop`), on `GaplessAudioActor`, so refill keeps
/// running when iOS deprioritises main-actor work in the background. The backend never touches the
/// node directly on the production path; it awaits the domain, and answers its own synchronous
/// reads from an immutable cached readout.
@MainActor
final class GaplessRealTimeBackend: GaplessRenderBackend {
    let engine: PersistentGaplessEngine
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessRealTime")
    private let instances = GaplessPlayInstanceAllocator()

    private(set) var state: GaplessEngineState = .idle
    /// Timeline records for the DEBUG file path; the PCM path keeps its own, already reconciled.
    private var fileSegments: [GaplessScheduledSegment] = []

    /// Segments currently on the timeline, in play order.
    ///
    /// Under the PCM substrate these are the domain scheduler's own records — lengths are
    /// **actually produced output** — read from the cached readout, which is refreshed after every
    /// awaited domain operation and on every heartbeat tick. Boundary observation tolerates that
    /// staleness by design; anything needing strong ordering awaits the domain instead.
    var scheduledSegments: [GaplessScheduledSegment] {
        #if DEBUG
        if schedulingMode == .fileSegment { return fileSegments }
        #endif
        return cachedReadout.segments
    }
    private var pendingBoundaryEvents: [GaplessBoundaryEvent] = []
    /// Boundaries already reported, keyed by play instance so a Repeat One replay is never
    /// mistaken for a duplicate of the previous play.
    private var reportedInstances: Set<GaplessPlayInstanceID> = []

    /// Timeline frames completed by schedules that have since been torn down (seek, skip). The
    /// player node's own sample clock resets on `stop()`, so this keeps the timeline monotonic.
    /// Readable for diagnostics: raw clock vs `timelineOffset` vs logical frame is what
    /// distinguishes "audio stopped" from "the raw clock rebased and nobody rebased the epoch".
    private(set) var timelineOffset: AVAudioFramePosition = 0

    // MARK: - Raw-clock forensics (detect-only)
    //
    // The session-index freeze observed on device is consistent with the node's raw sample clock
    // rebasing UNCOMMANDED (route/engine reconfiguration) while the monotonic clamp pins the
    // logical frame at its old high-water mark. The commanded paths — `resetTail()` and teardown —
    // already rebase `timelineOffset` correctly. Until the mechanism is proven, this block only
    // OBSERVES: it retains the previous raw reading, flags the two commanded windows, and records a
    // material raw regression outside them. It changes no behaviour.

    /// Raw `playerTime` retained from the previous read, for discontinuity comparison. Cleared
    /// around commanded resets so the first post-reset reading is a new epoch, not a regression.
    private(set) var lastRawSampleTime: AVAudioFramePosition?
    private(set) var lastRawSampleRate: Double?
    /// True inside `resetTail()` and teardown, the two paths that legitimately reset the raw clock.
    private(set) var commandedClockResetInProgress = false
    /// What last rebased (or failed to rebase) the clock epoch, for the Debug screen and export.
    private(set) var lastClockRebaseDescription = "none"
    private(set) var clockDiscontinuityCount = 0
    /// A raw regression must exceed measured jitter by a wide margin to count. Jitter was measured
    /// at under ~1,000 frames; one second is 44,100.
    private static let discontinuityThresholdFrames: AVAudioFramePosition = 44_100

    /// Retain the raw reading and record — never act on — a material uncommanded regression.
    private func noteRawClockReading(_ playerTime: AVAudioTime) {
        defer {
            lastRawSampleTime = playerTime.sampleTime
            lastRawSampleRate = playerTime.sampleRate
        }
        guard !commandedClockResetInProgress, clockOverride == nil,
              let previous = lastRawSampleTime else { return }
        let regressed = previous - playerTime.sampleTime > Self.discontinuityThresholdFrames
        let rateChanged = lastRawSampleRate.map { $0 != playerTime.sampleRate } ?? false
        guard regressed || rateChanged else { return }
        clockDiscontinuityCount += 1
        lastClockRebaseDescription = """
            DISCONTINUITY observed (unhandled): raw \(previous) -> \(playerTime.sampleTime) \
            @ \(lastRawSampleRate ?? 0) -> \(playerTime.sampleRate) Hz, \
            logical \(monotonicFrame), offset \(timelineOffset), tail \(tailGeneration)
            """
        log.warning("""
            raw-clock discontinuity (unhandled): raw \(previous, privacy: .public) -> \
            \(playerTime.sampleTime, privacy: .public), rate \
            \(self.lastRawSampleRate ?? 0, privacy: .public) -> \
            \(playerTime.sampleRate, privacy: .public), logical frame \
            \(self.monotonicFrame, privacy: .public), timeline offset \
            \(self.timelineOffset, privacy: .public), tail \(self.tailGeneration, privacy: .public)
            """)
    }
    /// Frame at which the current schedule begins on the timeline.
    private(set) var scheduleOriginFrame: AVAudioFramePosition = 0
    /// Identity of the current scheduled tail. Bumped by every replacement, so audio and callbacks
    /// belonging to a discarded tail can be recognised and ignored.
    private(set) var tailGeneration: UInt64 = 1

    /// How this backend hands audio to the player node.
    ///
    /// Production is `.pcmBuffer`. The file path exists only for controlled comparison and is
    /// **DEBUG-only**: in the tested persistent `AVAudioPlayerNode` configuration, `scheduleSegment`
    /// retains each supplied `AVAudioFile` and file descriptor until the node is stopped, which makes
    /// a long uninterrupted session unbounded in both. It is unsafe for long persistent sessions and
    /// cannot be selected in a release build.
    enum SchedulingMode: String, Sendable {
        case pcmBuffer
        #if DEBUG
        case fileSegment
        #endif
    }

    private(set) var schedulingMode: SchedulingMode = .pcmBuffer

    /// Change the scheduling substrate. Refused while a track is audible — swapping substrates under
    /// a playing track would cut the output stream, which is the defect this architecture exists to
    /// remove.
    @discardableResult
    func setSchedulingMode(_ mode: SchedulingMode) -> Bool {
        guard state != .playing else { return false }
        guard mode != schedulingMode else { return true }
        schedulingMode = mode
        return true
    }

    // MARK: - The audio domain

    /// The PCM substrate's owner: the one `GaplessAudioDomain` this backend ever constructs.
    ///
    /// Built on first use — a backend that is never started allocates no pool — and retained for
    /// the backend's lifetime, so every session on this assembly reuses the same domain, the same
    /// scheduler and the same pool. Every production player-node mutation happens inside it.
    private(set) var audioDomain: GaplessAudioDomain?
    /// Construction in flight, so two callers suspended across the actor hop cannot build two
    /// domains over one node.
    private var audioDomainConstruction: Task<GaplessAudioDomain, Never>?

    private func ensureAudioDomain() async -> GaplessAudioDomain {
        if let audioDomain { return audioDomain }
        let construction: Task<GaplessAudioDomain, Never>
        if let inFlight = audioDomainConstruction {
            construction = inFlight
        } else {
            let handle = GaplessGraphHandle(engine: engine.engine, player: engine.player,
                                            renderFormat: engine.renderFormat)
            construction = Task { await GaplessAudioDomain(graph: handle) }
            audioDomainConstruction = construction
        }
        let built = await construction.value
        if audioDomain == nil { audioDomain = built }
        audioDomainConstruction = nil
        return built
    }

    /// The immutable readout this backend's synchronous reads are answered from.
    ///
    /// Refreshed after every awaited domain operation and on every tick. Good for diagnostics and
    /// boundary scanning; never the basis for a teardown or resource decision — those await the
    /// domain and read its answer directly.
    private(set) var cachedReadout = GaplessAudioDomainReadout()

    private func refreshReadout(from domain: GaplessAudioDomain) async {
        cachedReadout = await domain.readout()
    }

    // MARK: - Ordered transport lane

    /// The one ordered lane for transport work started by a synchronous façade call.
    ///
    /// `stop()`, `pause()` and `resume()` keep their synchronous application contract by enqueueing
    /// their domain work here; each operation runs strictly after the previous one, so a teardown
    /// and a node resume can never interleave. `settleTransport()` is the honest completion seam:
    /// awaiting it means every transition ordered so far — including a stop's full teardown — has
    /// finished.
    private var orderedTransportTail: Task<Void, Never>?

    private func orderTransport(_ operation: @escaping @MainActor () async -> Void) {
        let previous = orderedTransportTail
        orderedTransportTail = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    /// Await every transport operation ordered so far. After this returns with no new work
    /// enqueued, a preceding `stop()` has completed its teardown and `.idle` is real.
    func settleTransport() async {
        while let tail = orderedTransportTail {
            await tail.value
            if orderedTransportTail == tail {
                orderedTransportTail = nil
                break
            }
        }
    }

    #if DEBUG
    /// Open `AVAudioFile` objects for the DEBUG file-segment comparison path only.
    ///
    /// **Not a bound and not a fix.** It removes redundant opens when the working set fits, but the
    /// node retains every file it is handed until stop regardless, so a queue larger than the cache
    /// still grows without limit — measured at ~141 KB per transition over a one-hour run. Kept
    /// solely so the two substrates can be compared; production does not use it.
    private var openFiles: [URL: AVAudioFile] = [:]
    private var openFileOrder: [URL] = []
    static let maximumOpenFiles = 6

    private func openFile(at url: URL) throws -> AVAudioFile {
        if let cached = openFiles[url] {
            openFileOrder.removeAll { $0 == url }
            openFileOrder.append(url)
            return cached
        }
        let file = try AVAudioFile(forReading: url)
        openFiles[url] = file
        openFileOrder.append(url)
        while openFileOrder.count > Self.maximumOpenFiles {
            let evicted = openFileOrder.removeFirst()
            openFiles[evicted] = nil
        }
        return file
    }
    #endif

    /// Live open-file count. In production this is the preparation window's own count — the PCM
    /// substrate holds a file only while there is still audio to read from it.
    var openFileCount: Int {
        #if DEBUG
        if schedulingMode == .fileSegment { return openFiles.count }
        #endif
        return cachedReadout.snapshot.openFiles
    }

    /// Injected so tests can drive the clock deterministically instead of sleeping.
    var clockOverride: (() -> AVAudioFramePosition)?

    /// Activates the audio session. Injected so tests can run without touching the real session and
    /// so the activation step stays visible rather than buried.
    var activateAudioSession: (() throws -> Void)?
    /// Called on stop, following existing session-deactivation policy.
    var deactivateAudioSession: (() -> Void)?

    init(engine: PersistentGaplessEngine = PersistentGaplessEngine()) {
        self.engine = engine
    }

    // MARK: - Lifecycle

    private func transition(to next: GaplessEngineState) throws {
        guard state.canTransition(to: next) else {
            throw GaplessEngineFailure.illegalTransition(from: state, to: next)
        }
        state = next
    }

    /// Build the graph. Explicitly passive: no session, no hardware, nothing started.
    func prepareGraph() throws {
        guard state == .idle else { return }
        // The graph is constructed in PersistentGaplessEngine's init; `prepare` only warms the
        // nodes' internal buffers, which does not activate anything.
        engine.engine.prepare()
        try transition(to: .prepared)
    }

    /// Begin playback. The only operation permitted to activate the audio session.
    ///
    /// The ordering is the design: audio session and engine start on the main actor — the two steps
    /// that can fail, and the application's job — then the node plays inside the audio domain, after
    /// whatever PCM is already enqueued has been produced. The node is never played before the
    /// engine is running.
    func start() async throws {
        // A stop ordered just before this start must finish tearing down first, or this start
        // would build on state the teardown is about to clear.
        await settleTransport()
        if state == .playing { return }                       // duplicate Play is a no-op
        guard state != .starting else { return }               // a start is already in flight
        if state == .idle { try prepareGraph() }
        if state == .paused { try resume(); await settleTransport(); return }
        try transition(to: .starting)

        do {
            try activateAudioSession?()
        } catch {
            state = .failed
            throw GaplessEngineFailure.audioSessionActivationFailed(error.localizedDescription)
        }
        do {
            try engine.engine.start()
        } catch {
            state = .failed
            throw GaplessEngineFailure.engineStartFailed(error.localizedDescription)
        }
        // The one permanent visualizer tap, installed with the engine's first start and idempotent
        // after that. Consumers (the visualizer adapters) come and go; the tap and the graph never
        // change for them — that per-track churn was the proven cause of the old transition freeze.
        engine.installVisualizerFeed()
        let domain = await ensureAudioDomain()
        await domain.play()
        await refreshReadout(from: domain)
        try transition(to: .playing)
    }

    /// Pause the node, not the engine: the graph, the scheduled tail, the EQ and ReplayGain state
    /// and the visualizer feed all stay exactly as they are. Synchronous façade — the node pause is
    /// ordered onto the audio domain, guarded so a resume issued straight after wins.
    func pause() {
        guard state == .playing else { return }
        state = .paused
        orderTransport { [weak self] in
            guard let self, self.state == .paused else { return }
            await self.audioDomain?.pause()
        }
    }

    /// Resume the same session. The engine restart — the only part that can fail — stays
    /// synchronous on the main actor, preserving the throwing contract; the node resume is ordered
    /// onto the audio domain behind whatever transition is already in flight.
    func resume() throws {
        guard state == .paused else { return }
        if !engine.engine.isRunning {
            do { try engine.engine.start() } catch {
                state = .failed
                throw GaplessEngineFailure.engineStartFailed(error.localizedDescription)
            }
        }
        state = .playing
        orderTransport { [weak self] in
            guard let self, self.state == .playing else { return }
            await self.audioDomain?.resume()
        }
    }

    /// End the session and leave the graph reusable. Synchronous façade over an ordered, awaited
    /// teardown: `.stopping` is published immediately, `.idle` only once the domain has actually
    /// stopped the node, drained refill, reconciled recycle tokens, reclaimed the pool and closed
    /// its sources. `settleTransport()` is how a caller waits for that completion.
    ///
    /// **`.failed` is a stop-able state, not a dead end.** A start that threw part way still holds
    /// everything the attempt built — buffers on the player node, open source files, live
    /// converters, pool tickets — and the assembly that owns this backend is retained for the
    /// process lifetime, so refusing to stop from `.failed` would leave those held and make every
    /// later persistent session on the same instance unusable.
    func stop() {
        guard state.isActive || state == .prepared || state == .failed else { return }
        // A teardown is already ordered; a second would only release the same nothing again.
        if state == .stopping { return }
        // `.failed` is the one entry that must not pass through `.stopping`: the state machine
        // permits exactly one exit from it, `.failed -> .idle`, because a start that failed left no
        // running graph for a "stopping" phase to describe.
        if state != .failed { state = .stopping }
        orderTransport { [weak self] in
            guard let self else { return }
            await self.releaseTransportResources()
            // Published only after everything above has actually been released. A backend that
            // merely *reported* `.idle` while the domain still held buffers and files would be
            // worse than one that stayed failed, because the next start would build on top of them.
            self.state = .idle
        }
    }

    /// Return a backend that failed to start to a reusable idle state.
    ///
    /// **Only from `.failed`.** A live session must be stopped, not reset: `stop()` is what ends
    /// audio that is or could still be flowing, and letting a reset stand in for it would tear down
    /// a playing session as though it had already died. From `.idle` there is nothing to release —
    /// notably, this never constructs the audio domain, so a reset on a backend that never ran
    /// allocates no pool. Idempotent: the second call sees `.idle` and does nothing. Completion is
    /// awaited through `settleTransport()`, same as `stop()`.
    func resetAfterFailure() {
        guard state == .failed else { return }
        stop()
    }

    /// Release everything a session holds. The caller owns the state transition around it.
    ///
    /// Ordered node-first, inside the domain: stopping the player node is what discards its pending
    /// schedules and returns their buffers, so the scheduler's reset — which reclaims the pool and
    /// closes the sources — follows it on the same actor turn rather than racing it. A refill
    /// wakeup that arrives mid-teardown waits its turn on the actor and then finds nothing to do.
    private func releaseTransportResources() async {
        commandedClockResetInProgress = true
        lastRawSampleTime = nil
        lastRawSampleRate = nil
        defer {
            lastClockRebaseDescription = "commanded teardown"
            commandedClockResetInProgress = false
        }
        if let audioDomain {
            await audioDomain.stopAndReset()
            await refreshReadout(from: audioDomain)
        }
        engine.engine.stop()
        fileSegments.removeAll()
        pendingBoundaryEvents.removeAll()
        reportedInstances.removeAll()
        timelineOffset = 0
        scheduleOriginFrame = 0
        monotonicFrame = 0
        // Bumped last so any callback or event still in flight from the ended session is recognised
        // as stale by `isCurrentTail` rather than attributed to whatever starts next.
        tailGeneration += 1
        #if DEBUG
        openFiles.removeAll()
        openFileOrder.removeAll()
        #endif
        engine.gainStage.reset()
        // Engine teardown is the one sanctioned uninstall point for the visualizer tap — never a
        // visualizer closing, never a track boundary. The next start reinstalls it.
        engine.uninstallVisualizerFeed()
        // The persistent side must hold no audio-session claim once its session has ended, whether
        // it ended by stopping or by failing. A start that failed before activation deactivates a
        // session it never activated, which is harmless: the next owner activates on its own start.
        deactivateAudioSession?()
    }

    // MARK: - Scheduling

    /// Append prepared tracks to the timeline, as one atomic domain operation.
    ///
    /// `expectedTailGeneration` is the fence for work planned before a suspension: the caller
    /// captures `cachedReadout.tailGeneration` before its awaits, and a batch whose tail has since
    /// been replaced by a stop or reset is refused (`GaplessEngineFailure.scheduleSuperseded`)
    /// rather than scheduled into the replacement tail. The check happens inside the domain, in the
    /// same actor turn as the enqueue.
    @discardableResult
    func schedule(_ tracks: [(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
                              generation: UInt64)],
                  expectedTailGeneration: UInt64) async throws -> [GaplessScheduledSegment] {
        #if DEBUG
        if schedulingMode == .fileSegment { return try scheduleAsFileSegments(tracks) }
        #endif
        let domain = await ensureAudioDomain()
        do {
            let created = try await domain.schedule(batch: tracks,
                                                    expectedTailGeneration: expectedTailGeneration)
            await refreshReadout(from: domain)
            return created
        } catch is GaplessAudioDomainError {
            await refreshReadout(from: domain)
            throw GaplessEngineFailure.scheduleSuperseded
        } catch {
            throw GaplessEngineFailure.scheduleFailed(error.localizedDescription)
        }
    }

    #if DEBUG
    /// The original substrate, retained for comparison only. Unsafe for long persistent sessions:
    /// every file handed to the node is retained until the node stops. This is the one deliberate
    /// node mutation outside the audio domain, and it cannot be selected in a release build.
    private func scheduleAsFileSegments(
        _ tracks: [(track: GaplessPreparedTrack, itemID: GaplessQueueItemID, generation: UInt64)]
    ) throws -> [GaplessScheduledSegment] {
        var created: [GaplessScheduledSegment] = []
        for entry in tracks {
            let start = fileSegments.last?.endFrame ?? scheduleOriginFrame
            let file: AVAudioFile
            do {
                file = try openFile(at: entry.track.fileURL)
            } catch {
                throw GaplessEngineFailure.scheduleFailed(error.localizedDescription)
            }
            let segment = GaplessScheduledSegment(
                playInstance: instances.allocate(), itemID: entry.itemID,
                songID: entry.track.trackID, generation: entry.generation,
                tailGeneration: tailGeneration,
                startFrame: start, frameCount: entry.track.renderFrames,
                sourceStartOffsetFrames: entry.track.sourceStartOffsetFrames)
            engine.player.scheduleSegment(file, startingFrame: entry.track.trim.startFrame,
                                          frameCount: entry.track.trim.frameCount, at: nil,
                                          completionCallbackType: .dataRendered) { _ in }
            fileSegments.append(segment)
            created.append(segment)
        }
        return created
    }
    #endif

    /// Drop everything not yet audible. The player node cannot remove a single future buffer, so the
    /// narrowest available operation is to stop the node — which discards *all* pending schedules —
    /// and re-schedule from the audible position. The stop, the scheduler reset and the optional
    /// restart happen as one domain operation, so a refill wakeup cannot land between them; the
    /// timeline offset preserves monotonic frame accounting across the rebuild, so elapsed time and
    /// boundary identity survive it.
    @discardableResult
    func resetTail() async -> AVAudioFramePosition {
        let resumeFrame = renderFrame
        let wasPlaying = state == .playing
        // A commanded epoch change: the raw clock is about to reset because we are stopping the
        // node, and the offset arithmetic below rebases for it. The forensics must not count it.
        commandedClockResetInProgress = true
        lastRawSampleTime = nil
        lastRawSampleRate = nil
        defer {
            lastClockRebaseDescription = "commanded tail reset at frame \(resumeFrame)"
            commandedClockResetInProgress = false
        }
        let domain = await ensureAudioDomain()
        // EVERY segment record is dropped, including the audible one — the node stop discards its
        // remaining audio along with the rest, so keeping its record would describe audio that no
        // longer exists. A caller that wants the current track to continue must re-schedule it from
        // `audibleOffset(of:)`, read *before* this call.
        await domain.resetTail(resumeTimelineFrame: resumeFrame,
                               resumePlaying: wasPlaying && engine.engine.isRunning)
        await refreshReadout(from: domain)
        // Main-actor bookkeeping lands after the node has actually stopped; a clock read that
        // interleaved with the hop above saw the old schedule's coherent reading, and the monotonic
        // clamp absorbs the node's sample-clock reset.
        tailGeneration += 1
        timelineOffset = resumeFrame
        scheduleOriginFrame = resumeFrame
        fileSegments.removeAll()
        reportedInstances.removeAll()
        return resumeFrame
    }

    /// How far into its own audio the given item currently is, for re-scheduling it after a tail
    /// replacement. Must be read *before* `resetTail()`, which discards the segment records.
    func audibleOffset(of itemID: GaplessQueueItemID) -> AVAudioFramePosition? {
        guard let segment = scheduledSegments.last(where: { $0.itemID == itemID }) else { return nil }
        return max(0, renderFrame - segment.startFrame)
    }

    /// Drop segment records for audio that has already played, so the timeline record stays bounded
    /// across a long run. The audible segment and everything after it are kept. The cached readout
    /// gates the hop: when it shows nothing before the audible instance, there is nothing to prune.
    func pruneSegments(before instance: GaplessPlayInstanceID) async {
        #if DEBUG
        if schedulingMode == .fileSegment {
            guard let index = fileSegments.firstIndex(where: { $0.playInstance == instance }),
                  index > 0 else { return }
            fileSegments.removeFirst(index)
            return
        }
        #endif
        guard let audioDomain,
              let index = cachedReadout.segments.firstIndex(where: { $0.playInstance == instance }),
              index > 0 else { return }
        await audioDomain.pruneSegments(before: instance)
        await refreshReadout(from: audioDomain)
    }

    /// Whether a callback or event carrying `tailGeneration` still describes live audio.
    func isCurrentTail(_ candidate: UInt64) -> Bool { candidate == tailGeneration }

    // MARK: - Clock

    /// Highest timeline frame reported so far. The timeline is an accounting of frames rendered, so
    /// it must never run backwards — but the underlying hardware clock can: `lastRenderTime` /
    /// `playerTime(forNodeTime:)` are sampled asynchronously and were measured regressing across a
    /// tail rebuild (a reading of 1411 after an earlier reading of 2351). Elapsed time, boundary
    /// detection and seek positions are all derived from this, and every one of them would misbehave
    /// on a backwards step, so monotonicity is enforced here rather than defended at each use.
    private var monotonicFrame: AVAudioFramePosition = 0

    /// Position on the scheduled timeline. Survives pause (the node's sample clock holds) and
    /// survives a tail rebuild (the offset carries the frames already played).
    var renderFrame: AVAudioFramePosition {
        if let clockOverride { return clockOverride() }
        let sampled: AVAudioFramePosition
        if let nodeTime = engine.player.lastRenderTime,
           let playerTime = engine.player.playerTime(forNodeTime: nodeTime) {
            noteRawClockReading(playerTime)
            sampled = timelineOffset + playerTime.sampleTime
        } else {
            sampled = timelineOffset
        }
        monotonicFrame = max(monotonicFrame, sampled)
        return monotonicFrame
    }

    /// Full clock reading, mapping hardware time to a queue item and a source-relative frame.
    func clockReading(generation: UInt64) -> GaplessClockReading {
        let frame = renderFrame
        let segment = scheduledSegments.last { $0.startFrame <= frame && frame < $0.endFrame }
        let nodeTime = engine.player.lastRenderTime
        let playerTime = nodeTime.flatMap { engine.player.playerTime(forNodeTime: $0) }
        // Position in the TRACK, not on the timeline: after a seek the segment begins partway into
        // the track's own audio, and reporting the timeline offset alone would show time-since-seek.
        let sourceRelative = segment.map { $0.sourceStartOffsetFrames + (frame - $0.startFrame) } ?? 0
        return GaplessClockReading(
            hostTime: nodeTime?.hostTime ?? 0,
            sampleTime: playerTime?.sampleTime ?? 0,
            timelineFrame: frame,
            itemID: segment?.itemID,
            playInstance: segment?.playInstance,
            sourceRelativeFrame: sourceRelative,
            elapsedSeconds: Double(sourceRelative) / engine.renderFormat.sampleRate,
            generation: generation,
            isPlayerPlaying: engine.player.isPlaying,
            engineState: state)
    }

    // MARK: - Boundary observation

    /// Turn clock progress into boundary events.
    ///
    /// Driven by the clock rather than by scheduling callbacks: a completion callback says a segment
    /// finished feeding, which is not the same instant the next one became audible. Identity is the
    /// **play instance**, so a Repeat One replay of the same slot produces a genuinely new event
    /// instead of being suppressed as a duplicate.
    func observeBoundaries() async {
        #if DEBUG
        let usingBuffers = schedulingMode == .pcmBuffer
        #else
        let usingBuffers = true
        #endif
        // Top the schedule up first: refill is what turns enqueued tracks into scheduled audio, and
        // a boundary can only be observed against audio that exists. This also refreshes the cached
        // readout, which is what the scan below runs on.
        if usingBuffers, let audioDomain {
            await audioDomain.refill()
            await refreshReadout(from: audioDomain)
        }
        let frame = renderFrame
        for segment in scheduledSegments
        where segment.startFrame <= frame && !reportedInstances.contains(segment.playInstance) {
            // A record whose start is still the enqueue-time estimate describes audio that has not
            // been scheduled yet. Observing a boundary against an estimate would name a track as
            // audible at a frame it may never occupy.
            if usingBuffers, !cachedReadout.materializedInstances.contains(segment.playInstance) {
                continue
            }
            reportedInstances.insert(segment.playInstance)
            pendingBoundaryEvents.append(GaplessBoundaryEvent(
                playInstance: segment.playInstance, itemID: segment.itemID, songID: segment.songID,
                generation: segment.generation, tailGeneration: segment.tailGeneration,
                scheduledStartFrame: segment.startFrame,
                observedRenderFrame: frame,
                replayGainLinear: engine.gainStage.currentGain.linear,
                eqEnabled: engine.eqStage.settings.isEnabled,
                visualizerFeedInstalled: engine.visualizerFeed.isInstalled))
        }
    }

    func drainBoundaryEvents() -> [GaplessBoundaryEvent] {
        defer { pendingBoundaryEvents.removeAll() }
        return pendingBoundaryEvents
    }
}
