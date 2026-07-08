import Testing
import Foundation
@testable import Vibrdrome

/// Tests for AudioSpectrum FFT data storage and thread safety.
struct AudioSpectrumTests {

    // MARK: - Initial State

    @Test func initialValuesAreZero() {
        let spectrum = AudioSpectrum.shared
        spectrum.reset()
        #expect(spectrum.bass == 0)
        #expect(spectrum.mid == 0)
        #expect(spectrum.treble == 0)
        #expect(spectrum.energy == 0)
        #expect(spectrum.bands.count == AudioSpectrum.bandCount)
        #expect(spectrum.bands.allSatisfy { $0 == 0 })
    }

    @Test func resetClearsAllValues() {
        let spectrum = AudioSpectrum.shared
        // Process some data to set non-zero values
        var samples = [Float](repeating: 0, count: AudioSpectrum.fftSize)
        // Generate a simple sine wave
        for i in 0..<AudioSpectrum.fftSize {
            samples[i] = sin(Float(i) * 0.1)
        }
        samples.withUnsafeBufferPointer { buf in
            spectrum.processPCM(buf.baseAddress!, count: buf.count, sampleRate: 44100)
        }

        spectrum.reset()
        #expect(spectrum.bass == 0)
        #expect(spectrum.mid == 0)
        #expect(spectrum.treble == 0)
        #expect(spectrum.energy == 0)
    }

    // MARK: - FFT Processing

    @Test func processPCMProducesNonZeroValues() {
        let spectrum = AudioSpectrum.shared
        spectrum.reset()

        // Generate a 440Hz sine wave
        var samples = [Float](repeating: 0, count: AudioSpectrum.fftSize)
        let freq: Float = 440.0
        let sampleRate: Float = 44100.0
        for i in 0..<AudioSpectrum.fftSize {
            samples[i] = sin(2.0 * .pi * freq * Float(i) / sampleRate)
        }

        samples.withUnsafeBufferPointer { buf in
            spectrum.processPCM(buf.baseAddress!, count: buf.count, sampleRate: sampleRate)
        }

        // Should have some energy after processing a sine wave
        #expect(spectrum.energy > 0)
    }

    @Test func processPCMIgnoresTooSmallBuffers() {
        let spectrum = AudioSpectrum.shared
        spectrum.reset()

        // Buffer smaller than fftSize should be ignored
        let samples = [Float](repeating: 0.5, count: 100)
        samples.withUnsafeBufferPointer { buf in
            spectrum.processPCM(buf.baseAddress!, count: buf.count, sampleRate: 44100)
        }

        // Values should remain zero since buffer was too small
        #expect(spectrum.energy == 0)
    }

