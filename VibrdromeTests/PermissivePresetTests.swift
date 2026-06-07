#if DEBUG
import XCTest
@testable import Vibrdrome

/// Research Step 3/4 — decode tests for the inline DEBUG preset library. Pure JSON
/// decode; no GL/UIKit. Confirms the v0 format parses and the four original presets
/// are present with sane fields, including the Phase-4 bloom/overlay knobs.
final class PermissivePresetTests: XCTestCase {

    func testLibraryDecodesFivePresets() {
        let presets = PermissivePresetLibrary.presets
        XCTAssertEqual(presets.count, 5)
        XCTAssertEqual(presets.map(\.id),
                       ["vibrdrome_flux", "vibrdrome_aurora", "vibrdrome_pulse",
                        "vibrdrome_nebula", "vibrdrome_spectrum"])
        XCTAssertEqual(presets.first?.name, "Flux")   // hero is index 0 (default on open)
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
            XCTAssertTrue((0...6).contains(p.paletteIndex), "\(p.id) palette")
            XCTAssertTrue((0...1).contains(p.bloomStrength), "\(p.id) bloom")
            XCTAssertTrue((0...1).contains(p.waveformStrength), "\(p.id) overlay")
            XCTAssertGreaterThanOrEqual(p.flow, 0)
            XCTAssertGreaterThan(p.flowScale, 0)        // default 2.5 when absent
            XCTAssertGreaterThanOrEqual(p.vibrance, 0)
        }
    }

    func testAllPresetsUseFlowEngineWithWaveform() {
        // Phase 7c — every shipping preset now runs the flow engine with a real waveform
        // and a distinct cosine palette (idx >= 2). No more legacy center-path presets.
        for p in PermissivePresetLibrary.presets {
            XCTAssertGreaterThan(p.flow, 0, "\(p.id) flow")
            XCTAssertGreaterThan(p.waveStyle, 0, "\(p.id) waveStyle")
            XCTAssertGreaterThanOrEqual(p.paletteIndex, 2, "\(p.id) palette")
        }
    }

    func testPresetsHaveDistinctPalettes() {
        let palettes = PermissivePresetLibrary.presets.map(\.paletteIndex)
        XCTAssertEqual(Set(palettes).count, palettes.count, "each preset should have a unique palette")
    }

    func testHeroFluxUsesFlowEngine() {
        // Step 6 — the hero opts into the flow engine, the beat→flow link, and palette 2.
        let by = Dictionary(uniqueKeysWithValues: PermissivePresetLibrary.presets.map { ($0.id, $0) })
        let flux = by["vibrdrome_flux"]
        XCTAssertGreaterThan(flux?.flow ?? 0, 0)          // curl-noise advection on
        XCTAssertGreaterThan(flux?.beatFlow ?? 0, 0)      // beat accelerates flow
        XCTAssertEqual(flux?.paletteIndex, 2)             // cosine hero palette
    }

    func testHeroFluxDrawsCircularWaveform() {
        // Step 7 — the hero draws a bright circular waveform into the feedback, pulled into
        // filaments by the tunnel.
        let by = Dictionary(uniqueKeysWithValues: PermissivePresetLibrary.presets.map { ($0.id, $0) })
        let flux = by["vibrdrome_flux"]
        XCTAssertEqual(flux?.waveStyle, 1)                // circular
        XCTAssertGreaterThan(flux?.waveAmp ?? 0, 0)
        XCTAssertGreaterThan(flux?.waveBright ?? 0, 0)
        XCTAssertGreaterThan(flux?.tunnel ?? 0, 0)
        XCTAssertEqual(flux?.symmetry, 1)                 // bilateral mirror on
        XCTAssertGreaterThan(flux?.vibrance ?? 0, 1.0)    // boosted vibrance
    }

    func testSpectrumIsScopeAndPulseIsQuad() {
        // Phase 7c — distinct forms: Spectrum is a horizontal scope; Pulse is a quad fold.
        let by = Dictionary(uniqueKeysWithValues: PermissivePresetLibrary.presets.map { ($0.id, $0) })
        XCTAssertEqual(by["vibrdrome_spectrum"]?.waveStyle, 2)   // horizontal scope
        XCTAssertEqual(by["vibrdrome_pulse"]?.symmetry, 2)       // quad kaleidoscope
        XCTAssertGreaterThan(by["vibrdrome_pulse"]?.beatWave ?? 0, 1.0)  // hard beat burst
    }

    func testNewFieldsDefaultWhenAbsent() {
        // A v0 preset without the Phase-4/6 keys still decodes (safe decodeIfPresent
        // defaults: flow→0, flowScale→2.5, the rest→0).
        let json = """
        {"version":1,"id":"old","name":"Old","author":"Vibrdrome","license":"permissive-tbd",
         "decay":0.9,"zoom":0.03,"rotate":0.02,"paletteIndex":0,"paletteShift":0.0,
         "pulseScale":0.6,"zoomBass":0.7,"rotateTreble":0.4,"pulseBass":0.85}
        """
        let p = try? JSONDecoder().decode(PermissivePreset.self, from: Data(json.utf8))
        XCTAssertEqual(p?.id, "old")
        XCTAssertEqual(p?.bloomStrength, 0)
        XCTAssertEqual(p?.waveformStrength, 0)
        XCTAssertEqual(p?.flow, 0)
        XCTAssertEqual(p?.flowScale, 2.5)
        XCTAssertEqual(p?.beatFlow, 0)
        XCTAssertEqual(p?.beatBloom, 0)
        XCTAssertEqual(p?.hueDrift, 0)
        XCTAssertEqual(p?.waveStyle, 0)
        XCTAssertEqual(p?.waveAmp, 0)
        XCTAssertEqual(p?.waveBright, 0)
        XCTAssertEqual(p?.tunnel, 0)
        XCTAssertEqual(p?.symmetry, 0)
        XCTAssertEqual(p?.vibrance, 1.0)   // neutral default
        XCTAssertEqual(p?.spin, 0)
        XCTAssertEqual(p?.beatWave, 0)
    }

    func testFallbackPresetExists() {
        XCTAssertEqual(PermissivePreset.fallback.id, "fallback")
    }
}
#endif
