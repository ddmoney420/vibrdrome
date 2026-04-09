import SwiftUI

// MARK: - Glass Effect Modifiers (iOS 26+)

#if os(iOS)
/// Applies `.glassEffect()` on iOS 26+, no-op on older versions.
struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
        }
    }
}

/// Applies `.glassEffect()` with a circular shape on iOS 26+, no-op on older versions.
struct GlassEffectCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content
        }
    }
}

/// Applies `.glassEffect()` with a rounded rectangle for toolbar bars on iOS 26+.
struct GlassEffectToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 16))
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
}
