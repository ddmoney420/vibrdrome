import Synchronization

/// App-facing entry point for the projectM visualizer's PCM feed. A single
/// shared instance owns one interleaved-stereo `FloatRingBuffer`.
///
/// Phase 1A establishes only the type, capacity, and API. Nothing feeds or
/// drains it yet:
/// - the EQ-tap producer is wired in Phase 1B (and gated by an `isActive` flag
///   added there);
/// - the projectM render consumer arrives in Phase 2.
///
/// See `FloatRingBuffer` for the SPSC real-time-safety contract. Mirrors the
/// existing `AudioSpectrum.shared` pattern.
final class VisualizerPCMSource: @unchecked Sendable {

    static let shared = VisualizerPCMSource()

    /// Default ring capacity in frames (~341 ms @ 48 kHz stereo).
    static let defaultFrameCapacity = 16384

    private let ring: FloatRingBuffer
    private let sampleRateBits = Atomic<UInt64>(0)
    private let channelCountStore = Atomic<Int>(2)
    private let isActive = Atomic<Bool>(false)
    private let consumerAttached = Atomic<Bool>(false)

    init(frameCapacity: Int = VisualizerPCMSource.defaultFrameCapacity) {
        ring = FloatRingBuffer(frameCapacity: frameCapacity, channelCount: 2)
    }

    /// Whether the EQ tap should feed PCM into the ring. Defaults to `false`, so
    /// the tap's write is a no-op (one relaxed atomic load + an untaken branch)
    /// until the projectM visualizer turns it on (Phase 2). Real-time safe to
    /// read from the audio callback.
    ///
    /// In Phase 1B nothing in shipping code sets this; it stays `false`. Tests /
    /// dev verification flip it via `setActiveForTesting(_:)`.
    var active: Bool {
        isActive.load(ordering: .relaxed)
    }

    #if DEBUG
    /// DEBUG/test-only: force the active flag (no UI, no shipping caller). Used to
    /// prove the tap write path fills the ring during Phase 1B verification.
    func setActiveForTesting(_ value: Bool) {
        isActive.store(value, ordering: .relaxed)
    }
    #endif

    /// Native sample rate of the source feeding the buffer. Set during the tap's
    /// `prepare` (Phase 1B), before the producer starts; read by the consumer.
    var sampleRate: Double {
        get { Double(bitPattern: sampleRateBits.load(ordering: .relaxed)) }
        set { sampleRateBits.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// Channel count of the original source (1 = mono, 2 = stereo, …).
    var sourceChannelCount: Int {
        get { channelCountStore.load(ordering: .relaxed) }
        set { channelCountStore.store(newValue, ordering: .relaxed) }
    }

    // MARK: - Render consumer lifecycle (shipping; Phase 2B)

    /// True while a projectM renderer is the live consumer. The DEBUG PCM overlay
    /// reads this to stay stats-only — it must not drain the SPSC ring while the
    /// renderer drains it.
    var hasActiveConsumer: Bool {
        consumerAttached.load(ordering: .relaxed)
    }

    /// The projectM renderer became the consumer: turn on the EQ-tap PCM write and
    /// mark the ring owned. Called on the main thread when the renderer appears.
    func beginRenderConsumer() {
        consumerAttached.store(true, ordering: .relaxed)
        isActive.store(true, ordering: .relaxed)
    }

    /// The renderer stopped: turn the tap write off and release ownership.
    /// Deliberately does NOT call `reset()` — the producer (audio tap) may still be
    /// running, and `reset()` is not producer-quiesce-safe. Clearing `isActive`
    /// makes the tap's next callback a no-op; any leftover ring data is harmless
    /// (the next consumer drains it on its first frame, and projectM keeps only the
    /// most recent samples from its rolling window).
    func endRenderConsumer() {
        isActive.store(false, ordering: .relaxed)
        consumerAttached.store(false, ordering: .relaxed)
    }

    // MARK: - Producer (real-time safe) — wired to the EQ tap in Phase 1B

    /// Feed interleaved stereo frames (length `frameCount * 2`).
    func ingestStereo(_ interleaved: UnsafePointer<Float>, frameCount: Int) {
        ring.writeInterleaved(interleaved, frameCount: frameCount)
    }

    /// Feed two planar channels, interleaving without allocation.
    func ingestPlanarStereo(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frameCount: Int) {
        ring.writePlanarStereo(left: left, right: right, frameCount: frameCount)
    }

    /// Feed a mono source, duplicated to both output channels.
    func ingestMono(_ src: UnsafePointer<Float>, frameCount: Int) {
        ring.writePlanarStereo(left: src, right: src, frameCount: frameCount)
    }

    // MARK: - Consumer — wired to the projectM render path in Phase 2

    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        ring.read(into: dst, maxFrames: maxFrames)
    }

    // MARK: - Control / diagnostics

    /// Empty the buffer and counters. **Not real-time safe** — call only when the
    /// producer and consumer are quiesced (see `FloatRingBuffer.reset()`).
    func reset() {
        ring.reset()
    }

    var stats: FloatRingBuffer.Stats {
        ring.stats
    }
}
