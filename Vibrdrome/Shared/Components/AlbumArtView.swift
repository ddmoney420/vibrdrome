import SwiftUI
import Nuke
import NukeUI

struct AlbumArtView: View, Equatable {
    let coverArtId: String?
    var size: CGFloat = 50
    var cornerRadius: CGFloat = 6

    @Environment(AppState.self) private var appState

    nonisolated static func == (lhs: AlbumArtView, rhs: AlbumArtView) -> Bool {
        lhs.coverArtId == rhs.coverArtId && lhs.size == rhs.size && lhs.cornerRadius == rhs.cornerRadius
    }

    var body: some View {
        if let coverArtId {
            let hasCached = AlbumArtImageCache.shared.image(for: coverArtId) != nil
            LazyImage(url: appState.subsonicClient.coverArtURL(id: coverArtId, size: Int(size * 2))) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .transition(hasCached ? .identity : .opacity.animation(.easeIn(duration: 0.2)))
                        .onAppear {
                            if let platformImage = state.imageContainer?.image {
                                AlbumArtImageCache.shared.store(platformImage, for: coverArtId)
                            }
                        }
                } else if state.error != nil {
                    cachedOrPlaceholder(for: coverArtId)
                } else {
                    cachedOrPlaceholder(for: coverArtId)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
        } else {
            placeholderView
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func cachedOrPlaceholder(for id: String) -> some View {
        if let cached = AlbumArtImageCache.shared.image(for: id) {
            Image(platformImage: cached)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }
}

private extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}
