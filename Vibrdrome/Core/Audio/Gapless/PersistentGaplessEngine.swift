import AVFoundation
import os.log

/// Persistent-output gapless engine (feat/persistent-gapless-engine).
///
/// ONE `AVAudioEngine` graph stays running across track boundaries:
///
///     AVAudioPlayerNode -> gain stage -> AVAudioUnitEQ -> output mixer -> mainMixerNode -> output
///
/// Consecutive tracks are SCHEDULED into the running player node (`scheduleSegment(at: nil)`), never
/// a new per-track output pipeline and never a per-item `MTAudioProcessingTap`. This is what makes
/// the transition frame-continuous — proven by `renderOfflineChannel0()` + the offline tests.
///
/// Every stage is built once and never rebuilt. A track boundary is not an EQ event, not a gain
/// event, and not a tap event — nothing is attached, detached, reset, or reconnected, so filter
/// state and the hardware output stream both carry straight across the join.
///
/// - `gainStage` — per-track gain (ReplayGain) applied at the rendered boundary with a short ramp.
/// - `eqStage` — the 10-band EQ, transparent when the user has EQ off.
/// - `outputMixer` — the single, permanent tap point for both visualizers. Installed once; opening
///   or closing a visualizer changes consumers, never the tap or the graph.
///
/// The existing AVQueuePlayer `AudioEngine` remains the production path and fallback until this
/// reaches parity.
final class PersistentGaplessEngine {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    /// Persistent per-track gain, ahead of the EQ so ReplayGain is equalised like the rest of the
    /// signal rather than applied to an already-boosted one.
    let gainStage = GaplessGainStage()
    /// Persistent EQ — see `GaplessEQStage` for how existing EQ settings map onto it.
    let eqStage = GaplessEQStage()
    /// Permanent tap point for the visualizers, after gain and EQ so they show what is heard.
    let outputMixer = AVAudioMixerNode()

    /// Convenience accessor for the EQ node itself.
    var eq: AVAudioUnitEQ { eqStage.node }

    private(set) var scheduler = GaplessScheduler()
    let renderFormat: AVAudioFormat
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessEngine")

    /// - Parameter renderFormat: the single format the graph runs at for its lifetime. Sources in a
    ///   different format must be converted to this before scheduling (see `GaplessRenderFormat`).
    init(renderFormat: AVAudioFormat = GaplessRenderFormat.standard) {
        self.renderFormat = renderFormat
        engine.attach(player)
        engine.attach(gainStage.node)
        engine.attach(eq)
        engine.attach(outputMixer)
        engine.connect(player, to: gainStage.node, format: renderFormat)
        engine.connect(gainStage.node, to: eq, format: renderFormat)
        engine.connect(eq, to: outputMixer, format: renderFormat)
        engine.connect(outputMixer, to: engine.mainMixerNode, format: renderFormat)
    }

    // MARK: - EQ

    /// Set EQ settings immediately, with no ramp — for initial state, before audio is flowing.
    /// Never stops the engine, never touches the player node, and never affects what is scheduled,
    /// so EQ state and gapless scheduling stay completely independent.
    func applyEQ(_ settings: GaplessEQSettings) {
        eqStage.apply(settings)
    }

    /// Change EQ settings during playback, ramped so the change cannot click.
    func transitionEQ(to settings: GaplessEQSettings) {
        eqStage.beginTransition(to: settings, sampleRate: renderFormat.sampleRate)
    }

    /// Turn EQ on or off mid-playback. Bypass is a true transparent path, not flat bands.
    func setEQEnabled(_ enabled: Bool) {
        eqStage.setEnabled(enabled, sampleRate: renderFormat.sampleRate)
    }

    /// Change one band mid-playback — the hot path while a user drags a slider.
    func setEQGain(_ gain: Float, forBand index: Int) {
        eqStage.setGain(gain, forBand: index, sampleRate: renderFormat.sampleRate)
    }

    /// Schedule local files consecutively into the running player node and record their exact
    /// render-frame ranges.
    ///
    /// Each file is described through the same `GaplessTrackPreparer` path used in production, so
    /// codec-specific trimming (notably MP3 encoder delay + padding) applies here too rather than
    /// only on the streaming path.
    func schedule(urls: [URL]) throws {
        let tracks = try urls.map {
            try GaplessTrackPreparer.describe(trackID: $0.lastPathComponent, fileURL: $0,
                                              renderSampleRate: renderFormat.sampleRate)
        }
        try schedule(tracks: tracks)
    }

