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
    var created: String?
    var userRating: Int = 0
    var label: String?
    var mbzAlbumId: String?
    var mbzAlbumArtistId: String?
    var mbzReleaseGroupId: String?
    var playCount: Int = 0
    var isCompilation: Bool = false
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
        self.created = album.created
        self.userRating = album.userRating ?? 0
        self.label = album.label
        self.mbzAlbumId = album.musicBrainzId
    }

    init(from ndAlbum: NDAlbum) {
        self.id = ndAlbum.id
        self.name = ndAlbum.name
        self.artistName = ndAlbum.artist
        self.artistId = ndAlbum.artistId
        self.coverArtId = ndAlbum.id        // ND albums use the album id as coverArt id
        self.year = ndAlbum.year
        self.genre = ndAlbum.genre
        self.songCount = ndAlbum.songCount
        self.duration = ndAlbum.duration.map { Int($0) }
        self.isStarred = ndAlbum.starred ?? false
        self.userRating = ndAlbum.rating ?? 0
        self.mbzAlbumId = ndAlbum.mbzAlbumId
        self.mbzAlbumArtistId = ndAlbum.mbzAlbumArtistId
        self.mbzReleaseGroupId = ndAlbum.mbzReleaseGroupId
        self.playCount = ndAlbum.playCount ?? 0
        self.isCompilation = ndAlbum.compilation ?? false
    }

    func update(from ndAlbum: NDAlbum) {
        name = ndAlbum.name
        artistId = ndAlbum.artistId
        year = ndAlbum.year
        genre = ndAlbum.genre
        songCount = ndAlbum.songCount
        duration = ndAlbum.duration.map { Int($0) }
        isStarred = ndAlbum.starred ?? false
        userRating = ndAlbum.rating ?? 0
        mbzAlbumId = ndAlbum.mbzAlbumId
        mbzAlbumArtistId = ndAlbum.mbzAlbumArtistId
        mbzReleaseGroupId = ndAlbum.mbzReleaseGroupId
        playCount = ndAlbum.playCount ?? 0
        isCompilation = ndAlbum.compilation ?? false
        cachedAt = Date()
    }

    /// Update existing record with fresh server data.
    func update(from album: Album) {
        name = album.name
        artistName = album.artist
        artistId = album.artistId
        coverArtId = album.coverArt
        year = album.year
        genre = album.genre
        songCount = album.songCount
        duration = album.duration
        isStarred = album.starred != nil
        created = album.created
        userRating = album.userRating ?? 0
        label = album.label
        mbzAlbumId = album.musicBrainzId
        cachedAt = Date()
    }

    /// Convert back to an Album value type for view compatibility.
    func toAlbum() -> Album {
        Album(
            id: id,
            name: name,
            artist: artistName,
            artistId: artistId,
            coverArt: coverArtId,
            songCount: songCount,
            duration: duration,
            year: year,
            genre: genre,
            starred: isStarred ? "true" : nil,
            created: created,
            userRating: userRating > 0 ? userRating : nil,
            song: nil,
            replayGain: nil,
            musicBrainzId: mbzAlbumId,
            recordLabels: label.map { [RecordLabel(name: $0)] }
        )
    }
}