    @Test func valuesClampedToUnitRange() {
        let spectrum = AudioSpectrum.shared
        spectrum.reset()

        // Process a loud signal
        let samples = [Float](repeating: 1.0, count: AudioSpectrum.fftSize)
        samples.withUnsafeBufferPointer { buf in
            spectrum.processPCM(buf.baseAddress!, count: buf.count, sampleRate: 44100)
        }

        #expect(spectrum.bass >= 0 && spectrum.bass <= 1)
        #expect(spectrum.mid >= 0 && spectrum.mid <= 1)
        #expect(spectrum.treble >= 0 && spectrum.treble <= 1)
        #expect(spectrum.energy >= 0 && spectrum.energy <= 1)
        #expect(spectrum.bands.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    // MARK: - Band Count

    @Test func bandCountIs32() {
        #expect(AudioSpectrum.bandCount == 32)
    }

    @Test func fftSizeIsPowerOf2() {
        let size = AudioSpectrum.fftSize
        #expect(size > 0)
        #expect(size & (size - 1) == 0) // Power of 2 check
    }

    // MARK: - FFT overlap (#112)

    /// 50% overlap (hop = fftSize/2): a contiguous `2 * fftSize` sample stream should produce
    /// ~3 FFT windows — landing at offsets 0, fftSize/2, and fftSize — instead of the 2
    /// non-overlapping windows the old clear-on-complete behavior produced.
    @Test func fftOverlapProducesThreeWindowsForDoubleLength() {
        let spectrum = AudioSpectrum.shared
        spectrum.reset()
        let before = spectrum.fftComputeCountForTesting

        let count = AudioSpectrum.fftSize * 2
        var samples = [Float](repeating: 0, count: count)
        let sr: Float = 44100, freq: Float = 440
        for i in 0..<count { samples[i] = sin(2.0 * .pi * freq * Float(i) / sr) }
        samples.withUnsafeBufferPointer { buf in
            spectrum.processPCM(buf.baseAddress!, count: buf.count, sampleRate: sr)
        }

        let computed = spectrum.fftComputeCountForTesting - before
        #expect(computed == 3)  // was 2 without overlap
    }

    /// hopSize is exactly half the FFT window (50% overlap).
    @Test func hopSizeIsHalfFFTSize() {
        #expect(AudioSpectrum.hopSize == AudioSpectrum.fftSize / 2)
    }

    // MARK: - Soft-knee de-saturation (#112 Slice B)

    /// Below the knee (0.6) the curve is identity — quiet/medium content is untouched, so derived
    /// energy (and the idle thresholds that read it) is preserved.
    @Test func softKneeIsIdentityBelowKnee() {
        #expect(AudioSpectrum.softKnee(0.0) == 0.0)
        #expect(AudioSpectrum.softKnee(0.3) == 0.3)
        #expect(AudioSpectrum.softKnee(0.6) == 0.6)
    }

    /// A medium-hot value that the old hard clamp would have pinned at exactly 1.0 now keeps
    /// gradation (strictly between the knee and the ceiling) — the actual de-saturation win. Only
    /// genuinely extreme input approaches the ceiling (and may reach 1.0 at Float precision).
    @Test func softKneeCompressesMediumHotBelowCeiling() {
        let mediumHot = AudioSpectrum.softKnee(1.5)   // hard clamp would have pinned this to 1.0
        #expect(mediumHot > 0.6 && mediumHot < 1.0)
        let veryHot = AudioSpectrum.softKnee(8.0)
        #expect(veryHot >= mediumHot && veryHot <= 1.0)  // monotonic, capped at the ceiling
    }

    /// Monotonic increasing and always within [0, 1] across the range.
    @Test func softKneeIsMonotonicAndInUnitRange() {
        var previous = AudioSpectrum.softKnee(0)
        for step in 1...200 {
            let value = AudioSpectrum.softKnee(Float(step) * 0.05)  // 0.05 … 10.0
            #expect(value >= 0 && value <= 1)
            #expect(value >= previous)  // non-decreasing
            previous = value
        }
    }

    // MARK: - Fast (native-only) band set — Slice 3

    @Test func bandsFastInitialZeroAndReset() {
        let spectrum = AudioSpectrum.shared
        spectrum.reset()
        #expect(spectrum.bandsFast.count == AudioSpectrum.bandCount)
        #expect(spectrum.bandsFast.allSatisfy { $0 == 0 })
    }

    @Test func bandsFastClampedToUnitRange() {
        let spectrum = AudioSpectrum.shared
        spectrum.reset()
        let samples = [Float](repeating: 1.0, count: AudioSpectrum.fftSize)
        samples.withUnsafeBufferPointer { buf in
            spectrum.processPCM(buf.baseAddress!, count: buf.count, sampleRate: 44100)
        }
        #expect(spectrum.bandsFast.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    /// The fast band set uses a quicker EMA (0.5/0.35) than the smoothed `bands` (0.4/0.12),
    /// so it rises faster on a transient and fades faster on silence.
    @Test func bandsFastRespondsFasterThanSmoothedBands() {
        let spectrum = AudioSpectrum.shared
        spectrum.reset()

        // One loud frame from zero → fast attack (0.5) should exceed the smoothed attack (0.4).
        var tone = [Float](repeating: 0, count: AudioSpectrum.fftSize)
        let sr: Float = 44100, freq: Float = 440
        for i in 0..<AudioSpectrum.fftSize { tone[i] = sin(2.0 * .pi * freq * Float(i) / sr) }
        tone.withUnsafeBufferPointer { buf in
            spectrum.processPCM(buf.baseAddress!, count: buf.count, sampleRate: sr)
        }
        let sumBands = spectrum.bands.reduce(0, +)
        let sumFast = spectrum.bandsFast.reduce(0, +)
        #expect(sumBands > 0)        // sanity: the tone produced signal
        #expect(sumFast > sumBands)  // faster attack

        // One silent frame → fast decay (retains 0.65) should fall below the smoothed (retains 0.88).
        let silence = [Float](repeating: 0, count: AudioSpectrum.fftSize)
        silence.withUnsafeBufferPointer { buf in
            spectrum.processPCM(buf.baseAddress!, count: buf.count, sampleRate: sr)
        }
        #expect(spectrum.bandsFast.reduce(0, +) < spectrum.bands.reduce(0, +))  // faster fade
    }
}