    /// Schedule prepared tracks consecutively into the running player node.
    ///
    /// This is the boundary-critical call, and it does no I/O beyond opening an already-local file:
    /// resolving, fetching, and decoding all happened during preparation. Each track is scheduled as
    /// an explicit *segment* rather than a whole file so codec priming/padding is excluded.
    ///
    /// - Note: `completionCallbackType: .dataRendered` fires when the segment's audio has actually
    ///   been rendered to the output — the correct signal for flipping metadata at the audible
    ///   boundary, rather than `.dataConsumed` which fires early when the node merely buffered it.
    func schedule(tracks: [GaplessPreparedTrack]) throws {
        for track in tracks {
            let file = try AVAudioFile(forReading: track.fileURL)
            let segment = scheduler.append(id: track.trackID, renderFrames: track.renderFrames)
            let label = "\(track.trackID) [\(segment.startFrame)..<\(segment.endFrame)]"
            let trimNote = track.trim.reason.rawValue
            // Capture only Sendable values (not self) so the @Sendable render-thread callback stays
            // concurrency-clean. Real-time metadata advance is driven off the frame-accounting
            // scheduler on the main actor in a later checkpoint, not from this callback.
            let renderLog = log
            player.scheduleSegment(file, startingFrame: track.trim.startFrame,
                                   frameCount: track.trim.frameCount, at: nil,
                                   completionCallbackType: .dataRendered) { _ in
                renderLog.debug("segment rendered to output: \(label, privacy: .public) (\(trimNote, privacy: .public))")
            }
        }
    }

    /// Offline-render the entire current schedule and return channel-0 samples. Deterministic
    /// `AVAudioEngine` manual rendering — the objective frame-continuity gate that replaces by-ear
    /// diagnostic loops. Not used on the real-time playback path.
    ///
    /// - Parameter changes: actions applied at exact output frame positions while rendering, so
    ///   runtime behaviour (enabling EQ mid-track, moving a band just before a boundary) can be
    ///   measured rather than assumed. Render slices are shortened so each change lands on its
    ///   requested frame instead of the next slice edge.
    func renderOfflineChannel0(
        maxFrameSlice: AVAudioFrameCount = 4096,
        applying changes: [(frame: Int, action: (PersistentGaplessEngine) -> Void)]
    ) throws -> [Float] {
        var pending = changes.sorted { $0.frame < $1.frame }
        return try renderOfflineChannel0(maxFrameSlice: maxFrameSlice) { renderedFrames in
            while let next = pending.first, renderedFrames >= next.frame {
                next.action(self)
                pending.removeFirst()
            }
            return pending.first.map { $0.frame - renderedFrames }
        }
    }

    /// Offline render with an optional per-slice hook.
    ///
    /// - Parameter beforeSlice: called with the number of frames rendered so far; returns the
    ///   maximum number of frames the next slice may cover (nil = no limit).
    func renderOfflineChannel0(maxFrameSlice: AVAudioFrameCount = 4096,
                               beforeSlice: ((Int) -> Int?)? = nil) throws -> [Float] {
        try engine.enableManualRenderingMode(.offline, format: renderFormat,
                                             maximumFrameCount: maxFrameSlice)
        try engine.start()
        player.play()

        let total = scheduler.totalFrames
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw NSError(domain: "GaplessEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "render buffer alloc failed"])
        }

        var out: [Float] = []
        out.reserveCapacity(Int(total) + Int(maxFrameSlice) * 2)
        while engine.manualRenderingSampleTime < total {
            let remaining = total - engine.manualRenderingSampleTime
            var slice = min(Int64(buffer.frameCapacity), remaining)
            // Shorten the slice so a scheduled change lands on its exact frame, never late.
            if let limit = beforeSlice?(out.count), limit > 0 {
                slice = min(slice, Int64(limit))
            }
            // Keep slices fine-grained while an EQ ramp is in flight, so each parameter step is
            // small enough to stay below the signal's own sample-to-sample movement.
            if let rampLimit = eqStage.rampSliceLimit {
                slice = min(slice, Int64(rampLimit))
            }
            let toRender = AVAudioFrameCount(max(1, slice))
            let status = try engine.renderOffline(toRender, to: buffer)
            guard status == .success else {
                log.error("offline render status \(status.rawValue) — stopping")
                break
            }
            if let channel = buffer.floatChannelData?[0] {
                for i in 0..<Int(buffer.frameLength) { out.append(channel[i]) }
            }
            // Advance the ramp in audio time — the only clock that is meaningful here, and the one
            // that makes offline measurement match real-time behaviour.
            eqStage.advanceRamp(byFrames: Int(buffer.frameLength))
        }
        player.stop()
        engine.stop()
        return out
    }
}
