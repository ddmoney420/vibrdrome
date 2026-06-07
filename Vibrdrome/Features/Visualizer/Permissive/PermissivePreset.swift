#if DEBUG
import Foundation

/// Research Step 3 — v0 preset format for the native feedback engine. Parameters
/// only (no shader code, no expressions); versioned; original Vibrdrome format
/// (not `.milk`). DEBUG-only — the prototype loads presets from the inline JSON in
/// `PermissivePresetLibrary` so **no `.json` is bundled into the app**.
/// Human-readable copies live in `docs/permissive-visualizer/presets/*.json`.
struct PermissivePreset: Codable, Identifiable {
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

    /// Used if the inline library ever fails to decode (it won't, but the renderer
    /// must still draw something).
    static let fallback = PermissivePreset(
        version: 1, id: "fallback", name: "Fallback", author: "Vibrdrome", license: "permissive-tbd",
        decay: 0.94, zoom: 0.03, rotate: 0.02, paletteIndex: 0, paletteShift: 0,
        pulseScale: 0.6, zoomBass: 0.7, rotateTreble: 0.4, pulseBass: 0.85)
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
        "zoomBass": 0.70, "rotateTreble": 0.50, "pulseBass": 0.80
      },
      {
        "version": 1, "id": "vibrdrome_pulse", "name": "Pulse",
        "author": "Vibrdrome", "license": "permissive-tbd",
        "decay": 0.90, "zoom": 0.045, "rotate": 0.012,
        "paletteIndex": 1, "paletteShift": 0.30, "pulseScale": 1.10,
        "zoomBass": 1.00, "rotateTreble": 0.25, "pulseBass": 1.00
      }
    ]
    """

    static let presets: [PermissivePreset] = {
        (try? JSONDecoder().decode([PermissivePreset].self, from: Data(json.utf8))) ?? []
    }()
}
#endif
