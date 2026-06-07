#if DEBUG
import Foundation

/// Research Step 3/4 — v0 preset format for the native feedback engine. Parameters
/// only (no shader code, no expressions); versioned; original Vibrdrome format
/// (not `.milk`). DEBUG-only — the prototype loads presets from the inline JSON in
/// `PermissivePresetLibrary` so **no `.json` is bundled into the app**.
/// Human-readable copies live in `docs/permissive-visualizer/presets/*.json`.
struct PermissivePreset: Identifiable, Codable {
    let version: Int
    let id: String
    let name: String
    let author: String
    let license: String?
    let decay: Float
    let zoom: Float
    let rotate: Float
    let paletteIndex: Int
    let paletteShift: Float
    let pulseScale: Float
    let zoomBass: Float
    let rotateTreble: Float
    let pulseBass: Float
    // Step 4 — optional visual-depth knobs (decodeIfPresent → 0, so the format stays
    // backward-compatible at version 1).
    let bloomStrength: Float
    let waveformStrength: Float
    // Step 6 — optional flow-engine knobs. `flow > 0` switches the feedback pass from the
    // legacy center rotate/zoom to curl-noise advection; the rest shape flow/beat/colour.
    // All decode with safe defaults (decodeIfPresent), so version stays 1.
    let flow: Float        // flow-field advection strength, 0 = legacy center path
    let flowScale: Float   // spatial frequency of the flow field
    let beatFlow: Float    // beatPulse → flow acceleration
    let beatBloom: Float   // beatPulse → bloom kick
    let hueDrift: Float    // colour drift speed (cosine-palette path)
    // Step 7 — waveform-into-feedback (the fine-line MilkDrop look). The audio waveform is
    // drawn as thin bright geometry into the feedback texture; the warp/flow/tunnel loop
    // then pulls it into filaments. All optional/defaulted, version stays 1.
    let waveStyle: Int     // 0 = off, 1 = circular, 2 = horizontal scope
    let waveAmp: Float     // waveform displacement amount
    let waveBright: Float  // line brightness (the glow)
    let tunnel: Float      // zoom-in pull that turns the lines into a tunnel/spiral
    // Phase 7b — bilateral mirror + vibrance.
    let symmetry: Int      // 0 = off, 1 = vertical (L/R) mirror, 2 = quad (4-way)
    let vibrance: Float    // saturation + brightness multiplier (1 = neutral)
    // Phase 7c "wow" — field spin + beat-driven waveform amplitude burst.
    let spin: Float        // field rotation speed (time + beat driven)
    let beatWave: Float    // beatPulse → waveform amplitude burst (the kick "explosion")
    // Phase 8 — polar warp (the vortex). warpMode 1 selects polar; swirl/swirlFreq shape it.
    let swirl: Float       // radius-modulated angle swirl amount (the spiral)
    let swirlFreq: Float   // spatial frequency of the swirl
    let warpMode: Int      // 0 = curl-flow, 1 = polar warp (hero)
    // Phase 8b — kaleidoscope wedge count for the present-time polar fold (0 = off).
    let kaleido: Int

