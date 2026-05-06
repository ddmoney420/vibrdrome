import SwiftUI
import NukeUI
import Nuke

struct AlbumArtView: View {
    let url: URL?
    var size: CGFloat? = 50
    var cornerRadius: CGFloat = 6

    init(url: URL?, size: CGFloat? = 50, cornerRadius: CGFloat = 6) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
    }

    /// Convenience init matching the old API — computes the URL from the shared client directly
    /// so this view has no @Environment dependency and won't re-render on AppState changes.
    init(coverArtId: String?, size: CGFloat? = 50, cornerRadius: CGFloat = 6, requestSize: Int? = CoverArtSize.gridThumb) {
        self.size = size
        self.cornerRadius = cornerRadius
        if let coverArtId {
            self.url = AppState.shared.subsonicClient.coverArtURL(id: coverArtId, size: requestSize)
        } else {
            self.url = nil
        }
    }

    var body: some View {
        if let url {
            LazyImage(request: imageRequest(for: url)) { state in
                if let image = state.image {
                    let fromMemory = { () -> Bool in
                        if case .success(let r) = state.result { return r.cacheType == .memory }
                        return false
                    }()
                    image.resizable().aspectRatio(contentMode: .fill)
                        .transition(fromMemory ? .identity : .opacity.animation(.easeIn(duration: 0.15)))
                } else {
                    placeholderView
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

    private func imageRequest(for url: URL) -> ImageRequest {
        guard let size else { return ImageRequest(url: url) }
        #if os(macOS)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        #else
        let scale = UIScreen.main.scale
        #endif
        let pixelSize = CGSize(width: size * scale, height: size * scale)
        return ImageRequest(
            url: url,
            processors: [ImageProcessors.Resize(size: pixelSize, contentMode: .aspectFill, crop: true)]
        )
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .frame(width: size, height: size)
    }
}
