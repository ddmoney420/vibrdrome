import AVFoundation
import MediaToolbox
import os.log

private let tapLog = Logger(subsystem: "com.vibrdrome.app", category: "EQTap")

// MARK: - Shared EQ Gains

/// Thread-safe storage for current EQ gain values.
/// Updated from the main thread when the user adjusts EQ; read on the audio render thread.
/// Each tap computes its own biquad coefficients using the actual audio sample rate.
final class EQCoefficients: @unchecked Sendable {
    static let shared = EQCoefficients()

    private let lock = OSAllocatedUnfairLock()
    private var _gains: [Float] = Array(repeating: 0, count: 10)
    private var _frequencies: [Float] = EQPresets.frequencies

    /// Current gain values — read by taps to compute per-sample-rate coefficients
    var gains: [Float] {
        lock.withLock { _gains }
    }

    var frequencies: [Float] {
        lock.withLock { _frequencies }
    }

    func update(gains: [Float], frequencies: [Float]) {
        lock.withLock {
            _gains = gains
            _frequencies = frequencies
        }
    }
}

// MARK: - Biquad Filter Coefficients

/// Normalized biquad coefficients for one parametric EQ band.
/// Uses the Audio EQ Cookbook (Robert Bristow-Johnson) peaking EQ formula.
struct BiquadCoefficients: Sendable {
    var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float

    static let passthrough = BiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    var isPassthrough: Bool {
        b0 == 1 && b1 == 0 && b2 == 0 && a1 == 0 && a2 == 0
    }

    static func parametric(
        frequency: Float, gainDB: Float, bandwidth: Float, sampleRate: Float
    ) -> BiquadCoefficients {
        let A = powf(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / sampleRate
        let sinW0 = sinf(w0)
        let cosW0 = cosf(w0)
        let alpha = sinW0 * sinhf(logf(2) / 2 * bandwidth * w0 / sinW0)

        let a0 = 1 + alpha / A
        return BiquadCoefficients(
            b0: (1 + alpha * A) / a0,
            b1: (-2 * cosW0) / a0,
            b2: (1 - alpha * A) / a0,
            a1: (-2 * cosW0) / a0,
            a2: (1 - alpha / A) / a0
        )
    }
}

// MARK: - Audio Tap Processor

/// Applies 10-band parametric EQ to AVPlayer audio via MTAudioProcessingTap.
/// Attach the resulting AVAudioMix to an AVPlayerItem — works with both
/// streaming and local files since AVPlayer handles all buffering.
enum EQTapProcessor {

    /// Per-tap context holding delay state and sample-rate-specific coefficients.
    /// Each AVPlayerItem gets its own context; gains are read from the shared store.
    final class TapContext: @unchecked Sendable {
        static let bandCount = 10
        // Per-channel, per-band delay state: (x[n-1], x[n-2], y[n-1], y[n-2])
        var delays: [[(Float, Float, Float, Float)]] = []
        /// Actual sample rate from the audio processing format
        var sampleRate: Float = 44100
        /// Cached coefficients computed at this tap's sample rate
        var coefficients: [BiquadCoefficients] = Array(repeating: .passthrough, count: bandCount)
        /// Snapshot of gains used to compute cached coefficients (detect changes)
        var cachedGains: [Float] = []

        func prepare(channelCount: Int, sampleRate: Float) {
            self.sampleRate = sampleRate
            delays = (0..<channelCount).map { _ in
                (0..<TapContext.bandCount).map { _ in (Float(0), Float(0), Float(0), Float(0)) }
            }
        }

        /// Recompute coefficients if gains have changed since last check
        func updateCoefficientsIfNeeded(gains: [Float], frequencies: [Float]) {
            guard gains != cachedGains else { return }
            cachedGains = gains
            var newCoeffs = [BiquadCoefficients]()
            for i in 0..<min(gains.count, frequencies.count) {
                if abs(gains[i]) < 0.1 {
                    newCoeffs.append(.passthrough)
                } else {
                    newCoeffs.append(.parametric(
                        frequency: frequencies[i], gainDB: gains[i],
                        bandwidth: 1.0, sampleRate: sampleRate
                    ))
                }
            }
            coefficients = newCoeffs
        }
    }

