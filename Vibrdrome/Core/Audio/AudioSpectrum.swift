import Accelerate
import Foundation
import os.log

/// Thread-safe storage for real-time FFT spectrum data extracted from the audio tap.
/// Updated on the audio render thread, read by the visualizer on the main thread at 60fps.
final class AudioSpectrum: @unchecked Sendable {
    static let shared = AudioSpectrum()

    /// Number of FFT bins (must be power of 2)
    static let fftSize = 1024
    /// Number of output frequency bands for visualization
    static let bandCount = 32

    private let lock = OSAllocatedUnfairLock()

    // Smoothed frequency bands (0.0 - 1.0)
    private var _bass: Float = 0
    private var _mid: Float = 0
    private var _treble: Float = 0
    private var _energy: Float = 0
    private var _bands: [Float] = Array(repeating: 0, count: bandCount)

    // Sample accumulator — collects incoming tap samples until we have a
    // full FFT window. Audio taps can deliver variable buffer sizes; gating
    // on count >= fftSize silently drops all data when the buffer is smaller
    // and leaves the visualizer falling through to its simulated fallback.
    // Only ever touched from the audio render thread (single writer), so no
    // lock is required on the buffer itself.
    private var _accumBuffer: [Float] = Array(repeating: 0, count: fftSize)
    private var _accumFill: Int = 0

    // FFT setup (reusable, created once)
    private let fftSetup: FFTSetup?
    private let log2n: vDSP_Length

    private init() {
        log2n = vDSP_Length(log2(Float(Self.fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    // MARK: - Thread-Safe Accessors

    var bass: Float { lock.withLock { _bass } }
    var mid: Float { lock.withLock { _mid } }
    var treble: Float { lock.withLock { _treble } }
    var energy: Float { lock.withLock { _energy } }
    var bands: [Float] { lock.withLock { _bands } }

    /// Reset all values to zero (e.g. when playback stops)
    func reset() {
        lock.withLock {
            _bass = 0; _mid = 0; _treble = 0; _energy = 0
            _bands = Array(repeating: 0, count: Self.bandCount)
        }
        _accumFill = 0
    }

    // MARK: - FFT Processing (called from audio render thread)

    /// Process raw PCM samples and extract frequency data.
    /// Called from the MTAudioProcessingTap callback — must be fast and lock-free where possible.
    /// Accepts any buffer size; accumulates samples until a full FFT window is available.
    func processPCM(_ samples: UnsafePointer<Float>, count: Int, sampleRate: Float) {
        guard let fftSetup, count > 0 else { return }

        var remaining = count
        var sourceOffset = 0

        while remaining > 0 {
            let space = Self.fftSize - _accumFill
            let toCopy = min(space, remaining)

            _accumBuffer.withUnsafeMutableBufferPointer { dst in
                guard let base = dst.baseAddress else { return }
                for i in 0..<toCopy {
                    base[_accumFill + i] = samples[sourceOffset + i]
                }
            }

            _accumFill += toCopy
            sourceOffset += toCopy
            remaining -= toCopy

            if _accumFill >= Self.fftSize {
                let magnitudes = _accumBuffer.withUnsafeBufferPointer { buf -> [Float] in
                    guard let base = buf.baseAddress else { return [] }
                    return computeFFT(samples: base, fftSetup: fftSetup)
                }
                if !magnitudes.isEmpty {
                    let newBands = bucketIntoBands(magnitudes: magnitudes, sampleRate: sampleRate)
                    smoothAndStore(newBands)
                }
                _accumFill = 0
            }
        }
    }

    private func computeFFT(samples: UnsafePointer<Float>, fftSetup: FFTSetup) -> [Float] {
        let n = Self.fftSize
        let halfN = n / 2

        var windowed = [Float](repeating: 0, count: n)
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        windowed.withUnsafeMutableBufferPointer { dst in
            vDSP_vmul(samples, 1, window, 1, dst.baseAddress!, 1, vDSP_Length(n))
        }

        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.baseAddress!.assumingMemoryBound(to: DSPComplex.self),
                              2, &split, 1, vDSP_Length(halfN))
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        var scale = Float(1.0 / Float(n))
        var scaled = [Float](repeating: 0, count: halfN)
        vDSP_vsmul(&magnitudes, 1, &scale, &scaled, 1, vDSP_Length(halfN))
        return scaled
    }

    private func bucketIntoBands(magnitudes: [Float], sampleRate: Float) -> [Float] {
        let binFreqWidth = sampleRate / Float(Self.fftSize)
        var bands = [Float](repeating: 0, count: Self.bandCount)

        for band in 0..<Self.bandCount {
            let lowFreq = 20.0 * pow(1000.0, Float(band) / Float(Self.bandCount))
            let highFreq = 20.0 * pow(1000.0, Float(band + 1) / Float(Self.bandCount))
            let lowBin = max(1, Int(lowFreq / binFreqWidth))
            let highBin = min(magnitudes.count - 1, Int(highFreq / binFreqWidth))
            guard highBin > lowBin else { continue }

            var sum: Float = 0
            for bin in lowBin...highBin { sum += magnitudes[bin] }
            bands[band] = min(1.0, sqrt(sum / Float(highBin - lowBin + 1)) * 8.0)
        }
        return bands
    }

    private func smoothAndStore(_ newBands: [Float]) {
        let third = Self.bandCount / 3
        let newBass = newBands[0..<third].reduce(0, +) / Float(third)
        let newMid = newBands[third..<(2 * third)].reduce(0, +) / Float(third)
        let newTreble = newBands[(2 * third)..<Self.bandCount].reduce(0, +) / Float(Self.bandCount - 2 * third)
        let newEnergy = (newBass + newMid + newTreble) / 3.0

        // Asymmetric smoothing: fast attack (0.4), slow decay (0.12)
        // Makes the visualizer snap to beats but fade smoothly
        lock.withLock {
            _bass = smooth(old: _bass, new: newBass)
            _mid = smooth(old: _mid, new: newMid)
            _treble = smooth(old: _treble, new: newTreble)
            _energy = smooth(old: _energy, new: newEnergy)
            for i in 0..<Self.bandCount {
                _bands[i] = smooth(old: _bands[i], new: newBands[i])
            }
        }
    }

    private func smooth(old: Float, new: Float) -> Float {
        let factor: Float = new > old ? 0.4 : 0.12
        return old + (new - old) * factor
    }
}