    init(version: Int, id: String, name: String, author: String, license: String?,
         decay: Float, zoom: Float, rotate: Float, paletteIndex: Int, paletteShift: Float,
         pulseScale: Float, zoomBass: Float, rotateTreble: Float, pulseBass: Float,
         bloomStrength: Float = 0, waveformStrength: Float = 0,
         flow: Float = 0, flowScale: Float = 2.5, beatFlow: Float = 0,
         beatBloom: Float = 0, hueDrift: Float = 0,
         waveStyle: Int = 0, waveAmp: Float = 0, waveBright: Float = 0, tunnel: Float = 0,
         symmetry: Int = 0, vibrance: Float = 1.0,
         spin: Float = 0, beatWave: Float = 0,
         swirl: Float = 0, swirlFreq: Float = 8, warpMode: Int = 0,
         kaleido: Int = 0) {
        self.version = version; self.id = id; self.name = name; self.author = author
        self.license = license; self.decay = decay; self.zoom = zoom; self.rotate = rotate
        self.paletteIndex = paletteIndex; self.paletteShift = paletteShift
        self.pulseScale = pulseScale; self.zoomBass = zoomBass; self.rotateTreble = rotateTreble
        self.pulseBass = pulseBass; self.bloomStrength = bloomStrength; self.waveformStrength = waveformStrength
        self.flow = flow; self.flowScale = flowScale; self.beatFlow = beatFlow
        self.beatBloom = beatBloom; self.hueDrift = hueDrift
        self.waveStyle = waveStyle; self.waveAmp = waveAmp; self.waveBright = waveBright; self.tunnel = tunnel
        self.symmetry = symmetry; self.vibrance = vibrance
        self.spin = spin; self.beatWave = beatWave
        self.swirl = swirl; self.swirlFreq = swirlFreq; self.warpMode = warpMode
        self.kaleido = kaleido
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        author = try c.decode(String.self, forKey: .author)
        license = try c.decodeIfPresent(String.self, forKey: .license)
        decay = try c.decode(Float.self, forKey: .decay)
        zoom = try c.decode(Float.self, forKey: .zoom)
        rotate = try c.decode(Float.self, forKey: .rotate)
        paletteIndex = try c.decode(Int.self, forKey: .paletteIndex)
        paletteShift = try c.decode(Float.self, forKey: .paletteShift)
        pulseScale = try c.decode(Float.self, forKey: .pulseScale)
        zoomBass = try c.decode(Float.self, forKey: .zoomBass)
        rotateTreble = try c.decode(Float.self, forKey: .rotateTreble)
        pulseBass = try c.decode(Float.self, forKey: .pulseBass)
        bloomStrength = try c.decodeIfPresent(Float.self, forKey: .bloomStrength) ?? 0
        waveformStrength = try c.decodeIfPresent(Float.self, forKey: .waveformStrength) ?? 0
        flow = try c.decodeIfPresent(Float.self, forKey: .flow) ?? 0
        flowScale = try c.decodeIfPresent(Float.self, forKey: .flowScale) ?? 2.5
        beatFlow = try c.decodeIfPresent(Float.self, forKey: .beatFlow) ?? 0
        beatBloom = try c.decodeIfPresent(Float.self, forKey: .beatBloom) ?? 0
        hueDrift = try c.decodeIfPresent(Float.self, forKey: .hueDrift) ?? 0
        waveStyle = try c.decodeIfPresent(Int.self, forKey: .waveStyle) ?? 0
        waveAmp = try c.decodeIfPresent(Float.self, forKey: .waveAmp) ?? 0
        waveBright = try c.decodeIfPresent(Float.self, forKey: .waveBright) ?? 0
        tunnel = try c.decodeIfPresent(Float.self, forKey: .tunnel) ?? 0
        symmetry = try c.decodeIfPresent(Int.self, forKey: .symmetry) ?? 0
        vibrance = try c.decodeIfPresent(Float.self, forKey: .vibrance) ?? 1.0
        spin = try c.decodeIfPresent(Float.self, forKey: .spin) ?? 0
        beatWave = try c.decodeIfPresent(Float.self, forKey: .beatWave) ?? 0
        swirl = try c.decodeIfPresent(Float.self, forKey: .swirl) ?? 0
        swirlFreq = try c.decodeIfPresent(Float.self, forKey: .swirlFreq) ?? 8
        warpMode = try c.decodeIfPresent(Int.self, forKey: .warpMode) ?? 0
        kaleido = try c.decodeIfPresent(Int.self, forKey: .kaleido) ?? 0
    }

    static let fallback = PermissivePreset(
        version: 1, id: "fallback", name: "Fallback", author: "Vibrdrome", license: "permissive-tbd",
        decay: 0.94, zoom: 0.03, rotate: 0.02, paletteIndex: 0, paletteShift: 0,
        pulseScale: 0.6, zoomBass: 0.7, rotateTreble: 0.4, pulseBass: 0.85,
        bloomStrength: 0.25, waveformStrength: 0)
}

