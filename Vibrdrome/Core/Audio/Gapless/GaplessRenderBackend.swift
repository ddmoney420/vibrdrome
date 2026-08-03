import AVFoundation
import Foundation

/// Lifecycle of the persistent engine.
///
/// Legal transitions:
/// ```
/// idle      → prepared            (graph built; NOTHING activated)
/// prepared  → starting → playing  (explicit play only)
/// playing   → paused   → playing
/// playing   → stopping → idle
/// paused    → stopping → idle
/// prepared  → stopping → idle     (torn down before ever playing)
/// any active state → failed
/// failed    → idle                (after teardown, so the graph is reusable)
/// ```
/// `starting` and `stopping` exist so a duplicate start or an overlapping stop/start can be rejected
/// rather than racing: both are asynchronous in real time, and without an explicit in-flight state a
/// second Play arriving mid-start would start the engine twice.
enum GaplessEngineState: String, Sendable, Equatable, CaseIterable {
    case idle, prepared, starting, playing, paused, stopping, failed

    /// Whether audio is or could be flowing — the window in which the graph must not be rebuilt.
    var isActive: Bool {
        switch self {
        case .starting, .playing, .paused, .stopping: return true
        case .idle, .prepared, .failed: return false
        }
    }

    func canTransition(to next: GaplessEngineState) -> Bool {
        switch (self, next) {
        case (_, .failed): return self != .failed
        case (.idle, .prepared), (.prepared, .starting), (.starting, .playing),
             (.playing, .paused), (.paused, .playing),
             (.playing, .stopping), (.paused, .stopping), (.prepared, .stopping),
             (.starting, .stopping), (.stopping, .idle), (.failed, .idle):
            return true
        default: return false
        }
    }
}

/// Why the engine failed, so a failure is a reportable fact rather than a silent stall.
enum GaplessEngineFailure: Error, Equatable, Sendable {
    case engineStartFailed(String)
    case audioSessionActivationFailed(String)
    case scheduleFailed(String)
    case illegalTransition(from: GaplessEngineState, to: GaplessEngineState)
}

/// One occurrence of a queue slot being played.
///
/// Distinct from the slot ID because Repeat One plays the *same slot* repeatedly, and each replay is
/// a separate play with its own boundary event, its own elapsed time and its own scrobble
/// eligibility. Song identity is even weaker — a queue can hold the same song twice.
struct GaplessPlayInstanceID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: UInt64
    var description: String { "p\(rawValue)" }
}

/// A scheduled segment on the render timeline, tying audio to the queue slot and play instance it
/// belongs to.
struct GaplessScheduledSegment: Sendable, Equatable {
    let playInstance: GaplessPlayInstanceID
    let itemID: GaplessQueueItemID
    let songID: String
    /// Queue generation the schedule was created under; anything older is stale.
    let generation: UInt64
    /// Which scheduled *tail* this segment belongs to.
    ///
    /// Deliberately separate from queue generation, slot ID and play instance. A seek or a skip
    /// replaces the tail without changing the queue at all, so queue generation cannot distinguish
    /// the old audio from the new; and the same slot can appear in both the discarded tail and its
    /// replacement, so slot ID cannot either. Callbacks carrying a superseded tail generation are
    /// ignored outright.
    let tailGeneration: UInt64
    let startFrame: AVAudioFramePosition
    let frameCount: AVAudioFramePosition
    var endFrame: AVAudioFramePosition { startFrame + frameCount }
}

/// A track boundary observed on the real render clock.
struct GaplessBoundaryEvent: Sendable, Equatable {
    let playInstance: GaplessPlayInstanceID
    let itemID: GaplessQueueItemID
    let songID: String
    let generation: UInt64
    /// Tail this boundary came from; a superseded tail must never emit one.
    let tailGeneration: UInt64
    let scheduledStartFrame: AVAudioFramePosition
    /// Where the clock actually was when the crossing was observed.
    let observedRenderFrame: AVAudioFramePosition
    /// How late the observation was, in frames. This is *observation* latency, not an audio gap:
    /// the audio itself is frame-exact, but the clock is sampled at a finite rate.
    var timingErrorFrames: AVAudioFramePosition { observedRenderFrame - scheduledStartFrame }
    let replayGainLinear: Float
    let eqEnabled: Bool
    let visualizerFeedInstalled: Bool
}

/// What the queue session needs from a render backend, whether it is rendering offline for a proof
/// or driving real hardware.
///
/// The session deliberately cannot tell the difference. Both backends consume the *same*
/// `GaplessPreparedTrack` values and the same segment model, so there is exactly one scheduler and
/// one set of scheduling semantics — an offline proof and a real-time run exercise the same code.
@MainActor
protocol GaplessRenderBackend: AnyObject {
    var state: GaplessEngineState { get }
    /// Frames rendered on this backend's timeline since the current schedule began.
    var renderFrame: AVAudioFramePosition { get }
    /// Segments currently on the timeline, in play order.
    var scheduledSegments: [GaplessScheduledSegment] { get }

    /// Build the graph. Must not activate an audio session or start anything.
    func prepareGraph() throws

    /// Append prepared tracks to the timeline.
    @discardableResult
    func schedule(_ tracks: [(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
                              generation: UInt64)]) throws -> [GaplessScheduledSegment]

    /// Begin playback. The ONLY operation permitted to activate the audio session.
    func start() throws
    func pause()
    func resume() throws
    func stop()

    /// Drop everything not yet audible, keeping the audible position. Returns the frame from which
    /// re-scheduling must resume.
    @discardableResult
    func resetTail() -> AVAudioFramePosition

    /// Boundary events observed since the last drain.
    func drainBoundaryEvents() -> [GaplessBoundaryEvent]
}

/// Issues play-instance identities. Monotonic and never reused, so a stale event from a previous
/// play of the same slot can always be told apart from the current one.
@MainActor
final class GaplessPlayInstanceAllocator {
    private var next: UInt64 = 1

    func allocate() -> GaplessPlayInstanceID {
        defer { next += 1 }
        return GaplessPlayInstanceID(rawValue: next)
    }
}
