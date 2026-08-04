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
    /// Under the PCM substrate these are the scheduler's own records, whose lengths are **actually
    /// produced output** rather than declared or ratio-estimated.
    var scheduledSegments: [GaplessScheduledSegment] {
        #if DEBUG
        if schedulingMode == .fileSegment { return fileSegments }
        #endif
        return bufferScheduler.segments
    }
    private var pendingBoundaryEvents: [GaplessBoundaryEvent] = []
    /// Boundaries already reported, keyed by play instance so a Repeat One replay is never
    /// mistaken for a duplicate of the previous play.
    private var reportedInstances: Set<GaplessPlayInstanceID> = []

    /// Timeline frames completed by schedules that have since been torn down (seek, skip). The
    /// player node's own sample clock resets on `stop()`, so this keeps the timeline monotonic.
    private var timelineOffset: AVAudioFramePosition = 0
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

    /// The PCM substrate. Built lazily so a backend that is never started allocates no pool.
    private(set) lazy var bufferScheduler = GaplessBufferScheduler(
        player: engine.player, renderFormat: engine.renderFormat)

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
        return bufferScheduler.openFileCount
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
    func start() throws {
        if state == .playing { return }                       // duplicate Play is a no-op
        guard state != .starting else { return }               // a start is already in flight
        if state == .idle { try prepareGraph() }
        if state == .paused { try resume(); return }
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
        engine.player.play()
        try transition(to: .playing)
    }

    func pause() {
        guard state == .playing else { return }
        // Pausing the node, not the engine: the graph, the scheduled tail, the EQ and ReplayGain
        // state and the visualizer feed all stay exactly as they are.
        engine.player.pause()
        state = .paused
    }

    func resume() throws {
        guard state == .paused else { return }
        if !engine.engine.isRunning {
            do { try engine.engine.start() } catch {
                state = .failed
                throw GaplessEngineFailure.engineStartFailed(error.localizedDescription)
            }
        }
        engine.player.play()
        state = .playing
    }

    func stop() {
        guard state.isActive || state == .prepared else { return }
        state = .stopping
        engine.player.stop()
        engine.engine.stop()
        fileSegments.removeAll()
        bufferScheduler.resetAfterNodeStop(resumeTimelineFrame: 0)
        pendingBoundaryEvents.removeAll()
        reportedInstances.removeAll()
        timelineOffset = 0
        scheduleOriginFrame = 0
        monotonicFrame = 0
        tailGeneration += 1
        #if DEBUG
        openFiles.removeAll()
        openFileOrder.removeAll()
        #endif
        engine.gainStage.reset()
        deactivateAudioSession?()
        state = .idle
    }

    // MARK: - Scheduling

    /// Append prepared tracks to the timeline.
    ///
    /// `scheduleSegment` is used rather than `scheduleFile` because the schedulable range is not
    /// always the whole file — an MP3 with a valid Xing/LAME header must have its encoder delay and
    /// padding excluded, and only the segment API can express that. The frame count comes from
    /// `GaplessPreparedTrack.trim`, which preparation resolved from the decoded file, so the count
    /// is the true audio length rather than the container's.
    ///
    /// `completionCallbackType: .dataRendered` is used because `.dataConsumed` fires when the node
    /// has merely *taken* the data, which on this architecture happens a whole track early. Even so,
    /// the callback is not treated as the audible boundary — boundaries come from the clock (see
    /// `observeBoundaries`), because a completion callback tells you a segment finished, not when
    /// the next one became audible.
    @discardableResult
    func schedule(_ tracks: [(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
                              generation: UInt64)]) throws -> [GaplessScheduledSegment] {
        #if DEBUG
        if schedulingMode == .fileSegment { return try scheduleAsFileSegments(tracks) }
        #endif
        var created: [GaplessScheduledSegment] = []
        for entry in tracks {
            do {
                created.append(try bufferScheduler.enqueue(track: entry.track, itemID: entry.itemID,
                                                           generation: entry.generation))
            } catch {
                throw GaplessEngineFailure.scheduleFailed(error.localizedDescription)
            }
        }
        // Produce immediately so the lead is filled before the boundary rather than at it.
        bufferScheduler.pump()
        return created
    }

    #if DEBUG
    /// The original substrate, retained for comparison only. Unsafe for long persistent sessions:
    /// every file handed to the node is retained until the node stops.
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
    /// and re-schedule from the audible position. The timeline offset preserves monotonic frame
    /// accounting across that, so elapsed time and boundary identity survive the rebuild.
    @discardableResult
    func resetTail() -> AVAudioFramePosition {
        let resumeFrame = renderFrame
        let wasPlaying = state == .playing
        // `AVAudioPlayerNode` has no surgical per-buffer cancellation: `stop()` discards *every*
        // pending schedule, including the audible one. That is the only mechanism available, so a
        // tail replacement is always a stop-and-reschedule, and the audible position is preserved by
        // arithmetic (the timeline offset) rather than by the node.
        engine.player.stop()
        tailGeneration += 1
        timelineOffset = resumeFrame
        scheduleOriginFrame = resumeFrame
        // EVERY segment record is dropped, including the audible one — `stop()` discarded its
        // remaining audio along with the rest, so keeping its record would describe audio that no
        // longer exists and place the replacement at the wrong timeline frame. A caller that wants
        // the current track to continue must re-schedule it from `audibleOffset(of:)`.
        fileSegments.removeAll()
        // Every discarded chunk token is invalidated with the tail bump, every safe buffer returns
        // to the pool exactly once, and any conversion still running for the old tail is cancelled
        // so it cannot write into a buffer that now belongs to a newer generation.
        bufferScheduler.resetAfterNodeStop(resumeTimelineFrame: resumeFrame)
        reportedInstances.removeAll()
        if wasPlaying, engine.engine.isRunning { engine.player.play() }
        return resumeFrame
    }

    /// How far into its own audio the given item currently is, for re-scheduling it after a tail
    /// replacement. Must be read *before* `resetTail()`, which discards the segment records.
    func audibleOffset(of itemID: GaplessQueueItemID) -> AVAudioFramePosition? {
        guard let segment = scheduledSegments.last(where: { $0.itemID == itemID }) else { return nil }
        return max(0, renderFrame - segment.startFrame)
    }

    /// Drop segment records for audio that has already played, so the timeline record stays bounded
    /// across a long run. The audible segment and everything after it are kept.
    func pruneSegments(before instance: GaplessPlayInstanceID) {
        #if DEBUG
        if schedulingMode == .fileSegment {
            guard let index = fileSegments.firstIndex(where: { $0.playInstance == instance }),
                  index > 0 else { return }
            fileSegments.removeFirst(index)
            return
        }
        #endif
        bufferScheduler.pruneSegments(before: instance)
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
    func observeBoundaries() {
        #if DEBUG
        let usingBuffers = schedulingMode == .pcmBuffer
        #else
        let usingBuffers = true
        #endif
        // Top the schedule up first: the pump is what turns enqueued tracks into scheduled audio,
        // and a boundary can only be observed against audio that exists.
        if usingBuffers { bufferScheduler.pump() }
        let frame = renderFrame
        for segment in scheduledSegments
        where segment.startFrame <= frame && !reportedInstances.contains(segment.playInstance) {
            // A record whose start is still the enqueue-time estimate describes audio that has not
            // been scheduled yet. Observing a boundary against an estimate would name a track as
            // audible at a frame it may never occupy.
            if usingBuffers, !bufferScheduler.materializedInstances.contains(segment.playInstance) {
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
