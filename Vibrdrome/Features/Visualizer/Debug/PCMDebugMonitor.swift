#if DEBUG
import Foundation
import QuartzCore
import os

/// DEBUG-only diagnostics for the visualizer PCM pipeline (Phase 1D).
///
/// While shown, it force-enables `VisualizerPCMSource`, acts as the sole dev
/// **consumer** (drains the ring so the buffer doesn't perpetually overflow and
/// the consumed rate is real), and computes produced/consumed frame rates plus a
/// non-fatal over-production warning (produced > 1.5x the source sample rate —
/// which would indicate a crossfade double-feed). Not compiled into release.
///
/// The rate/warning math lives in `ingestSample(...)`, which is pure enough to
/// unit-test with synthetic inputs (no timer, ring, or playback required).
@MainActor
@Observable
final class PCMDebugMonitor {

    static let overProductionFactor = 1.5
    private static let rateInterval: CFTimeInterval = 0.5
    private static let scratchFrames = 4096

    private(set) var producedRate: Double = 0      // frames/sec
    private(set) var consumedRate: Double = 0       // frames/sec
    private(set) var fillFrames = 0
    private(set) var capacityFrames = 0
    private(set) var overflowFrames: UInt64 = 0
    private(set) var underrunReads: UInt64 = 0
    private(set) var sampleRate: Double = 0
    private(set) var channelCount = 2
    private(set) var overProductionWarning = false

    private var lastSample: (produced: UInt64, consumed: UInt64, time: CFTimeInterval)?
    private var lastRateTime: CFTimeInterval = 0
    private var owningActivation = false
    private var timer: Timer?
    private var scratch = [Float](repeating: 0, count: PCMDebugMonitor.scratchFrames * 2)
    private let source = VisualizerPCMSource.shared
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "PCMDebug")

    func start() {
        // If a visualizer renderer is already the consumer, observe only — do NOT
        // activate or drain (single-consumer SPSC). Otherwise own activation (1D).
        owningActivation = !source.hasActiveConsumer
        if owningActivation { source.setActiveForTesting(true) }
        lastSample = nil
        lastRateTime = 0
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        // Only deactivate/reset if we owned activation and no renderer took over.
        if owningActivation && !source.hasActiveConsumer {
            source.setActiveForTesting(false)
            source.reset()
        }
        owningActivation = false
        producedRate = 0
        consumedRate = 0
        overProductionWarning = false
        lastSample = nil
    }

    private func tick() {
        // Drain ONLY when we own the ring. When a renderer is the consumer it
        // drains; we just read stats (no second reader on the SPSC ring).
        if owningActivation && !source.hasActiveConsumer {
            scratch.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                while source.read(into: base, maxFrames: Self.scratchFrames) == Self.scratchFrames {}
            }
        }
        let now = CACurrentMediaTime()
        guard now - lastRateTime >= Self.rateInterval else { return }
        lastRateTime = now
        let stats = source.stats
        fillFrames = stats.fillFrames
        capacityFrames = stats.capacityFrames
        overflowFrames = stats.overflowFrames
        underrunReads = stats.underrunReads
        channelCount = stats.channelCount
        ingestSample(produced: stats.producedFrames, consumed: stats.consumedFrames,
                     sampleRate: source.sampleRate, at: now)
    }

    /// Core rate + warning math. Computes frames/sec from the delta since the
    /// previous sample. The over-production warning is edge-triggered: logged
    /// once on the normal -> warning transition (no per-tick log spam).
    func ingestSample(produced: UInt64, consumed: UInt64, sampleRate: Double, at now: CFTimeInterval) {
        self.sampleRate = sampleRate
        defer { lastSample = (produced, consumed, now) }
        guard let last = lastSample, now > last.time else { return }
        let dt = now - last.time
        producedRate = Double(produced &- last.produced) / dt
        consumedRate = Double(consumed &- last.consumed) / dt
        let warn = sampleRate > 0 && producedRate > Self.overProductionFactor * sampleRate
        if warn && !overProductionWarning {
            log.warning("PCM over-production: produced \(Int(self.producedRate)) fps > 1.5x sample rate \(Int(sampleRate)) Hz")
        }
        overProductionWarning = warn
    }
}
#endif
