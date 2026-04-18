import Nuke
import Foundation

/// Synchronous in-memory image cache layered on top of Nuke's async pipeline.
///
/// **Why this exists alongside Nuke's built-in cache:**
/// Nuke's `ImagePipeline` cache is asynchronous — even a memory-cache hit goes through
/// an async request/response cycle, which causes a brief placeholder flash on every
/// SwiftUI re-render (e.g. scrolling a grid, switching tabs, or state changes that
/// trigger view identity updates). This NSCache provides an *instant, synchronous*
/// lookup path: if the cover art was loaded during this session, `AlbumArtView` can
/// display it immediately without a loading state or fade-in transition.
///
/// The two caches serve different roles:
/// - **Nuke pipeline cache**: disk + memory, handles network fetching, deduplication,
///   and progressive decoding. Source of truth for loading images.
/// - **AlbumArtImageCache**: session-scoped, synchronous, display-only. Populated as
///   a side effect when Nuke finishes loading. Avoids re-entering Nuke's async path
///   for images we've already rendered this session.
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