    /// Create an AVAudioMix with a 10-band EQ tap for the given audio track.
    static func createAudioMix(track: AVAssetTrack) -> AVAudioMix? {
        let context = TapContext()

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(context).toOpaque(),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        #if swift(>=6.1)
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects, &tap
        )
        guard status == noErr, let tap else {
            tapLog.error("MTAudioProcessingTapCreate failed: \(status)")
            return nil
        }
        #else
        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects, &tap
        )
        guard status == noErr, let unwrappedTap = tap?.takeRetainedValue() else {
            tapLog.error("MTAudioProcessingTapCreate failed: \(status)")
            return nil
        }
        let tap = unwrappedTap
        #endif

        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap

        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        return mix
    }

    // MARK: - C Callbacks

    // swiftlint:disable closure_parameter_position
    private static let tapInit: MTAudioProcessingTapInitCallback = {
        _, clientInfo, tapStorageOut in
        tapStorageOut.pointee = clientInfo
    }

    private static let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
        Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
    }

    private static let tapPrepare: MTAudioProcessingTapPrepareCallback = {
        tap, _, processingFormat in
        let ctx = Unmanaged<TapContext>.fromOpaque(
            MTAudioProcessingTapGetStorage(tap)
        ).takeUnretainedValue()
        let format = processingFormat.pointee
        ctx.prepare(
            channelCount: Int(format.mChannelsPerFrame),
            sampleRate: Float(format.mSampleRate)
        )
    }

    private static let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in }

    private static let tapProcess: MTAudioProcessingTapProcessCallback = {
        tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
    // swiftlint:enable closure_parameter_position

        let status = MTAudioProcessingTapGetSourceAudio(
            tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut
        )
        guard status == noErr else { return }

        let ctx = Unmanaged<TapContext>.fromOpaque(
            MTAudioProcessingTapGetStorage(tap)
        ).takeUnretainedValue()

        // Read shared gains and recompute coefficients at this tap's sample rate if needed
        let gains = EQCoefficients.shared.gains
        let frequencies = EQCoefficients.shared.frequencies
        ctx.updateCoefficientsIfNeeded(gains: gains, frequencies: frequencies)

        let coeffs = ctx.coefficients
        guard !coeffs.isEmpty else { return }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)
        let frameCount = Int(numberFrames)

        // Tiny constant to flush denormalized floats (prevents CPU spikes on x86)
        let antiDenormal: Float = 1.0e-25

        for ch in 0..<bufferList.count where ch < ctx.delays.count {
            guard let data = bufferList[ch].mData else { continue }
            let buffer = data.assumingMemoryBound(to: Float.self)

            for band in 0..<min(coeffs.count, ctx.delays[ch].count) {
                let c = coeffs[band]
                if c.isPassthrough { continue }

                var (xn1, xn2, yn1, yn2) = ctx.delays[ch][band]

                for i in 0..<frameCount {
                    let x = buffer[i]
                    let y = c.b0 * x + c.b1 * xn1 + c.b2 * xn2
                        - c.a1 * yn1 - c.a2 * yn2 + antiDenormal
                    buffer[i] = y
                    xn2 = xn1; xn1 = x
                    yn2 = yn1; yn1 = y
                }

                ctx.delays[ch][band] = (xn1, xn2, yn1, yn2)
            }

            // Clamp output to prevent cascaded gain overflow
            for i in 0..<frameCount {
                buffer[i] = min(max(buffer[i], -1.0), 1.0)
            }
        }

        // Extract PCM for FFT spectrum analysis (first channel only)
        if !bufferList.isEmpty, let data = bufferList[0].mData {
            let samples = data.assumingMemoryBound(to: Float.self)
            let sampleRate = Unmanaged<TapContext>.fromOpaque(
                MTAudioProcessingTapGetStorage(tap)
            ).takeUnretainedValue().sampleRate
            AudioSpectrum.shared.processPCM(samples, count: frameCount, sampleRate: sampleRate)
        }
    }
}
