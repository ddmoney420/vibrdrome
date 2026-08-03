import AVFoundation
import os.log

/// Persistent-output gapless engine (feat/persistent-gapless-engine).
///
/// ONE `AVAudioEngine` graph stays running across track boundaries:
///
///     AVAudioPlayerNode -> AVAudioUnitEQ -> engine.mainMixerNode -> output
///
/// Consecutive tracks are SCHEDULED into the running player node (`scheduleFile(at: nil)`), never a
/// new per-track output pipeline and never a per-item `MTAudioProcessingTap`. This is what makes the
/// transition frame-continuous — proven by `renderOfflineChannel0()` + `GaplessEngineOfflineTests`.
///
/// Vertical slice (Checkpoint 2): local-file gapless playback + frame accounting + the offline
/// frame-continuity proof. Streaming/prefetch, EQ toggle, the persistent visualizer tap, ReplayGain,
/// repeat modes, and queue operations land in later checkpoints. The existing AVQueuePlayer
/// `AudioEngine` remains the production path and fallback until this reaches parity.
final class PersistentGaplessEngine {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    /// Persistent EQ node — always in the graph, transparent when flat. EQ toggling never rebuilds
    /// the graph or recreates the player node (implemented in a later checkpoint).
    let eq = AVAudioUnitEQ(numberOfBands: 10)

    private(set) var scheduler = GaplessScheduler()
    let renderFormat: AVAudioFormat
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessEngine")

    /// - Parameter renderFormat: the single format the graph runs at for its lifetime. Sources in a
    ///   different format must be converted to this before scheduling (see `GaplessRenderFormat`).
    init(renderFormat: AVAudioFormat = GaplessRenderFormat.standard) {
        self.renderFormat = renderFormat
        engine.attach(player)
        engine.attach(eq)
        engine.connect(player, to: eq, format: renderFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: renderFormat)
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
    func renderOfflineChannel0(maxFrameSlice: AVAudioFrameCount = 4096) throws -> [Float] {
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
            let toRender = AVAudioFrameCount(min(Int64(buffer.frameCapacity), remaining))
            let status = try engine.renderOffline(toRender, to: buffer)
            guard status == .success else {
                log.error("offline render status \(status.rawValue) — stopping")
                break
            }
            if let channel = buffer.floatChannelData?[0] {
                for i in 0..<Int(buffer.frameLength) { out.append(channel[i]) }
            }
        }
        player.stop()
        engine.stop()
        return out
    }
}
