import Testing
import Foundation
@testable import Vibrdrome

/// Tests for EQ pre-gain attenuation logic used in EQTapProcessor.
struct EQPreGainTests {

    /// Replicate the pre-gain calculation from EQTapProcessor
    private func computePreGain(maxBoostDB: Float) -> Float {
        maxBoostDB > 0.5 ? powf(10, -maxBoostDB / 20) : 1.0
    }

    @Test func noBoostReturnsUnity() {
        #expect(computePreGain(maxBoostDB: 0) == 1.0)
    }

    @Test func smallBoostBelowThresholdReturnsUnity() {
        #expect(computePreGain(maxBoostDB: 0.3) == 1.0)
        #expect(computePreGain(maxBoostDB: 0.5) == 1.0)
    }

    @Test func sixDBBoostHalvesSignal() {
        let preGain = computePreGain(maxBoostDB: 6)
        // 6dB attenuation ≈ 0.501
        #expect(preGain > 0.49)
        #expect(preGain < 0.52)
    }

    @Test func twelveDBBoostQuartersSignal() {
        let preGain = computePreGain(maxBoostDB: 12)
        // 12dB attenuation ≈ 0.251
        #expect(preGain > 0.24)
        #expect(preGain < 0.26)
    }

    @Test func negativeBoostReturnsUnity() {
        // Negative gain (cut) should not attenuate
        #expect(computePreGain(maxBoostDB: -6) == 1.0)
        #expect(computePreGain(maxBoostDB: -12) == 1.0)
    }

    @Test func preGainIsAlwaysPositive() {
        for db in stride(from: Float(0), through: 20, by: 1) {
            let preGain = computePreGain(maxBoostDB: db)
            #expect(preGain > 0, "Pre-gain should always be positive for \(db) dB boost")
            #expect(preGain <= 1, "Pre-gain should never exceed 1.0 for \(db) dB boost")
        }
    }

    @Test func preGainDecreasesWithMoreBoost() {
        let gain6 = computePreGain(maxBoostDB: 6)
        let gain12 = computePreGain(maxBoostDB: 12)
        #expect(gain12 < gain6, "More boost should result in more attenuation")
    }
}
