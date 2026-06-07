#if DEBUG
import XCTest
@testable import Vibrdrome

/// Research Step 3/4 — decode tests for the inline DEBUG preset library. Pure JSON
/// decode; no GL/UIKit. Confirms the v0 format parses and the four original presets
/// are present with sane fields, including the Phase-4 bloom/overlay knobs.
final class PermissivePresetTests: XCTestCase {

    func testLibraryDecodesFourPresets() {
        let presets = PermissivePresetLibrary.presets
        XCTAssertEqual(presets.count, 4)
        XCTAssertEqual(presets.map(\.id),
                       ["vibrdrome_aurora", "vibrdrome_pulse", "vibrdrome_nebula", "vibrdrome_spectrum"])
        XCTAssertEqual(presets.map(\.name), ["Aurora", "Pulse", "Nebula", "Spectrum"])
    }

    func testAllPresetsVersion1AndAuthored() {
        for p in PermissivePresetLibrary.presets {
            XCTAssertEqual(p.version, 1)
            XCTAssertEqual(p.author, "Vibrdrome")
        }
    }

    func testFieldRangesAreSane() {
        for p in PermissivePresetLibrary.presets {
            XCTAssertTrue((0...1).contains(p.decay), "\(p.id) decay")
            XCTAssertGreaterThanOrEqual(p.zoom, 0)
            XCTAssertGreaterThanOrEqual(p.pulseScale, 0)
            XCTAssertTrue(p.paletteIndex == 0 || p.paletteIndex == 1)
            XCTAssertTrue((0...1).contains(p.bloomStrength), "\(p.id) bloom")
            XCTAssertTrue((0...1).contains(p.waveformStrength), "\(p.id) overlay")
        }
    }

    func testNebulaBloomsAndSpectrumOverlays() {
        let by = Dictionary(uniqueKeysWithValues: PermissivePresetLibrary.presets.map { ($0.id, $0) })
        XCTAssertGreaterThan(by["vibrdrome_nebula"]?.bloomStrength ?? 0, 0.5)   // glow showcase
        XCTAssertGreaterThan(by["vibrdrome_spectrum"]?.waveformStrength ?? 0, 0.5) // overlay showcase
    }

    func testNewFieldsDefaultWhenAbsent() {
        // A v0 preset without the Phase-4 keys still decodes (decodeIfPresent → 0).
        let json = """
        {"version":1,"id":"old","name":"Old","author":"Vibrdrome","license":"permissive-tbd",
         "decay":0.9,"zoom":0.03,"rotate":0.02,"paletteIndex":0,"paletteShift":0.0,
         "pulseScale":0.6,"zoomBass":0.7,"rotateTreble":0.4,"pulseBass":0.85}
        """
        let p = try? JSONDecoder().decode(PermissivePreset.self, from: Data(json.utf8))
        XCTAssertEqual(p?.id, "old")
        XCTAssertEqual(p?.bloomStrength, 0)
        XCTAssertEqual(p?.waveformStrength, 0)
    }

    func testFallbackPresetExists() {
        XCTAssertEqual(PermissivePreset.fallback.id, "fallback")
    }
}
#endif
