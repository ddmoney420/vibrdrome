import Foundation
import SwiftData

@Model
final class CachedSong {
    @Attribute(.unique) var id: String
    var title: String
    var artist: String?
    var albumName: String?
    var albumId: String?
    var artistId: String?
    var coverArtId: String?
    var track: Int?
    var discNumber: Int?
    var year: Int?
    var genre: String?
    var duration: Int?
    var bitRate: Int?
    var suffix: String?
    var contentType: String?
    var size: Int?
    var isStarred: Bool = false
    var rating: Int = 0
    var lastPlayed: Date?
    var playCount: Int = 0
    var cachedAt: Date = Date()

    @Relationship(inverse: \CachedAlbum.songs) var album: CachedAlbum?
    @Relationship(inverse: \DownloadedSong.song) var download: DownloadedSong?

    init(from song: Song) {
        self.id = song.id
        self.title = song.title
        self.artist = song.artist
        self.albumName = song.album
        self.albumId = song.albumId
        self.artistId = song.artistId
        self.coverArtId = song.coverArt
        self.track = song.track
        self.discNumber = song.discNumber
        self.year = song.year
        self.genre = song.genre
        self.duration = song.duration
        self.bitRate = song.bitRate
        self.suffix = song.suffix
        self.contentType = song.contentType
        self.size = song.size
        self.isStarred = song.starred != nil
    }
}
