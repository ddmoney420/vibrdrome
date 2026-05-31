import SwiftUI

// MARK: - Glass Effect Modifiers (iOS 26+)

#if os(iOS)
/// Applies `.glassEffect()` on iOS 26+, no-op on older versions.
/// Respects the `enableLiquidGlass` user preference.
struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if swift(>=6.1)
        let glassEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableLiquidGlass)
        if #available(iOS 26.0, *), glassEnabled {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Applies `.glassEffect()` with a circular shape on iOS 26+, no-op on older versions.
/// Respects the `enableLiquidGlass` user preference.
struct GlassEffectCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if swift(>=6.1)
        let glassEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableLiquidGlass)
        if #available(iOS 26.0, *), glassEnabled {
            content.glassEffect(.regular, in: .circle)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Applies `.glassEffect()` with a rounded rectangle for toolbar bars on iOS 26+.
/// Respects the `enableLiquidGlass` user preference.
struct GlassEffectToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if swift(>=6.1)
        let glassEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableLiquidGlass)
        if #available(iOS 26.0, *), glassEnabled {
            content.glassEffect(.regular, in: .rect(cornerRadius: 16))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Conditionally applies `.glassEffect()` capsule on iOS 26+ when enabled.
struct ConditionalGlassModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.modifier(GlassEffectModifier())
        } else {
            content
        }
    }
}
#endif

// MARK: - Grid Density

enum CoverArtSize {
    static let blur = 32                // tiny blur placeholder — whole library fits in memory
    static let gridThumb = 400          // 200pt @2x — matches grid card display size
    static let listThumb = 112          // 56pt @2x — matches list row display size
    static let detail: Int? = nil       // omit size param — serve original resolution
}

enum GridDensity: String, CaseIterable {
    case compact, comfortable, spacious

    var minimumWidth: CGFloat {
        switch self {
        case .compact:     return 130
        case .comfortable: return 170
        case .spacious:    return 220
        }
    }

    var label: String {
        switch self {
        case .compact:     return "Compact"
        case .comfortable: return "Comfortable"
        case .spacious:    return "Spacious"
        }
    }
}

// MARK: - Theme

enum Theme {
    static let cornerRadius: CGFloat = 12
    static let albumArtShadow: CGFloat = 8
    static let listRowSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 16
    static let miniPlayerHeight: CGFloat = 64

    // Platform-adaptive sizes
    static var albumCardSize: CGFloat {
        #if os(macOS)
        200
        #else
        160
        #endif
    }

    static var songCardSize: CGFloat {
        #if os(macOS)
        160
        #else
        130
        #endif
    }

    static var artistBubbleSize: CGFloat {
        #if os(macOS)
        100
        #else
        80
        #endif
    }

    static var playlistCardSize: CGFloat {
        #if os(macOS)
        200
        #else
        170
        #endif
    }

    static var searchAlbumTileSize: CGFloat {
        #if os(macOS)
        180
        #else
        140
        #endif
    }
}
