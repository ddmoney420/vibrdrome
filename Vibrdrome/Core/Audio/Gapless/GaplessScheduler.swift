import AVFoundation

/// Pure frame-accounting model for the persistent gapless engine (feat/persistent-gapless-engine).
///
/// Knows the exact render-frame range each queue item occupies in the engine timeline, so metadata,
/// scrobble, and Now Playing flip at the REAL audible boundary — the frame actually rendered to the
/// output — rather than when the player node merely finished consuming a file's data. Deliberately
/// has no `AVAudioEngine` dependency so the boundary logic is unit-testable in isolation.
struct GaplessScheduler {
    /// One scheduled queue item, mapped to a contiguous, non-overlapping render-frame range.
    struct Segment: Equatable {
        let id: String
        /// Frames this segment contributes to the engine render timeline (converted frames if the
        /// source was sample-rate converted; equals source frames when no SR conversion occurred).
        let renderFrames: AVAudioFramePosition
        /// First render frame at which this segment is audible.
        let startFrame: AVAudioFramePosition
        /// One past the last render frame of this segment (== next segment's startFrame).
        var endFrame: AVAudioFramePosition { startFrame + renderFrames }
    }

    private(set) var segments: [Segment] = []

    /// Append a segment consecutively after the current tail — exact hand-off, no overlap, no gap.
    /// Returns the appended segment so the caller can schedule the matching audio at `startFrame`.
    @discardableResult
    mutating func append(id: String, renderFrames: AVAudioFramePosition) -> Segment {
        let start = segments.last?.endFrame ?? 0
        let segment = Segment(id: id, renderFrames: renderFrames, startFrame: start)
        segments.append(segment)
        return segment
    }

    /// The segment audible at a given engine render sample-time (nil before the first / after the
    /// last). This is the source of truth for switching Now Playing metadata at the audible boundary.
    func segment(atRenderFrame frame: AVAudioFramePosition) -> Segment? {
        segments.first { frame >= $0.startFrame && frame < $0.endFrame }
    }

    /// Index of the segment audible at a render sample-time, for advancing queue/current-index state.
    func index(atRenderFrame frame: AVAudioFramePosition) -> Int? {
        segments.firstIndex { frame >= $0.startFrame && frame < $0.endFrame }
    }

    /// Total scheduled render frames across all segments (the offline render target length).
    var totalFrames: AVAudioFramePosition { segments.last?.endFrame ?? 0 }

    /// Drop everything from `id` onward (queue edit: a removed/replaced upcoming item and its
    /// successors are unscheduled). Returns the render frame from which re-scheduling must resume.
    @discardableResult
    mutating func truncate(fromID id: String) -> AVAudioFramePosition? {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return nil }
        let resumeFrame = segments[idx].startFrame
        segments.removeSubrange(idx...)
        return resumeFrame
    }
}
