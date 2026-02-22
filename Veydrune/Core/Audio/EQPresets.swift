import Foundation

struct EQPreset: Identifiable, Sendable {
    let id: String
    let name: String
    /// Gain values for 10 ISO bands (32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16kHz)
    let gains: [Float]
}

enum EQPresets {
    static let bands = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    static let flat = EQPreset(id: "flat", name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    static let bassBoost = EQPreset(id: "bass_boost", name: "Bass Boost", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0])
    static let trebleBoost = EQPreset(id: "treble_boost", name: "Treble Boost", gains: [0, 0, 0, 0, 0, 0, 2, 4, 5, 6])
    static let rock = EQPreset(id: "rock", name: "Rock", gains: [5, 4, 2, 0, -1, 0, 2, 3, 4, 5])
    static let pop = EQPreset(id: "pop", name: "Pop", gains: [-1, 1, 3, 4, 3, 0, -1, -1, 1, 2])
    static let jazz = EQPreset(id: "jazz", name: "Jazz", gains: [3, 2, 0, 1, -1, -1, 0, 1, 3, 4])
    static let classical = EQPreset(id: "classical", name: "Classical", gains: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4])
    static let vocal = EQPreset(id: "vocal", name: "Vocal", gains: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1])
    static let lateNight = EQPreset(id: "late_night", name: "Late Night", gains: [3, 3, 2, 0, -2, -2, 0, 1, 2, 2])

    static let all: [EQPreset] = [
        flat, bassBoost, trebleBoost, rock, pop, jazz, classical, vocal, lateNight,
    ]
}
