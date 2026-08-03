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
    private(set) var scheduledSegments: [GaplessScheduledSegment] = []
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
        scheduledSegments.removeAll()
        pendingBoundaryEvents.removeAll()
        reportedInstances.removeAll()
        timelineOffset = 0
        scheduleOriginFrame = 0
        monotonicFrame = 0
        tailGeneration += 1
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
        var created: [GaplessScheduledSegment] = []
        for entry in tracks {
            let start = scheduledSegments.last?.endFrame ?? scheduleOriginFrame
            let file: AVAudioFile
            do {
                file = try AVAudioFile(forReading: entry.track.fileURL)
            } catch {
                throw GaplessEngineFailure.scheduleFailed(error.localizedDescription)
            }
            let segment = GaplessScheduledSegment(
                playInstance: instances.allocate(), itemID: entry.itemID,
                songID: entry.track.trackID, generation: entry.generation,
                tailGeneration: tailGeneration,
                startFrame: start, frameCount: entry.track.renderFrames)
            engine.player.scheduleSegment(file, startingFrame: entry.track.trim.startFrame,
                                          frameCount: entry.track.trim.frameCount, at: nil,
                                          completionCallbackType: .dataRendered) { _ in }
            scheduledSegments.append(segment)
            created.append(segment)
        }
        return created
    }

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
        // Keep the audible segment's record; everything after it is gone.
        scheduledSegments.removeAll { $0.startFrame > resumeFrame }
        // Play instances belonging to discarded segments must not be able to emit a boundary later.
        let surviving = Set(scheduledSegments.map(\.playInstance))
        reportedInstances.formIntersection(surviving.union(reportedInstances.filter { instance in
            scheduledSegments.contains { $0.playInstance == instance }
        }))
        if wasPlaying, engine.engine.isRunning { engine.player.play() }
        return resumeFrame
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
        let sourceRelative = segment.map { frame - $0.startFrame } ?? 0
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
        let frame = renderFrame
        for segment in scheduledSegments
        where segment.startFrame <= frame && !reportedInstances.contains(segment.playInstance) {
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
