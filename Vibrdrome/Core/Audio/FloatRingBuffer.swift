import Synchronization

/// Lock-free single-producer / single-consumer (SPSC) ring buffer of
/// interleaved Float32 audio frames. Used to hand real-time PCM from the audio
/// render thread to a non-real-time consumer (the future projectM render/debug
/// path). Phase 1A: the type exists and is unit-tested, but nothing in the app
/// feeds or drains it yet.
///
/// **Concurrency contract (SPSC):** exactly ONE producer thread calls the
/// `write*` methods and exactly ONE consumer thread calls `read(into:maxFrames:)`.
/// `head` is producer-owned, `tail` is consumer-owned; they are published with
/// release ordering and observed with acquire ordering, so the producer's sample
/// writes happen-before the consumer reads them — no locks required.
///
/// `@unchecked Sendable`: `storage` is accessed without a lock, but the producer
/// and consumer only ever touch disjoint slots (guaranteed by the head/tail
/// atomics under the SPSC contract above), so this is data-race free in practice.
final class FloatRingBuffer: @unchecked Sendable {

    /// Diagnostics snapshot (display-only; relaxed reads).
    struct Stats {
        let capacityFrames: Int
        let fillFrames: Int
        let channelCount: Int
        let producedFrames: UInt64
        let consumedFrames: UInt64
        let overflowFrames: UInt64
        let underrunReads: UInt64
    }

    /// Capacity in frames (a power of two; one frame = `channelCount` samples).
    let frameCapacity: Int
    /// Interleaved channels per frame (2 = stereo).
    let channelCount: Int

    private let mask: UInt64
    private let storage: UnsafeMutablePointer<Float>

    // Monotonic frame counters; slot = index & mask. Only the producer mutates
    // `head`; only the consumer mutates `tail`.
    private let head = Atomic<UInt64>(0)
    private let tail = Atomic<UInt64>(0)
    // Display-only counters (relaxed).
    private let overflowFrameCount = Atomic<UInt64>(0)
    private let underrunReadCount = Atomic<UInt64>(0)

    /// - Parameters:
    ///   - frameCapacity: requested capacity in frames; rounded up to a power of
    ///     two so wraparound is a bitmask. Must be >= 2.
    ///   - channelCount: interleaved channels per frame (default 2). Must be >= 1.
    init(frameCapacity: Int = 16384, channelCount: Int = 2) {
        precondition(frameCapacity >= 2, "FloatRingBuffer: frameCapacity must be >= 2")
        precondition(channelCount >= 1, "FloatRingBuffer: channelCount must be >= 1")
        let capacity = FloatRingBuffer.roundUpToPowerOfTwo(frameCapacity)
        self.frameCapacity = capacity
        self.channelCount = channelCount
        self.mask = UInt64(capacity - 1)
        let sampleCount = capacity * channelCount
        storage = UnsafeMutablePointer<Float>.allocate(capacity: sampleCount)
        storage.initialize(repeating: 0, count: sampleCount)
    }

    deinit {
        storage.deinitialize(count: frameCapacity * channelCount)
        storage.deallocate()
    }

    // MARK: - Producer (real-time safe: no allocation, no locks, no logging)

    /// Append `frameCount` interleaved frames from `src` (length
    /// `frameCount * channelCount`). Drop-oldest on overflow.
    func writeInterleaved(_ src: UnsafePointer<Float>, frameCount: Int) {
        guard frameCount > 0 else { return }
        let cc = channelCount
        let writeHead = head.load(ordering: .relaxed)
        let readTail = tail.load(ordering: .acquiring)
        accountOverflow(used: writeHead &- readTail, requested: frameCount)
        // A single write larger than capacity can only retain its last `cap`
        // frames; skip the earlier ones rather than wrap over ourselves.
        var count = frameCount
        var srcFrameOffset = 0
        if count > frameCapacity {
            srcFrameOffset = count - frameCapacity
            count = frameCapacity
        }
        var i = 0
        while i < count {
            let slot = Int((writeHead &+ UInt64(i)) & mask) * cc
            let srcBase = (srcFrameOffset + i) * cc
            var c = 0
            while c < cc {
                storage[slot + c] = src[srcBase + c]
                c += 1
            }
            i += 1
        }
        head.store(writeHead &+ UInt64(count), ordering: .releasing)
    }

