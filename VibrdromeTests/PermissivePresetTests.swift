#if DEBUG
import XCTest
@testable import Vibrdrome

/// Decode tests for the inline DEBUG preset library (the native-visualizer spike). Pure JSON
/// decode; no GL/UIKit. Confirms the v0 format parses, the 50-preset library is well-formed,
/// and the hero presets carry their expected feature knobs.
final class PermissivePresetTests: XCTestCase {

    private var byId: [String: PermissivePreset] {
        Dictionary(uniqueKeysWithValues: PermissivePresetLibrary.presets.map { ($0.id, $0) })
    }

    func testLibraryDecodesSeventySixPresets() {
        let presets = PermissivePresetLibrary.presets
        XCTAssertEqual(presets.count, 76)                     // 50 2D + 26 3D/procedural scenes
        XCTAssertEqual(presets.first?.name, "Flux")           // hero is index 0 (default on open)
        XCTAssertEqual(Set(presets.map(\.id)).count, 76)      // ids are unique
        // A spread of families is present.
        for id in ["vibrdrome_flux", "vibrdrome_kaleidoscope", "vibrdrome_radiant",
                   "vibrdrome_spectralspokes", "vibrdrome_wormhole", "vibrdrome_zenith",
                   "vibrdrome_tunnel", "vibrdrome_orbs", "vibrdrome_warpfield", "vibrdrome_gyroid",
                   "vibrdrome_ocean", "vibrdrome_highway", "vibrdrome_fracture", "vibrdrome_crystal",
                   "vibrdrome_mirrorchamber", "vibrdrome_elevator", "vibrdrome_perlinblob",
                   "vibrdrome_faultline", "vibrdrome_cymatic", "vibrdrome_horizondome",
                   "vibrdrome_vortex", "vibrdrome_shockwave", "vibrdrome_menger",
                   "vibrdrome_urbancanyon", "vibrdrome_chrome", "vibrdrome_apollonian",
                   "vibrdrome_reaction", "vibrdrome_hex", "vibrdrome_truchet",
                   "vibrdrome_torusknot", "vibrdrome_caustic", "vibrdrome_cathedral"] {
            XCTAssertNotNil(byId[id], "missing \(id)")
        }
    }

