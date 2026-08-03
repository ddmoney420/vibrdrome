import AVFoundation
import Foundation

/// The handle a completion callback carries back from the audio thread.
///
/// Deliberately a small value of plain scalars. The measured defect this whole substrate exists to
/// remove was an object the player node held for the life of the play session, so nothing that can
/// own memory — no buffer, no file, no decoder, no track, no scheduler — travels in the callback.
/// The token names a pool slot; the main actor looks up what it means.
struct GaplessRecycleToken: Sendable, Equatable {
    /// Index into the pool's fixed buffer array.
    let bufferIndex: Int
    /// Which chunk of its track this was.
    let chunkIndex: Int
    let playInstance: GaplessPlayInstanceID
    /// Tail this buffer was scheduled under, so audio from a discarded tail is recognisable.
    let tailGeneration: UInt64
}

/// Where completion callbacks deposit tokens, and the only object shared with the audio thread.
///
/// A lock rather than an actor: the callback runs on an AVFoundation-owned realtime-adjacent thread
/// that must not await, and `deposit` is a bounded append under an uncontended lock. `onDeposit`
/// hops to the main actor to do the actual work, so nothing beyond the append happens on that
/// thread.
final class GaplessRecycleInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [GaplessRecycleToken] = []
    private var depositCount = 0

    /// Signalled after each deposit so the scheduler can refill promptly rather than waiting for the
    /// next heartbeat. Recycling only — this must never be used to publish an audible boundary.
    var onDeposit: (@Sendable () -> Void)?

    func deposit(_ token: GaplessRecycleToken) {
        lock.lock()
        tokens.append(token)
        depositCount += 1
        lock.unlock()
        onDeposit?()
    }

    func drain() -> [GaplessRecycleToken] {
        lock.lock()
        defer { tokens.removeAll(keepingCapacity: true); lock.unlock() }
        return tokens
    }

    /// Tokens deposited but not yet drained.
    var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return tokens.count
    }

    /// Total deposits ever, for reconciling against the number of chunks scheduled.
    var totalDeposits: Int {
        lock.lock(); defer { lock.unlock() }
        return depositCount
    }

    func reset() {
        lock.lock()
        tokens.removeAll()
        depositCount = 0
        lock.unlock()
    }
}

/// A fixed set of `AVAudioPCMBuffer` objects, reused for the life of the engine.
///
/// The point of the pool is that it is *fixed*. Every buffer is allocated once, at construction, and
/// the same objects are handed out and returned for the whole session, so PCM memory is a constant
/// that does not track tracks, transitions, or session length. `available + inFlight == capacity` is
/// an invariant, and a caller that loses a token starves the pool rather than silently growing it —
/// which is the failure mode worth having, because it is visible.
@MainActor
final class GaplessBufferPool {
    let capacity: Int
    let frameCapacity: AVAudioFrameCount
    let format: AVAudioFormat

    private var buffers: [AVAudioPCMBuffer]
    private var availableIndices: [Int]
    private var inFlightIndices: Set<Int> = []

    /// Highest number of buffers ever simultaneously out of the pool.
    private(set) var peakInFlight = 0

    init(capacity: Int, frameCapacity: AVAudioFrameCount, format: AVAudioFormat) {
        self.capacity = capacity
        self.frameCapacity = frameCapacity
        self.format = format
        buffers = (0..<capacity).map { _ in
            // Force-unwrapped deliberately: a nil here means the format and frame capacity are
            // inconsistent, which is a programming error at construction, not a runtime condition.
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)!
        }
        availableIndices = Array((0..<capacity).reversed())
    }

    /// Total PCM bytes held. Constant for the life of the pool; reported so "bounded" is a number
    /// rather than a claim.
    var allocatedBytes: Int {
        capacity * Int(frameCapacity) * Int(format.channelCount) * MemoryLayout<Float>.size
    }

    var availableCount: Int { availableIndices.count }
    var inFlightCount: Int { inFlightIndices.count }

    /// Take a buffer. `nil` when every buffer is still with the player node — the caller must wait
    /// rather than allocate, because allocating on demand is precisely the unbounded behaviour being
    /// removed.
    func acquire() -> (index: Int, buffer: AVAudioPCMBuffer)? {
        guard let index = availableIndices.popLast() else { return nil }
        inFlightIndices.insert(index)
        peakInFlight = max(peakInFlight, inFlightIndices.count)
        let buffer = buffers[index]
        buffer.frameLength = 0
        return (index, buffer)
    }

    /// Return a buffer. Ignores a token for a buffer already back in the pool, so a duplicated
    /// callback cannot hand out the same buffer twice — that would let two chunks write the same
    /// memory, which is the one corruption this pool must not permit.
    @discardableResult
    func release(_ index: Int) -> Bool {
        guard inFlightIndices.remove(index) != nil else { return false }
        buffers[index].frameLength = 0
        availableIndices.append(index)
        return true
    }

    /// The buffer for a token, for tests that need to inspect what the node was given.
    func buffer(at index: Int) -> AVAudioPCMBuffer { buffers[index] }

    /// Return everything. Only valid once the player node has been stopped and can no longer read
    /// any of them.
    func reclaimAll() {
        for index in inFlightIndices { buffers[index].frameLength = 0 }
        inFlightIndices.removeAll()
        availableIndices = Array((0..<capacity).reversed())
    }
}
