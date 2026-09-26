import AVFoundation
import Foundation
import os.lock
import Synchronization

/// The single, permanent PCM feed that both visualizers consume.
///
/// One tap is installed on the persistent `outputMixer` when the engine starts and removed only when
/// the engine is torn down. In the old playback path a visualizer opening or closing changed the
/// audio pipeline, which is how a UI action became an audio-path event — and how a visualizer could
/// disturb a track transition. Here, opening or closing a visualizer adds or removes a *consumer*.
/// The tap, the graph, and everything scheduled are untouched.
///
/// Placement is after the gain stage and the EQ, so the visualizers show what is actually heard
/// rather than the raw file.
///
/// **Render-thread contract.** The callback runs on a real-time thread, so it does exactly one kind
/// of work: copy samples into each active consumer's pre-allocated ring buffer. It never allocates,
/// never waits on a lock, never performs FFT or UI work, and never calls back into an actor. A
/// consumer that cannot keep up loses the oldest frames — the ring is bounded, so a stalled UI can
/// neither block audio nor grow memory without limit.
///
/// **Why one ring per consumer.** `FloatRingBuffer` is a single-producer/single-consumer structure.
/// Giving Classic and Native a ring each keeps that contract intact while there is still only one
/// producer and one tap, and lets a slow consumer drop frames without affecting the other.
final class GaplessVisualizerFeed: @unchecked Sendable {
    /// Frames requested per callback. Fixed and bounded so render-thread work is constant.
    static let bufferFrames: AVAudioFrameCount = 1_024
    /// Ring capacity per consumer — roughly 0.37 s at 44.1 kHz, enough to ride out a UI hitch and
    /// small enough that a stalled consumer cannot hoard memory.
    static let ringFrameCapacity = 16_384

    /// A registered visualizer. Holds its own bounded ring; the feed never allocates per callback.
    final class Consumer: @unchecked Sendable {
        let identifier: String
        let buffer: FloatRingBuffer
        /// When false the feed skips this consumer entirely, so a closed visualizer costs nothing
        /// downstream — without the tap or the graph changing in any way.
        private let activeFlag = Atomic<Bool>(false)

        var isActive: Bool {
            get { activeFlag.load(ordering: .acquiring) }
            set { activeFlag.store(newValue, ordering: .releasing) }
        }

        init(identifier: String, frameCapacity: Int, channelCount: Int) {
            self.identifier = identifier
            buffer = FloatRingBuffer(frameCapacity: frameCapacity, channelCount: channelCount)
        }
    }

    /// Render-thread statistics, for the performance measurements this checkpoint reports.
    struct Stats {
        let callbackCount: UInt64
        let framesDelivered: UInt64
        /// Callbacks that found the consumer list momentarily locked and returned rather than wait.
        let contendedCallbacks: UInt64
        let peakCallbackNanoseconds: UInt64
        let totalCallbackNanoseconds: UInt64

        var averageCallbackNanoseconds: UInt64 {
            callbackCount == 0 ? 0 : totalCallbackNanoseconds / callbackCount
        }
    }

    private(set) var isInstalled = false
    private weak var tappedNode: AVAudioNode?

    // Mutated only when a visualizer opens or closes; read on the render thread under `trylock`.
    private var consumers: [Consumer] = []
    private let consumersLock = OSAllocatedUnfairLock()

    private let callbackCount = Atomic<UInt64>(0)
    private let framesDelivered = Atomic<UInt64>(0)
    private let contendedCallbacks = Atomic<UInt64>(0)
    private let peakCallbackNanoseconds = Atomic<UInt64>(0)
    private let totalCallbackNanoseconds = Atomic<UInt64>(0)

    // MARK: - Tap lifetime

    /// Install the tap once, for the life of the engine. Repeat calls are ignored rather than
    /// reinstalling — a reinstall is exactly the per-track pipeline churn this design removes.
    func install(on node: AVAudioNode, format: AVAudioFormat) {
        guard !isInstalled else { return }
        tappedNode = node
        node.installTap(onBus: 0, bufferSize: Self.bufferFrames, format: format) { [weak self] buffer, _ in
            self?.deliver(buffer)
        }
        isInstalled = true
    }

