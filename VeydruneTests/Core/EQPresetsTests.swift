import Testing
import Foundation
@testable import Veydrune

/// Tests for EQ preset definitions and band configuration.
struct EQPresetsTests {

    // MARK: - Band Definitions

    @Test func tenBandsDefined() {
        #expect(EQPresets.bands.count == 10)
        #expect(EQPresets.frequencies.count == 10)
    }

    @Test func frequenciesAscending() {
        for i in 1..<EQPresets.frequencies.count {
            #expect(EQPresets.frequencies[i] > EQPresets.frequencies[i - 1])
        }
    }

    @Test func frequenciesMatchISO() {
        let expected: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        #expect(EQPresets.frequencies == expected)
    }

    @Test func bandLabelsMatchCount() {
        #expect(EQPresets.bands.count == EQPresets.frequencies.count)
    }

    // MARK: - Preset Properties

    @Test func allPresetsHaveTenBands() {
        for preset in EQPresets.all {
            #expect(preset.gains.count == 10, "Preset \(preset.name) should have 10 bands")
        }
    }

    @Test func flatPresetAllZeros() {
        let flat = EQPresets.flat
        #expect(flat.id == "flat")
        for gain in flat.gains {
            #expect(gain == 0)
        }
    }

    @Test func bassBoostHasPositiveLowFrequencies() {
        let bb = EQPresets.bassBoost
        // First 4 bands (32-250Hz) should be positive
        #expect(bb.gains[0] > 0)
        #expect(bb.gains[1] > 0)
        #expect(bb.gains[2] > 0)
        #expect(bb.gains[3] > 0)
    }

    @Test func trebleBoostHasPositiveHighFrequencies() {
        let tb = EQPresets.trebleBoost
        // Last 4 bands (4k-16kHz) should be positive
        #expect(tb.gains[6] > 0)
        #expect(tb.gains[7] > 0)
        #expect(tb.gains[8] > 0)
        #expect(tb.gains[9] > 0)
    }

    @Test func allPresetsHaveUniqueIds() {
        let ids = EQPresets.all.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count)
    }

    @Test func allPresetsHaveNames() {
        for preset in EQPresets.all {
            #expect(!preset.name.isEmpty, "Preset \(preset.id) should have a name")
        }
    }

    @Test func presetCount() {
        // flat, bass_boost, treble_boost, rock, pop, jazz, classical, vocal, late_night
        #expect(EQPresets.all.count == 9)
    }

    @Test func gainsInReasonableRange() {
        for preset in EQPresets.all {
            for (i, gain) in preset.gains.enumerated() {
                #expect(gain >= -12 && gain <= 12,
                    "Preset \(preset.name) band \(i) gain \(gain) out of range")
            }
        }
    }

    // MARK: - EQPreset struct

    @Test func presetIsIdentifiable() {
        let preset = EQPresets.rock
        #expect(preset.id == "rock")
    }

    @Test func presetIsSendable() {
        // Compile-time check — if this compiles, EQPreset conforms to Sendable
        let preset: Sendable = EQPresets.flat
        _ = preset
    }
}