/// Inline DEBUG preset library — the prototype's preset source. NOT a bundled
/// resource. Matches the docs example presets.
enum PermissivePresetLibrary {
    static let json = """
    [
      {
        "version": 1, "id": "vibrdrome_flux", "name": "Flux",
        "author": "Vibrdrome", "license": "permissive-tbd",
        "decay": 0.94, "zoom": 0.000, "rotate": 0.000,
        "paletteIndex": 2, "paletteShift": 0.00, "pulseScale": 0.30,
        "zoomBass": 0.00, "rotateTreble": 0.00, "pulseBass": 0.00,
        "bloomStrength": 0.55, "waveformStrength": 0.00,
        "flow": 0.00, "flowScale": 2.50, "beatFlow": 0.00,
        "beatBloom": 0.50, "hueDrift": 0.40,
        "waveStyle": 1, "waveAmp": 0.16, "waveBright": 0.95, "tunnel": 1.00,
        "symmetry": 1, "vibrance": 1.40, "spin": 0.00, "beatWave": 0.80,
        "swirl": 0.25, "swirlFreq": 8.0, "warpMode": 1
      },
      {
        "version": 1, "id": "vibrdrome_kaleidoscope", "name": "Kaleidoscope",
        "author": "Vibrdrome", "license": "permissive-tbd",
        "decay": 0.94, "zoom": 0.000, "rotate": 0.000,
        "paletteIndex": 5, "paletteShift": 0.00, "pulseScale": 0.30,
        "zoomBass": 0.00, "rotateTreble": 0.00, "pulseBass": 0.00,
        "bloomStrength": 0.55, "waveformStrength": 0.00,
        "flow": 0.60, "flowScale": 3.00, "beatFlow": 1.00,
        "beatBloom": 0.50, "hueDrift": 0.35,
        "waveStyle": 2, "waveAmp": 0.30, "waveBright": 1.00, "tunnel": 0.60,
        "symmetry": 0, "vibrance": 1.40, "spin": 0.00, "beatWave": 1.00,
        "swirl": 0.25, "swirlFreq": 8.0, "warpMode": 0, "kaleido": 6
      },
      {
        "version": 1, "id": "vibrdrome_aurora", "name": "Aurora",
        "author": "Vibrdrome", "license": "permissive-tbd",
        "decay": 0.95, "zoom": 0.000, "rotate": 0.000,
        "paletteIndex": 3, "paletteShift": 0.00, "pulseScale": 0.25,
        "zoomBass": 0.00, "rotateTreble": 0.00, "pulseBass": 0.00,
        "bloomStrength": 0.55, "waveformStrength": 0.00,
        "flow": 0.45, "flowScale": 2.00, "beatFlow": 0.70,
        "beatBloom": 0.40, "hueDrift": 0.35,
        "waveStyle": 1, "waveAmp": 0.15, "waveBright": 0.85, "tunnel": 0.50,
        "symmetry": 1, "vibrance": 1.30, "spin": 0.05, "beatWave": 0.70
      },
      {
        "version": 1, "id": "vibrdrome_pulse", "name": "Pulse",
        "author": "Vibrdrome", "license": "permissive-tbd",
        "decay": 0.87, "zoom": 0.000, "rotate": 0.000,
        "paletteIndex": 4, "paletteShift": 0.00, "pulseScale": 0.40,
        "zoomBass": 0.00, "rotateTreble": 0.00, "pulseBass": 0.00,
        "bloomStrength": 0.80, "waveformStrength": 0.00,
        "flow": 0.85, "flowScale": 3.00, "beatFlow": 1.50,
        "beatBloom": 1.00, "hueDrift": 0.60,
        "waveStyle": 1, "waveAmp": 0.22, "waveBright": 1.00, "tunnel": 0.95,
        "symmetry": 2, "vibrance": 1.60, "spin": 0.28, "beatWave": 2.00
      },
      {
        "version": 1, "id": "vibrdrome_nebula", "name": "Nebula",
        "author": "Vibrdrome", "license": "permissive-tbd",
        "decay": 0.97, "zoom": 0.000, "rotate": 0.000,
        "paletteIndex": 5, "paletteShift": 0.10, "pulseScale": 0.30,
        "zoomBass": 0.00, "rotateTreble": 0.00, "pulseBass": 0.00,
        "bloomStrength": 0.95, "waveformStrength": 0.00,
        "flow": 0.40, "flowScale": 2.20, "beatFlow": 0.60,
        "beatBloom": 0.50, "hueDrift": 0.25,
        "waveStyle": 1, "waveAmp": 0.14, "waveBright": 0.80, "tunnel": 1.20,
        "symmetry": 1, "vibrance": 1.35, "spin": 0.03, "beatWave": 0.60
      },
      {
        "version": 1, "id": "vibrdrome_spectrum", "name": "Spectrum",
        "author": "Vibrdrome", "license": "permissive-tbd",
        "decay": 0.90, "zoom": 0.000, "rotate": 0.000,
        "paletteIndex": 6, "paletteShift": 0.50, "pulseScale": 0.30,
        "zoomBass": 0.00, "rotateTreble": 0.00, "pulseBass": 0.00,
        "bloomStrength": 0.70, "waveformStrength": 0.00,
        "flow": 0.50, "flowScale": 2.50, "beatFlow": 1.20,
        "beatBloom": 0.80, "hueDrift": 0.50,
        "waveStyle": 2, "waveAmp": 0.35, "waveBright": 1.00, "tunnel": 0.60,
        "symmetry": 2, "vibrance": 1.60, "spin": 0.15, "beatWave": 1.50
      }
    ]
    """

    static let presets: [PermissivePreset] = {
        (try? JSONDecoder().decode([PermissivePreset].self, from: Data(json.utf8))) ?? []
    }()
}
#endif
