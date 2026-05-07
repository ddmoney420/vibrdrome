import Foundation
import SwiftData

@Model
final class CachedArtist {
    @Attribute(.unique) var id: String
    var name: String
    var coverArtId: String?
    var albumCount: Int?
    var isStarred: Bool = false
    var cachedAt: Date = Date()

    init(from artist: Artist) {
        self.id = artist.id
        self.name = artist.name
        self.coverArtId = artist.coverArt
        self.albumCount = artist.albumCount
        self.isStarred = artist.starred != nil
    }

    func toArtist() -> Artist {
        Artist(
            id: id,
            name: name,
            coverArt: coverArtId,
            albumCount: albumCount,
            starred: isStarred ? "true" : nil,
            album: nil
        )
    }
}
