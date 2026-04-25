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

    /// Returns the column count for grid views given the user's base preference
    /// and the current vertical size class. Doubles the base count when the
    /// vertical size class is `.compact` (iPhone in landscape) so a portrait-
    /// tuned value still uses the extra horizontal space after rotation.
    /// Clamped to the picker's 2-10 range. On iPad and macOS the size class
    /// is regular in both orientations so the base value is used as-is.
    static func effectiveGridColumns(
        base: Int,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> Int {
        let multiplier = verticalSizeClass == .compact ? 2 : 1
        return max(2, min(10, base * multiplier))
    }
}
