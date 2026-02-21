import SwiftUI

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
