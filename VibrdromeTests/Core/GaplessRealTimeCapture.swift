import AVFoundation
import Foundation
@testable import Vibrdrome

/// Captures and identifies what the engine **actually played** in real time.
///
/// Real-time tests can otherwise only assert on internal state, which proves the bookkeeping agrees
/// with itself and nothing about the audio. This taps the engine's output, records it, and
/// identifies each region by tone frequency — so a claim like "1 → X → 2" is backed by the sound
/// that came out, not by the order the segments were scheduled in.
///
/// The tap goes on `mainMixerNode`, deliberately not on `outputMixer`, so it cannot collide with the
/// visualizer feed's tap (a bus accepts only one) and the two can be exercised together.
///
/// **This type must NOT be `@MainActor`.** A tap closure written inside a main-actor-isolated context
/// inherits that isolation, and the tap fires on `RealtimeMessenger.mServiceQueue` — so the Swift 6
/// runtime asserts the executor and traps (`_dispatch_assert_queue_fail` via
/// `swift_task_isCurrentExecutor`). It crashes the whole test host, with no exception message and no
/// obvious link to isolation. The same rule applies to `GaplessVisualizerFeed`, which is likewise
/// non-isolated and shares only `Sendable` state with its callback.
final class GaplessRealTimeCapture: @unchecked Sendable {
    private let engine: PersistentGaplessEngine
    private let storage = SampleStore()
    private(set) var isCapturing = false

    /// Unbounded on purpose — a test capture is short and must not drop the evidence it exists to
    /// collect. Production paths use the bounded visualizer feed instead.
    private final class SampleStore: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [Float] = []
        private var rate: Double = 0
        func append(_ buffer: UnsafePointer<Float>, count: Int, sampleRate: Double) {
            lock.lock(); defer { lock.unlock() }
            if rate == 0 { rate = sampleRate }
            samples.append(contentsOf: UnsafeBufferPointer(start: buffer, count: count))
        }
        /// Rate of the buffers that actually arrived. Read from the tap rather than from the format
        /// requested at install time: the mixer's output format follows the hardware once the engine
        /// starts, so a capture installed before `start()` can receive a different rate than it asked
        /// for. Analysis that assumed otherwise stretched every span it measured.
        var observedRate: Double {
            lock.lock(); defer { lock.unlock() }
            return rate
        }
        var snapshot: [Float] {
            lock.lock(); defer { lock.unlock() }
            return samples
        }
        func reset() {
            lock.lock(); defer { lock.unlock() }
            samples.removeAll()
            rate = 0
        }
    }

    init(engine: PersistentGaplessEngine) {
        self.engine = engine
    }

    func start() {
        guard !isCapturing else { return }
        let node = engine.engine.mainMixerNode
        let format = node.outputFormat(forBus: 0)
        // Captures only `storage`, which is Sendable and does its own locking — no actor isolation
        // travels into the audio callback.
        node.installTap(onBus: 0, bufferSize: 1_024, format: format) { [storage] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            storage.append(channel, count: Int(buffer.frameLength),
                           sampleRate: buffer.format.sampleRate)
        }
        isCapturing = true
    }

    func stop() {
        guard isCapturing else { return }
        engine.engine.mainMixerNode.removeTap(onBus: 0)
        isCapturing = false
    }

    var samples: [Float] { storage.snapshot }
    /// Sample rate of the captured audio, measured from the delivered buffers. Zero until the first
    /// buffer arrives.
    var observedSampleRate: Double { storage.observedRate }
    var frameCount: Int { storage.snapshot.count }
    func reset() { storage.reset() }

    // MARK: - Analysis

    /// Energy of `frequency` in a window, via the Goertzel algorithm. Cheap and exact enough to tell
    /// a handful of well-separated tones apart.
    static func energy(_ samples: ArraySlice<Float>, frequency: Double, sampleRate: Double) -> Double {
        guard samples.count > 16 else { return 0 }
        let omega = 2.0 * .pi * frequency / sampleRate
        let coefficient = 2.0 * cos(omega)
        var s1 = 0.0, s2 = 0.0
        for sample in samples {
            let s0 = Double(sample) + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }
        return s1 * s1 + s2 * s2 - coefficient * s1 * s2
    }

    /// Which of `frequencies` dominates a window, or nil when the window is effectively silent.
    static func dominantFrequency(_ samples: ArraySlice<Float>, frequencies: [Double],
                                  sampleRate: Double, silenceThreshold: Float = 0.01) -> Double? {
        var peak: Float = 0
        for sample in samples { peak = max(peak, abs(sample)) }
        guard peak > silenceThreshold else { return nil }
        var best: Double?
        var bestEnergy = 0.0
        for frequency in frequencies {
            let value = energy(samples, frequency: frequency, sampleRate: sampleRate)
            if value > bestEnergy { bestEnergy = value; best = frequency }
        }
        return best
    }

    /// The sequence of tones actually heard, collapsing consecutive identical windows.
    ///
    /// Silence is skipped rather than recorded, because a short gap at a manual transition is
    /// expected; use `silenceRuns` to measure those separately.
    func heardSequence(frequencies: [Double], sampleRate: Double,
                       windowFrames: Int = 2_048) -> [Double] {
        let captured = samples
        var result: [Double] = []
        var index = 0
        while index + windowFrames <= captured.count {
            let window = captured[index..<(index + windowFrames)]
            if let dominant = Self.dominantFrequency(window, frequencies: frequencies,
                                                     sampleRate: sampleRate) {
                if result.last != dominant { result.append(dominant) }
            }
            index += windowFrames
        }
        return result
    }

    /// Runs of near-silence, in frames, ignoring leading silence before playback begins.
    /// Used to measure the audible interruption of a manual transition.
    func silenceRuns(threshold: Float = 0.01, windowFrames: Int = 512) -> [Int] {
        let captured = samples
        var runs: [Int] = []
        var current = 0
        var seenAudio = false
        var index = 0
        while index + windowFrames <= captured.count {
            var peak: Float = 0
            for sample in captured[index..<(index + windowFrames)] { peak = max(peak, abs(sample)) }
            if peak <= threshold {
                if seenAudio { current += windowFrames }
            } else {
                seenAudio = true
                if current > 0 { runs.append(current); current = 0 }
            }
            index += windowFrames
        }
        return runs
    }

    /// Longest silent run in seconds — the headline "how long was the gap" number.
    func longestSilenceSeconds(sampleRate: Double, threshold: Float = 0.01) -> TimeInterval {
        let longest = silenceRuns(threshold: threshold).max() ?? 0
        return Double(longest) / sampleRate
    }
}
