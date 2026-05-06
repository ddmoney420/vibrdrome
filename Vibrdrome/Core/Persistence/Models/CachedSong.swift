import Foundation
import SwiftData

@Model
final class CachedSong {
    #Index<CachedSong>([\.title], [\.albumId], [\.artistId], [\.genre], [\.isStarred], [\.playCount], [\.lastPlayed])

    @Attribute(.unique) var id: String
    var title: String
    var artist: String?
    var albumArtist: String?
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
        self.albumArtist = song.albumArtist
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

    /// Convert back to a Song value type for playback queue reconstruction.
    func toSong() -> Song {
        Song(
            id: id,
            parent: nil,
            title: title,
            album: albumName,
            artist: artist,
            albumArtist: albumArtist,
            albumId: albumId,
            artistId: artistId,
            track: track,
            year: year,
            genre: genre,
            coverArt: coverArtId,
            size: size,
            contentType: contentType,
            suffix: suffix,
            duration: duration,
            bitRate: bitRate,
            path: nil,
            discNumber: discNumber,
            created: nil,
            starred: isStarred ? "true" : nil,
            userRating: rating,
            bpm: nil,
            replayGain: nil,
            musicBrainzId: nil
        )
    }
}
