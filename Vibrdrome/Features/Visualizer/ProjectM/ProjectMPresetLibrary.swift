import Foundation

/// One bundled MilkDrop (`.milk`) preset.
struct ProjectMPreset: Identifiable, Equatable {
    /// File basename without extension, e.g. "vibrdrome_plasma".
    let id: String
    let url: URL

    /// Friendly name: drop the `vibrdrome_` prefix, de-underscore, capitalize.
    var displayName: String {
        id.replacingOccurrences(of: "vibrdrome_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

/// Swift-managed ordering over the bundled `.milk` presets (Phase 2D). Provides
/// sequential next/previous and shuffled random selection. No `projectM-4-playlist`
/// library is used; projectM stays preset-locked and every transition is driven
/// from here. Pure value type with no GL/UIKit dependency, so the ordering logic
/// is unit-testable by injecting a fixed preset list.
struct ProjectMPresetLibrary {
    let presets: [ProjectMPreset]

    init(presets: [ProjectMPreset]) {
        self.presets = presets
    }

    init(bundle: Bundle = .main) {
        let urls = bundle.urls(forResourcesWithExtension: "milk", subdirectory: nil) ?? []
        presets = urls
            .map { ProjectMPreset(id: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.displayName < $1.displayName }
    }

    var isEmpty: Bool { presets.isEmpty }

    func preset(id: String?) -> ProjectMPreset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    /// The preset after `id` (wraps). `nil` id → the first preset. Single preset
    /// → itself. Empty → nil.
    func next(after id: String?) -> ProjectMPreset? {
        guard !presets.isEmpty else { return nil }
        guard let id, let i = presets.firstIndex(where: { $0.id == id }) else { return presets.first }
        return presets[(i + 1) % presets.count]
    }

    /// The preset before `id` (wraps).
    func previous(before id: String?) -> ProjectMPreset? {
        guard !presets.isEmpty else { return nil }
        guard let id, let i = presets.firstIndex(where: { $0.id == id }) else { return presets.first }
        return presets[(i - 1 + presets.count) % presets.count]
    }

    /// A random preset, never the current one when more than one exists.
    func random(excluding id: String?) -> ProjectMPreset? {
        guard !presets.isEmpty else { return nil }
        guard presets.count > 1 else { return presets.first }
        let candidates = presets.filter { $0.id != id }
        return candidates.randomElement() ?? presets.first
    }
}
