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
        var samples = [Float](repeating: 0.5, count: 100)
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
        var samples = [Float](repeating: 1.0, count: AudioSpectrum.fftSize)
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
}