    /// Remove the tap. Called only when the engine itself is torn down — never because a visualizer
    /// closed, and never at a track boundary.
    func uninstall() {
        guard isInstalled else { return }
        tappedNode?.removeTap(onBus: 0)
        tappedNode = nil
        isInstalled = false
    }

    // MARK: - Consumers

    /// Register a consumer and get its bounded ring. Does not touch the tap or the graph, so
    /// opening a visualizer mid-track is invisible to playback.
    @discardableResult
    func addConsumer(identifier: String, channelCount: Int = 2) -> Consumer {
        consumersLock.lock()
        defer { consumersLock.unlock() }
        if let existing = consumers.first(where: { $0.identifier == identifier }) { return existing }
        let consumer = Consumer(identifier: identifier, frameCapacity: Self.ringFrameCapacity,
                                channelCount: channelCount)
        consumers.append(consumer)
        return consumer
    }

    func removeConsumer(identifier: String) {
        consumersLock.lock()
        defer { consumersLock.unlock() }
        consumers.removeAll { $0.identifier == identifier }
    }

    func consumer(identifier: String) -> Consumer? {
        consumersLock.lock()
        defer { consumersLock.unlock() }
        return consumers.first { $0.identifier == identifier }
    }

    /// Whether any consumer currently wants data. Callers may use this to skip their own work, but
    /// must not use it to decide whether the tap should exist.
    var hasActiveConsumer: Bool {
        consumersLock.lock()
        defer { consumersLock.unlock() }
        return consumers.contains { $0.isActive }
    }

    var registeredConsumerCount: Int {
        consumersLock.lock()
        defer { consumersLock.unlock() }
        return consumers.count
    }

    // MARK: - Delivery (render thread)

    /// Copy one buffer to every active consumer. Real-time safe: no allocation, no waiting.
    func deliver(_ buffer: AVAudioPCMBuffer) {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            let elapsed = DispatchTime.now().uptimeNanoseconds - started
            callbackCount.wrappingAdd(1, ordering: .relaxed)
            totalCallbackNanoseconds.wrappingAdd(elapsed, ordering: .relaxed)
            // Monotonic max without a lock.
            var currentPeak = peakCallbackNanoseconds.load(ordering: .relaxed)
            while elapsed > currentPeak {
                let (exchanged, original) = peakCallbackNanoseconds.compareExchange(
                    expected: currentPeak, desired: elapsed, ordering: .relaxed)
                if exchanged { break }
                currentPeak = original
            }
        }

        // Never wait: if a visualizer is being added or removed at this instant, drop this buffer
        // rather than block the render thread. Registration is rare, so this is vanishingly uncommon
        // and costs at most one frame of visualisation.
        guard consumersLock.lockIfAvailable() else {
            contendedCallbacks.wrappingAdd(1, ordering: .relaxed)
            return
        }
        defer { consumersLock.unlock() }

        let frames = Int(buffer.frameLength)
        guard frames > 0, let channels = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)

        // A mono source feeds the same channel to both sides — the ring is stereo-interleaved, and
        // duplicating is cheaper than branching per consumer downstream.
        let left = channels[0]
        let right = channelCount >= 2 ? channels[1] : channels[0]
        for consumer in consumers where consumer.isActive {
            consumer.buffer.writePlanarStereo(left: left, right: right, frameCount: frames)
        }
        framesDelivered.wrappingAdd(UInt64(frames), ordering: .relaxed)
    }

    // MARK: - Diagnostics

    var stats: Stats {
        Stats(callbackCount: callbackCount.load(ordering: .relaxed),
              framesDelivered: framesDelivered.load(ordering: .relaxed),
              contendedCallbacks: contendedCallbacks.load(ordering: .relaxed),
              peakCallbackNanoseconds: peakCallbackNanoseconds.load(ordering: .relaxed),
              totalCallbackNanoseconds: totalCallbackNanoseconds.load(ordering: .relaxed))
    }

    func resetStats() {
        callbackCount.store(0, ordering: .relaxed)
        framesDelivered.store(0, ordering: .relaxed)
        contendedCallbacks.store(0, ordering: .relaxed)
        peakCallbackNanoseconds.store(0, ordering: .relaxed)
        totalCallbackNanoseconds.store(0, ordering: .relaxed)
    }
}
