import Foundation
import SwiftData

@Model
final class CachedAlbum {
    #Index<CachedAlbum>([\.name], [\.artistId], [\.year], [\.isStarred], [\.userRating], [\.coverArtId])

    @Attribute(.unique) var id: String
    var name: String
    var artistName: String?
    var artistId: String?
    var coverArtId: String?
    var year: Int?
    var genres: [String] = []
    var songCount: Int?
    var duration: Int?
    var isStarred: Bool = false
    var created: String?
    var userRating: Int = 0
    var label: String?
    var cachedAt: Date = Date()

    var songs: [CachedSong] = []

    init(from album: Album) {
        self.id = album.id
        self.name = album.name
        self.artistName = album.artist
        self.artistId = album.artistId
        self.coverArtId = album.coverArt
        self.year = album.year
        self.genres = album.allGenres
        self.songCount = album.songCount
        self.duration = album.duration
        self.isStarred = album.starred != nil
        self.created = album.created
        self.userRating = album.userRating ?? 0
        self.label = album.label
    }

    /// Update existing record with fresh server data.
    func update(from album: Album) {
        name = album.name
        artistName = album.artist
        artistId = album.artistId
        coverArtId = album.coverArt
        year = album.year
        genres = album.allGenres
        songCount = album.songCount
        duration = album.duration
        isStarred = album.starred != nil
        created = album.created
        userRating = album.userRating ?? 0
        label = album.label
        cachedAt = Date()
    }

    /// Convert back to an Album value type for view compatibility.
    func toAlbum() -> Album {
        let album = Album(
            id: id,
            name: name,
            artist: artistName,
            artistId: artistId,
            coverArt: coverArtId,
            songCount: songCount,
            duration: duration,
            year: year,
            genre: genres.first,
            genres: genres.map { ItemGenre(name: $0) },
            starred: isStarred ? "true" : nil,
            created: created,
            userRating: userRating > 0 ? userRating : nil,
            song: nil,
            replayGain: nil,
            musicBrainzId: nil,
            recordLabels: label.map { [RecordLabel(name: $0)] }
        )
        return album
    }
}