    /// Append `frameCount` frames from two planar channels, interleaving directly
    /// into storage with no temporary buffer. Requires `channelCount == 2`; pass
    /// `left == right` for a mono source. Drop-oldest on overflow.
    func writePlanarStereo(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frameCount: Int) {
        precondition(channelCount == 2, "writePlanarStereo requires channelCount == 2")
        guard frameCount > 0 else { return }
        let writeHead = head.load(ordering: .relaxed)
        let readTail = tail.load(ordering: .acquiring)
        accountOverflow(used: writeHead &- readTail, requested: frameCount)
        var count = frameCount
        var srcFrameOffset = 0
        if count > frameCapacity {
            srcFrameOffset = count - frameCapacity
            count = frameCapacity
        }
        var i = 0
        while i < count {
            let slot = Int((writeHead &+ UInt64(i)) & mask) * 2
            storage[slot] = left[srcFrameOffset + i]
            storage[slot + 1] = right[srcFrameOffset + i]
            i += 1
        }
        head.store(writeHead &+ UInt64(count), ordering: .releasing)
    }

    private func accountOverflow(used: UInt64, requested: Int) {
        let free = used >= UInt64(frameCapacity) ? 0 : UInt64(frameCapacity) - used
        if UInt64(requested) > free {
            overflowFrameCount.wrappingAdd(UInt64(requested) - free, ordering: .relaxed)
        }
    }

    // MARK: - Consumer

    /// Drain up to `maxFrames` interleaved frames into `dst` (capacity
    /// `maxFrames * channelCount`). Returns the number of frames written. A
    /// partial read increments `underrunReads`. If the producer has lapped the
    /// consumer, the oldest over-capacity frames are skipped (drop-oldest).
    func read(into dst: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        guard maxFrames > 0 else { return 0 }
        let cc = channelCount
        var readTail = tail.load(ordering: .relaxed)
        let writeHead = head.load(ordering: .acquiring)
        var available = writeHead &- readTail
        if available > UInt64(frameCapacity) {
            readTail = writeHead &- UInt64(frameCapacity)
            available = UInt64(frameCapacity)
        }
        let toRead = min(Int(available), maxFrames)
        if toRead < maxFrames {
            underrunReadCount.wrappingAdd(1, ordering: .relaxed)
        }
        guard toRead > 0 else { return 0 }
        var i = 0
        while i < toRead {
            let slot = Int((readTail &+ UInt64(i)) & mask) * cc
            let dstBase = i * cc
            var c = 0
            while c < cc {
                dst[dstBase + c] = storage[slot + c]
                c += 1
            }
            i += 1
        }
        tail.store(readTail &+ UInt64(toRead), ordering: .releasing)
        return toRead
    }

    // MARK: - Control (NOT real-time safe)

    /// Empty the buffer and clear counters. **Not real-time safe** — call only
    /// when the producer and consumer are quiesced (no tap feeding and no
    /// consumer draining), e.g. when playback stops or the visualizer closes.
    /// The relaxed stores here are only data-race free in the absence of any
    /// concurrent `write*`/`read` call.
    func reset() {
        head.store(0, ordering: .relaxed)
        tail.store(0, ordering: .relaxed)
        overflowFrameCount.store(0, ordering: .relaxed)
        underrunReadCount.store(0, ordering: .relaxed)
    }

    // MARK: - Diagnostics

    var stats: Stats {
        let writeHead = head.load(ordering: .relaxed)
        let readTail = tail.load(ordering: .relaxed)
        let used = writeHead >= readTail ? writeHead &- readTail : 0
        return Stats(
            capacityFrames: frameCapacity,
            fillFrames: Int(min(used, UInt64(frameCapacity))),
            channelCount: channelCount,
            producedFrames: writeHead,
            consumedFrames: readTail,
            overflowFrames: overflowFrameCount.load(ordering: .relaxed),
            underrunReads: underrunReadCount.load(ordering: .relaxed)
        )
    }

    private static func roundUpToPowerOfTwo(_ value: Int) -> Int {
        var result = 1
        while result < value {
            result <<= 1
        }
        return result
    }
}
