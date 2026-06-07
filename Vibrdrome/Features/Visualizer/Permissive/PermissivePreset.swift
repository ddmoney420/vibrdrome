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

    init(version: Int, id: String, name: String, author: String, license: String?,
         decay: Float, zoom: Float, rotate: Float, paletteIndex: Int, paletteShift: Float,
         pulseScale: Float, zoomBass: Float, rotateTreble: Float, pulseBass: Float,
         bloomStrength: Float = 0, waveformStrength: Float = 0) {
        self.version = version; self.id = id; self.name = name; self.author = author
        self.license = license; self.decay = decay; self.zoom = zoom; self.rotate = rotate
        self.paletteIndex = paletteIndex; self.paletteShift = paletteShift
        self.pulseScale = pulseScale; self.zoomBass = zoomBass; self.rotateTreble = rotateTreble
        self.pulseBass = pulseBass; self.bloomStrength = bloomStrength; self.waveformStrength = waveformStrength
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
        "version": 1, "id": "vibrdrome_aurora", "name": "Aurora",
        "author": "Vibrdrome", "license": "permissive-tbd",
        "decay": 0.96, "zoom": 0.020, "rotate": 0.030,
        "paletteIndex": 0, "paletteShift": 0.00, "pulseScale": 0.55,
        "zoomBass": 0.70, "rotateTreble": 0.50, "pulseBass": 0.80,
        "bloomStrength": 0.25, "waveformStrength": 0.00
      },
      {
        "version": 1, "id": "vibrdrome_pulse", "name": "Pulse",
        "author": "Vibrdrome", "license": "permissive-tbd",
        "decay": 0.90, "zoom": 0.045, "rotate": 0.012,
        "paletteIndex": 1, "paletteShift": 0.30, "pulseScale": 1.10,
        "zoomBass": 1.00, "rotateTreble": 0.25, "pulseBass": 1.00,
        "bloomStrength": 0.35, "waveformStrength": 0.20
      },
      {
        "version": 1, "id": "vibrdrome_nebula", "name": "Nebula",
        "author": "Vibrdrome", "license": "permissive-tbd",
        "decay": 0.97, "zoom": 0.015, "rotate": 0.020,
        "paletteIndex": 0, "paletteShift": 0.10, "pulseScale": 0.50,
        "zoomBass": 0.60, "rotateTreble": 0.40, "pulseBass": 0.70,
        "bloomStrength": 0.90, "waveformStrength": 0.00
      },
      {
        "version": 1, "id": "vibrdrome_spectrum", "name": "Spectrum",
        "author": "Vibrdrome", "license": "permissive-tbd",
        "decay": 0.88, "zoom": 0.030, "rotate": 0.010,
        "paletteIndex": 1, "paletteShift": 0.50, "pulseScale": 0.70,
        "zoomBass": 0.80, "rotateTreble": 0.30, "pulseBass": 0.90,
        "bloomStrength": 0.40, "waveformStrength": 0.90
      }
    ]
    """

    static let presets: [PermissivePreset] = {
        (try? JSONDecoder().decode([PermissivePreset].self, from: Data(json.utf8))) ?? []
    }()
}
#endif