    func testThreeDScenesAreTwentySixSceneModes() {
        XCTAssertEqual(byId["vibrdrome_tunnel"]?.sceneMode, 1)            // raymarch tunnel
        XCTAssertEqual(byId["vibrdrome_orbs"]?.sceneMode, 2)            // glowing-orb / metaball
        XCTAssertEqual(byId["vibrdrome_warpfield"]?.sceneMode, 3)       // screen-space warp starfield
        XCTAssertEqual(byId["vibrdrome_gyroid"]?.sceneMode, 4)          // raymarched gyroid lattice
        XCTAssertEqual(byId["vibrdrome_ocean"]?.sceneMode, 5)           // raymarched audio ocean
        XCTAssertEqual(byId["vibrdrome_highway"]?.sceneMode, 6)         // screen-space synthwave grid
        XCTAssertEqual(byId["vibrdrome_fracture"]?.sceneMode, 7)        // raymarched 3D voronoi fracture
        XCTAssertEqual(byId["vibrdrome_crystal"]?.sceneMode, 8)         // octahedron-cluster crystal SDF
        XCTAssertEqual(byId["vibrdrome_mirrorchamber"]?.sceneMode, 9)   // kaleidoscopic mirror corridor
        XCTAssertEqual(byId["vibrdrome_elevator"]?.sceneMode, 10)       // inside-out box shaft
        XCTAssertEqual(byId["vibrdrome_perlinblob"]?.sceneMode, 11)     // ridged-FBM displaced SDF blob
        XCTAssertEqual(byId["vibrdrome_faultline"]?.sceneMode, 12)      // ridged heightfield fault terrain
        XCTAssertEqual(byId["vibrdrome_cymatic"]?.sceneMode, 13)        // analytic Chladni cymatic plate
        XCTAssertEqual(byId["vibrdrome_horizondome"]?.sceneMode, 14)    // analytic dome + floor grid
        XCTAssertEqual(byId["vibrdrome_vortex"]?.sceneMode, 15)         // thin-shell funnel raymarch
        XCTAssertEqual(byId["vibrdrome_shockwave"]?.sceneMode, 16)      // radial shockwave procedural
        XCTAssertEqual(byId["vibrdrome_menger"]?.sceneMode, 17)         // menger sponge DE fractal
        XCTAssertEqual(byId["vibrdrome_urbancanyon"]?.sceneMode, 18)    // neon city canyon raymarch
        XCTAssertEqual(byId["vibrdrome_chrome"]?.sceneMode, 19)         // refractive liquid chrome
        XCTAssertEqual(byId["vibrdrome_apollonian"]?.sceneMode, 20)     // sphere-inversion apollonian DE
        XCTAssertEqual(byId["vibrdrome_reaction"]?.sceneMode, 21)       // procedural reaction-diffusion membrane
        XCTAssertEqual(byId["vibrdrome_hex"]?.sceneMode, 22)           // extruded hex honeycomb heightfield
        XCTAssertEqual(byId["vibrdrome_truchet"]?.sceneMode, 23)        // raised truchet circuit heightfield
        XCTAssertEqual(byId["vibrdrome_torusknot"]?.sceneMode, 24)      // analytic torus-knot SDF
        XCTAssertEqual(byId["vibrdrome_caustic"]?.sceneMode, 25)        // perspective caustic pool
        XCTAssertEqual(byId["vibrdrome_cathedral"]?.sceneMode, 26)      // raymarched cathedral interior
        // Exactly those twenty-six are non-2D; everything else stays on the 2D engine (sceneMode 0).
        let threeD = PermissivePresetLibrary.presets.filter { $0.sceneMode > 0 }.map(\.id)
        XCTAssertEqual(Set(threeD),
                       ["vibrdrome_tunnel", "vibrdrome_orbs", "vibrdrome_warpfield",
                        "vibrdrome_gyroid", "vibrdrome_ocean", "vibrdrome_highway",
                        "vibrdrome_fracture", "vibrdrome_crystal",
                        "vibrdrome_mirrorchamber", "vibrdrome_elevator",
                        "vibrdrome_perlinblob", "vibrdrome_faultline",
                        "vibrdrome_cymatic", "vibrdrome_horizondome",
                        "vibrdrome_vortex", "vibrdrome_shockwave",
                        "vibrdrome_menger", "vibrdrome_urbancanyon",
                        "vibrdrome_chrome", "vibrdrome_apollonian",
                        "vibrdrome_reaction", "vibrdrome_hex",
                        "vibrdrome_truchet", "vibrdrome_torusknot",
                        "vibrdrome_caustic", "vibrdrome_cathedral"])
    }

    func testAllPresetsVersion1AndAuthored() {
        for p in PermissivePresetLibrary.presets {
            XCTAssertEqual(p.version, 1)
            XCTAssertEqual(p.author, "Vibrdrome")
            XCTAssertFalse(p.name.isEmpty)
        }
    }

    func testFieldRangesAreSane() {
        for p in PermissivePresetLibrary.presets {
            XCTAssertTrue((0...1).contains(p.decay), "\(p.id) decay")
            XCTAssertGreaterThanOrEqual(p.zoom, 0)
            XCTAssertGreaterThanOrEqual(p.pulseScale, 0)
            XCTAssertTrue((0...10).contains(p.paletteIndex), "\(p.id) palette")   // cosine palettes 2…10
            XCTAssertTrue((0...1).contains(p.bloomStrength), "\(p.id) bloom")
            XCTAssertTrue((0...1).contains(p.waveformStrength), "\(p.id) overlay")
            XCTAssertGreaterThanOrEqual(p.flow, 0)
            XCTAssertGreaterThan(p.flowScale, 0)        // default 2.5 when absent
            XCTAssertGreaterThanOrEqual(p.vibrance, 0)
        }
    }

    func testPresetsHaveVariedPalettes() {
        // 50 presets across the cosine palettes (2…10) — expect broad colour variety.
        let palettes = PermissivePresetLibrary.presets.map(\.paletteIndex)
        XCTAssertGreaterThanOrEqual(Set(palettes).count, 8, "presets should span varied palettes")
    }

