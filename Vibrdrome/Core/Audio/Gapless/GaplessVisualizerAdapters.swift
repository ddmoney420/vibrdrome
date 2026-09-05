import AVFoundation
import Foundation

/// Connects the shared persistent feed to the app's two existing visualizers.
///
/// Both adapters drain their own ring buffer on a timer and hand samples to the existing consumer
/// unchanged — `AudioSpectrum` keeps its own FFT size, binning, smoothing and cadence, and
/// `VisualizerPCMSource` keeps its own ring and format expectations. Nothing about how either
/// visualizer looks or behaves is reimplemented here; this is purely a change of *where the samples
/// come from*.
///
/// Draining happens off the render thread deliberately. The feed's callback only copies into a
/// bounded ring; the FFT (which allocates) and every other per-frame computation happen here, on the
/// adapter's own cadence. That is what keeps a slow or stalled visualizer from ever touching audio.
///
/// When the persistent engine is active these adapters replace the old per-item
/// `MTAudioProcessingTap` as the source for both visualizers — the tap that was the proven cause of
/// the transition freeze. The old path stays in place for the AVQueuePlayer fallback engine.
@MainActor
protocol GaplessVisualizerAdapter: AnyObject {
    /// Identifier of this adapter's consumer in the feed.
    var consumerIdentifier: String { get }
    /// Start consuming — the visualizer opened.
    func activate()
    /// Stop consuming. Removes no tap and touches no node: the feed keeps running and this adapter
    /// simply stops doing downstream work.
    func deactivate()
    /// Drain whatever is available and push it to the underlying visualizer. Called on the
    /// adapter's cadence, never from the render thread.
    @discardableResult
    func drain() -> Int
    /// Drop everything buffered without touching the downstream visualizer's own state — used
    /// after a pause, where the feed kept delivering engine silence the consumer must not replay.
    /// Distinct from `deactivate()`, which also resets the visualizer and would blank it.
    func flush()
}

/// Feeds the Classic (FFT) visualizer from the shared feed.
@MainActor
final class GaplessClassicVisualizerAdapter: GaplessVisualizerAdapter {
    let consumerIdentifier = "classic"
    /// Frames pulled per drain. `AudioSpectrum` accumulates into its own FFT window, so this only
    /// needs to keep up with the feed, not match the FFT size.
    static let drainFrames = 4_096

    private let consumer: GaplessVisualizerFeed.Consumer
    private let spectrum: AudioSpectrum
    private let sampleRate: Float
    /// Pre-allocated interleaved scratch — the adapter allocates once, never per drain.
    private var scratch: [Float]
    /// Mono scratch, since the Classic FFT consumes a single channel.
    private var mono: [Float]

    init(feed: GaplessVisualizerFeed, spectrum: AudioSpectrum = .shared,
         sampleRate: Double = GaplessRenderFormat.sampleRate) {
        consumer = feed.addConsumer(identifier: "classic")
        self.spectrum = spectrum
        self.sampleRate = Float(sampleRate)
        scratch = [Float](repeating: 0, count: Self.drainFrames * 2)
        mono = [Float](repeating: 0, count: Self.drainFrames)
    }

    func activate() { consumer.isActive = true }

    func deactivate() {
        consumer.isActive = false
        // Drop anything buffered so reopening does not show audio from minutes ago.
        consumer.buffer.reset()
        spectrum.reset()
    }

    func flush() { consumer.buffer.reset() }

    @discardableResult
    func drain() -> Int {
        guard consumer.isActive else { return 0 }
        let frames = scratch.withUnsafeMutableBufferPointer { destination in
            consumer.buffer.read(into: destination.baseAddress!, maxFrames: Self.drainFrames)
        }
        guard frames > 0 else { return 0 }
        // Down-mix to mono for the FFT, matching what the old tap handed it.
        for i in 0..<frames { mono[i] = (scratch[i * 2] + scratch[i * 2 + 1]) * 0.5 }
        mono.withUnsafeBufferPointer { source in
            spectrum.processPCM(source.baseAddress!, count: frames, sampleRate: sampleRate)
        }
        return frames
    }
}

/// Feeds the Native (PCM) visualizer from the shared feed.
///
/// `VisualizerPCMSource` already owns a ring and a consumer-count gate, so this adapter simply moves
/// samples from the feed's ring into it, preserving its existing interleaved-stereo input contract.
@MainActor
final class GaplessNativeVisualizerAdapter: GaplessVisualizerAdapter {
    let consumerIdentifier = "native"
    static let drainFrames = 4_096

    private let consumer: GaplessVisualizerFeed.Consumer
    private let source: VisualizerPCMSource
    private var scratch: [Float]

    init(feed: GaplessVisualizerFeed, source: VisualizerPCMSource = .shared) {
        consumer = feed.addConsumer(identifier: "native")
        self.source = source
        scratch = [Float](repeating: 0, count: Self.drainFrames * 2)
    }

    func activate() {
        consumer.isActive = true
        source.beginRenderConsumer()
    }

    func deactivate() {
        consumer.isActive = false
        consumer.buffer.reset()
        source.endRenderConsumer()
    }

    func flush() { consumer.buffer.reset() }

    @discardableResult
    func drain() -> Int {
        guard consumer.isActive else { return 0 }
        let frames = scratch.withUnsafeMutableBufferPointer { destination in
            consumer.buffer.read(into: destination.baseAddress!, maxFrames: Self.drainFrames)
        }
        guard frames > 0 else { return 0 }
        scratch.withUnsafeBufferPointer { source in
            self.source.ingestStereo(source.baseAddress!, frameCount: frames)
        }
        return frames
    }
}
