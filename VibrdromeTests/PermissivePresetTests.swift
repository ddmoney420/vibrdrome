#if DEBUG
import XCTest
@testable import Vibrdrome

/// Research Step 3/4 — decode tests for the inline DEBUG preset library. Pure JSON
/// decode; no GL/UIKit. Confirms the v0 format parses and the four original presets
/// are present with sane fields, including the Phase-4 bloom/overlay knobs.
final class PermissivePresetTests: XCTestCase {

    func testLibraryDecodesEightPresets() {
        let presets = PermissivePresetLibrary.presets
        XCTAssertEqual(presets.count, 8)
        XCTAssertEqual(presets.map(\.id),
                       ["vibrdrome_flux", "vibrdrome_kaleidoscope", "vibrdrome_radiant",
                        "vibrdrome_spectralspokes", "vibrdrome_aurora", "vibrdrome_pulse",
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

    func testAllPresetsUseNonLegacyEngine() {
        // Every shipping preset runs the new engine — curl-flow (flow > 0) or polar warp
        // (warpMode > 0) — with structured geometry (a waveform OR spectrum spokes) and a
        // distinct cosine palette (idx >= 2). No legacy center-path presets.
        for p in PermissivePresetLibrary.presets {
            XCTAssertTrue(p.flow > 0 || p.warpMode > 0, "\(p.id) should not be on the legacy center path")
            XCTAssertTrue(p.waveStyle > 0 || p.spokes > 0, "\(p.id) needs geometry (waveform or spokes)")
            XCTAssertGreaterThanOrEqual(p.paletteIndex, 2, "\(p.id) palette")
        }
    }

    func testPresetsHaveVariedPalettes() {
        // 6 presets across 5 cosine palettes (2–6) — expect broad variety (≥5 distinct).
        let palettes = PermissivePresetLibrary.presets.map(\.paletteIndex)
        XCTAssertGreaterThanOrEqual(Set(palettes).count, 5, "presets should span varied palettes")
    }

    func testKaleidoscopeIsKaleidoscopeWaveform() {
        // Step 8b — Kaleidoscope is the kaleidoscope-waveform family: the wedge fold supplies
        // the symmetry; the source is intentionally ASYMMETRIC (curl-flow + scope) so the fold
        // has angular detail to mirror into a mandala (a symmetric source folds to a circle).
        let by = Dictionary(uniqueKeysWithValues: PermissivePresetLibrary.presets.map { ($0.id, $0) })
        let kaleidoscope = by["vibrdrome_kaleidoscope"]
        XCTAssertEqual(kaleidoscope?.kaleido, 6)        // wedge fold on
        XCTAssertEqual(kaleidoscope?.symmetry, 0)       // rectilinear mirror off (wedge supplies it)
        XCTAssertGreaterThan(kaleidoscope?.flow ?? 0, 0)  // curl-flow (asymmetric) under the fold
        XCTAssertGreaterThan(kaleidoscope?.waveStyle ?? 0, 0)
    }

    func testHeroFluxUsesPolarWarp() {
        // Step 8 — the hero runs the polar warp (vortex), not curl-flow.
        let by = Dictionary(uniqueKeysWithValues: PermissivePresetLibrary.presets.map { ($0.id, $0) })
        let flux = by["vibrdrome_flux"]
        XCTAssertEqual(flux?.warpMode, 1)                 // polar warp selected
        XCTAssertGreaterThan(flux?.swirl ?? 0, 0)         // swirl (the spiral) on
        XCTAssertGreaterThan(flux?.swirlFreq ?? 0, 0)
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

    func testRadiantIsRadialSpectrumSpokes() {
        // Step 8c — Radiant is the spectrum-geometry family: radial spokes from the bands,
        // no waveform (the spokes are the geometry).
        let by = Dictionary(uniqueKeysWithValues: PermissivePresetLibrary.presets.map { ($0.id, $0) })
        let radiant = by["vibrdrome_radiant"]
        XCTAssertGreaterThan(radiant?.spokes ?? 0, 0)        // spokes on
        XCTAssertGreaterThan(radiant?.spokeLen ?? 0, 0)
        XCTAssertEqual(radiant?.waveStyle, 0)                // no waveform
        XCTAssertEqual(radiant?.kaleido, 0)                  // no wedge fold
        XCTAssertEqual(radiant?.spokeInject, 0)              // present-only (sharp, no trails)
    }

    func testSpectralSpokesInjectsForBloomAndTrails() {
        // Step 8c-2 — Spectral Spokes is the injected variant: spokes drawn into the feedback
        // field (spokeInject 1) so they bloom and trail.
        let by = Dictionary(uniqueKeysWithValues: PermissivePresetLibrary.presets.map { ($0.id, $0) })
        let ss = by["vibrdrome_spectralspokes"]
        XCTAssertGreaterThan(ss?.spokes ?? 0, 0)
        XCTAssertEqual(ss?.spokeInject, 1)                   // injected → bloom + trails
        XCTAssertGreaterThan(ss?.whirl ?? 0, 0)              // centre whirlpool
        XCTAssertEqual(ss?.symmetry, 1)                      // L/R mirror re-symmetrizes the whirl
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
        XCTAssertEqual(p?.swirl, 0)
        XCTAssertEqual(p?.swirlFreq, 8)    // safe default
        XCTAssertEqual(p?.warpMode, 0)
        XCTAssertEqual(p?.kaleido, 0)
        XCTAssertEqual(p?.spokes, 0)
        XCTAssertEqual(p?.spokeLen, 0)
        XCTAssertEqual(p?.spokeInject, 0)
        XCTAssertEqual(p?.whirl, 0)
    }

    func testFallbackPresetExists() {
        XCTAssertEqual(PermissivePreset.fallback.id, "fallback")
    }
}
#endif