    func testHeroFluxUsesPolarWarpAndWaveform() {
        let flux = byId["vibrdrome_flux"]
        XCTAssertEqual(flux?.warpMode, 1)                 // polar warp (vortex)
        XCTAssertGreaterThan(flux?.swirl ?? 0, 0)         // swirl spiral on
        XCTAssertEqual(flux?.paletteIndex, 2)             // deep-space hero palette
        XCTAssertEqual(flux?.waveStyle, 1)                // circular waveform
        XCTAssertEqual(flux?.symmetry, 1)                 // bilateral mirror
        XCTAssertGreaterThan(flux?.vibrance ?? 0, 1.0)
    }

    func testKaleidoscopeIsKaleidoscopeWaveform() {
        let k = byId["vibrdrome_kaleidoscope"]
        XCTAssertEqual(k?.kaleido, 6)                     // wedge fold on
        XCTAssertEqual(k?.symmetry, 0)                    // wedge supplies the symmetry
        XCTAssertGreaterThan(k?.flow ?? 0, 0)             // asymmetric curl-flow source
        XCTAssertGreaterThan(k?.waveStyle ?? 0, 0)
    }

    func testRadiantIsRadialSpectrumSpokes() {
        let r = byId["vibrdrome_radiant"]
        XCTAssertGreaterThan(r?.spokes ?? 0, 0)           // spokes on
        XCTAssertGreaterThan(r?.spokeLen ?? 0, 0)
        XCTAssertEqual(r?.waveStyle, 0)                   // spokes ARE the geometry
        XCTAssertEqual(r?.spokeInject, 0)                 // present-only (sharp)
    }

    func testSpectralSpokesInjectsWithWhirlpool() {
        let ss = byId["vibrdrome_spectralspokes"]
        XCTAssertGreaterThan(ss?.spokes ?? 0, 0)
        XCTAssertEqual(ss?.spokeInject, 1)                // injected → bloom + trails
        XCTAssertGreaterThan(ss?.whirl ?? 0, 0)           // centre whirlpool
        XCTAssertEqual(ss?.symmetry, 1)                   // L/R mirror re-symmetrizes the whirl
    }

    func testSpectrumIsHorizontalScope() {
        XCTAssertEqual(byId["vibrdrome_spectrum"]?.waveStyle, 2)
    }

    func testNewFieldsDefaultWhenAbsent() {
        // A minimal v0 preset (only the required keys) still decodes — every optional knob
        // takes its safe decodeIfPresent default.
        let json = """
        {"version":1,"id":"old","name":"Old","author":"Vibrdrome","license":"permissive-tbd",
         "decay":0.9,"zoom":0.03,"rotate":0.02,"paletteIndex":0,"paletteShift":0.0,
         "pulseScale":0.6,"zoomBass":0.7,"rotateTreble":0.4,"pulseBass":0.85}
        """
        let p = try? JSONDecoder().decode(PermissivePreset.self, from: Data(json.utf8))
        XCTAssertEqual(p?.id, "old")
        XCTAssertEqual(p?.flow, 0)
        XCTAssertEqual(p?.flowScale, 2.5)
        XCTAssertEqual(p?.vibrance, 1.0)
        XCTAssertEqual(p?.swirlFreq, 8)
        XCTAssertEqual(p?.warpMode, 0)
        XCTAssertEqual(p?.kaleido, 0)
        XCTAssertEqual(p?.spokes, 0)
        XCTAssertEqual(p?.whirl, 0)
        // Phase 9–13 knobs all default to 0.
        XCTAssertEqual(p?.lattice, 0)
        XCTAssertEqual(p?.fractal, 0)
        XCTAssertEqual(p?.spiral, 0)
        XCTAssertEqual(p?.tile, 0)
        XCTAssertEqual(p?.tunnel3d, 0)
        XCTAssertEqual(p?.plasma, 0)
        XCTAssertEqual(p?.phyllo, 0)
        XCTAssertEqual(p?.ripple, 0)
        XCTAssertEqual(p?.hex, 0)
        XCTAssertEqual(p?.chroma, 0)
        XCTAssertEqual(p?.sceneMode, 0)   // defaults to the 2D engine
    }

    func testFallbackPresetExists() {
        XCTAssertEqual(PermissivePreset.fallback.id, "fallback")
    }
}
#endif
