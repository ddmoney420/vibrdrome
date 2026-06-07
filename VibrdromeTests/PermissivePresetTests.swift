#if DEBUG
import XCTest
@testable import Vibrdrome

/// Research Step 3 — decode tests for the inline DEBUG preset library. Pure JSON
/// decode; no GL/UIKit. Confirms the v0 format parses and the two original presets
/// are present with sane fields.
final class PermissivePresetTests: XCTestCase {

    func testLibraryDecodesTwoPresets() {
        let presets = PermissivePresetLibrary.presets
        XCTAssertEqual(presets.count, 2)
        XCTAssertEqual(presets.map(\.id), ["vibrdrome_aurora", "vibrdrome_pulse"])
        XCTAssertEqual(presets.map(\.name), ["Aurora", "Pulse"])
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
            XCTAssertTrue((0...1).contains(p.paletteIndex == 1 ? 1.0 : 0.0))  // index within the 2 built-in palettes
            XCTAssertTrue(p.paletteIndex == 0 || p.paletteIndex == 1)
        }
    }

    func testDecodesFromRawJSON() {
        let json = """
        {"version":1,"id":"x","name":"X","author":"Vibrdrome","license":"permissive-tbd",
         "decay":0.9,"zoom":0.03,"rotate":0.02,"paletteIndex":0,"paletteShift":0.0,
         "pulseScale":0.6,"zoomBass":0.7,"rotateTreble":0.4,"pulseBass":0.85}
        """
        let p = try? JSONDecoder().decode(PermissivePreset.self, from: Data(json.utf8))
        XCTAssertEqual(p?.id, "x")
        XCTAssertEqual(p?.paletteIndex, 0)
    }

    func testFallbackPresetExists() {
        XCTAssertEqual(PermissivePreset.fallback.id, "fallback")
    }
}
#endif
