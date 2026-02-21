import Foundation
import SwiftData

@Model
final class CachedAlbum {
    @Attribute(.unique) var id: String
    var name: String
    var artistName: String?
    var artistId: String?
    var coverArtId: String?
    var year: Int?
    var genre: String?
    var songCount: Int?
    var duration: Int?
    var isStarred: Bool = false
    var cachedAt: Date = Date()

    var songs: [CachedSong] = []

    init(from album: Album) {
        self.id = album.id
        self.name = album.name
        self.artistName = album.artist
        self.artistId = album.artistId
        self.coverArtId = album.coverArt
        self.year = album.year
        self.genre = album.genre
        self.songCount = album.songCount
        self.duration = album.duration
        self.isStarred = album.starred != nil
    }
}
