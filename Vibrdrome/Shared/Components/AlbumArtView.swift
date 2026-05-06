import SwiftUI
import NukeUI
import Nuke

struct AlbumArtView: View {
    let url: URL?
    let blurURL: URL?
    let cacheKey: String?
    let blurCacheKey: String?
    var size: CGFloat? = 50
    var cornerRadius: CGFloat = 6

    init(url: URL?, size: CGFloat? = 50, cornerRadius: CGFloat = 6) {
        self.url = url
        self.blurURL = nil
        self.cacheKey = nil
        self.blurCacheKey = nil
        self.size = size
        self.cornerRadius = cornerRadius
    }

    /// Convenience init — computes both full-res and blur URLs from the shared client directly
    /// so this view has no @Environment dependency and won't re-render on AppState changes.
    init(coverArtId: String?, size: CGFloat? = 50, cornerRadius: CGFloat = 6, requestSize: Int? = CoverArtSize.gridThumb) {
        self.size = size
        self.cornerRadius = cornerRadius
        if let coverArtId {
            let client = AppState.shared.subsonicClient
            self.url = client.coverArtURL(id: coverArtId, size: requestSize)
            self.cacheKey = client.coverArtCacheKey(id: coverArtId, size: requestSize)
            if requestSize == CoverArtSize.gridThumb {
                self.blurURL = client.coverArtURL(id: coverArtId, size: CoverArtSize.blur)
                self.blurCacheKey = client.coverArtCacheKey(id: coverArtId, size: CoverArtSize.blur)
            } else {
                self.blurURL = nil
                self.blurCacheKey = nil
            }
        } else {
            self.url = nil
            self.blurURL = nil
            self.cacheKey = nil
            self.blurCacheKey = nil
        }
    }

    var body: some View {
        if let url {
            LazyImage(request: fullResRequest(for: url)) { state in
                if let image = state.image {
                    let fromCache = { () -> Bool in
                        if case .success(let r) = state.result {
                            return r.cacheType == .memory || r.cacheType == .disk
                        }
                        return false
                    }()
                    image.resizable().aspectRatio(contentMode: .fill)
                        .transition(fromCache ? .identity : .opacity.animation(.easeIn(duration: 0.15)))
                } else {
                    blurPlaceholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
        } else {
            fallbackPlaceholder
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var blurPlaceholder: some View {
        if let blurURL {
            LazyImage(request: blurRequest(for: blurURL)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: 12, opaque: true)
                } else {
                    fallbackPlaceholder
                }
            }
            .pipeline(VibrdromeApp.blurPipeline)
            .frame(width: size, height: size)
        } else {
            fallbackPlaceholder
        }
    }

    private var fallbackPlaceholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .frame(width: size, height: size)
    }

    private func fullResRequest(for url: URL) -> ImageRequest {
        guard let size else { return ImageRequest(url: url) }
        #if os(macOS)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        #else
        let scale = UIScreen.main.scale
        #endif
        let pixelSize = CGSize(width: size * scale, height: size * scale)
        var request = ImageRequest(
            url: url,
            processors: [ImageProcessors.Resize(size: pixelSize, contentMode: .aspectFill, crop: true)]
        )
        if let cacheKey { request.userInfo[.imageIdKey] = cacheKey }
        return request
    }

    private func blurRequest(for url: URL) -> ImageRequest {
        var request = ImageRequest(url: url)
        if let blurCacheKey { request.userInfo[.imageIdKey] = blurCacheKey }
        return request
    }
}
