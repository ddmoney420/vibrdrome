import Foundation
import Observation
import os.log

/// EQ preset and gain management.
/// Playback processing is handled by EQTapProcessor (inline on AVPlayer).
@Observable
@MainActor
final class EQEngine {
    static let shared = EQEngine()

    var currentPresetId: String = "flat" {
        didSet { UserDefaults.standard.set(currentPresetId, forKey: UserDefaultsKeys.eqCurrentPresetId) }
    }

    var customGains: [Float] = Array(repeating: 0, count: 10) {
        didSet {
            if let data = try? JSONEncoder().encode(customGains) {
                UserDefaults.standard.set(data, forKey: UserDefaultsKeys.eqCurrentGains)
            }
        }
    }

    private init() {
        // Restore saved state
        if let savedId = UserDefaults.standard.string(forKey: UserDefaultsKeys.eqCurrentPresetId) {
            currentPresetId = savedId
        }
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.eqCurrentGains),
           let gains = try? JSONDecoder().decode([Float].self, from: data),
           gains.count == 10 {
            customGains = gains
        }
    }

    /// Apply preset gains
    func applyPreset(_ preset: EQPreset) {
        currentPresetId = preset.id
        customGains = preset.gains
        syncCoefficients()
    }

    /// Update individual band gain (clamped to ±12 dB)
    func setGain(_ gain: Float, forBand index: Int) {
        guard index >= 0, index < 10 else { return }
        customGains[index] = min(max(gain, -12), 12)
        currentPresetId = "custom"
        syncCoefficients()
    }

    /// Push current gains to the shared coefficient store (picked up by audio taps)
    func syncCoefficients() {
        EQCoefficients.shared.update(
            gains: customGains,
            frequencies: EQPresets.frequencies
        )
    }

    // MARK: - Custom Presets

    /// Save custom preset to UserDefaults
    func saveCustomPreset(name: String) {
        var presets = loadCustomPresets()
        presets[name] = customGains
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.customEQPresets)
        }
    }

    /// Load custom presets from UserDefaults
    func loadCustomPresets() -> [String: [Float]] {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.customEQPresets),
              let presets = try? JSONDecoder().decode([String: [Float]].self, from: data)
        else { return [:] }
        return presets
    }
}
