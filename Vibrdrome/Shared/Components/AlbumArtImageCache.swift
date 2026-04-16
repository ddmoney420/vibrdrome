import Nuke
import Foundation

@MainActor
final class AlbumArtImageCache {
    static let shared = AlbumArtImageCache()
    private let cache = NSCache<NSString, PlatformImage>()

    private init() {
        cache.countLimit = 300
    }

    func image(for coverArtId: String) -> PlatformImage? {
        cache.object(forKey: coverArtId as NSString)
    }

    func store(_ image: PlatformImage, for coverArtId: String) {
        cache.setObject(image, forKey: coverArtId as NSString)
    }
}
