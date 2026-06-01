import Foundation
import SwiftData

@Model
final class CachedArtist {
    #Index<CachedArtist>([\.name], [\.isStarred])

    @Attribute(.unique) var id: String
    var name: String
    var coverArtId: String?
    var albumCount: Int?
    var isStarred: Bool = false
    var artistImageUrl: String?
    var userRating: Int?
    var averageRating: Double?
    var cachedAt: Date = Date()

    init(from artist: Artist) {
        self.id = artist.id
        self.name = artist.name
        self.coverArtId = artist.coverArt
        self.albumCount = artist.albumCount
        self.isStarred = artist.starred != nil
        self.artistImageUrl = artist.artistImageUrl
        self.userRating = artist.userRating
        self.averageRating = artist.averageRating
    }

    func toArtist() -> Artist {
        Artist(
            id: id,
            name: name,
            coverArt: coverArtId,
            artistImageUrl: artistImageUrl,
            albumCount: albumCount,
            starred: isStarred ? "true" : nil,
            userRating: userRating,
            averageRating: averageRating,
            album: nil
        )
    }
}
