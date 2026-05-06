import Foundation
import SwiftData

@Model
final class CachedAlbum {
    #Index<CachedAlbum>([\.name], [\.artistId], [\.year], [\.isStarred], [\.userRating], [\.label])

    @Attribute(.unique) var id: String
    var name: String
    var artistName: String?
    var artistId: String?
    var coverArtId: String?
    var year: Int?
    var songCount: Int?
    var duration: Int?
    var isStarred: Bool = false
    var created: String?
    var userRating: Int = 0
    var label: String?
    var cachedAt: Date = Date()

    var songs: [CachedSong] = []
    @Relationship(deleteRule: .cascade, inverse: \AlbumGenre.album) var genreLinks: [AlbumGenre] = []

    var genres: [String] {
        genreLinks.map(\.name).sorted()
    }

    init(from album: Album) {
        self.id = album.id
        self.name = album.name
        self.artistName = album.artist
        self.artistId = album.artistId
        self.coverArtId = album.coverArt
        self.year = album.year
        self.songCount = album.songCount
        self.duration = album.duration
        self.isStarred = album.starred != nil
        self.created = album.created
        self.userRating = album.userRating ?? 0
        self.label = album.label
        self.genreLinks = album.allGenres.map { AlbumGenre(name: $0) }
    }

    /// Update existing record with fresh server data.
    func update(from album: Album) {
        name = album.name
        artistName = album.artist
        artistId = album.artistId
        coverArtId = album.coverArt
        year = album.year
        songCount = album.songCount
        duration = album.duration
        isStarred = album.starred != nil
        created = album.created
        userRating = album.userRating ?? 0
        label = album.label
        cachedAt = Date()
        let incoming = Set(album.allGenres)
        let existing = Set(genreLinks.map(\.name))
        for removed in existing.subtracting(incoming) {
            genreLinks.removeAll { $0.name == removed }
        }
        for added in incoming.subtracting(existing) {
            genreLinks.append(AlbumGenre(name: added))
        }
    }

    /// Convert back to an Album value type for view compatibility.
    func toAlbum() -> Album {
        let g = genres
        return Album(
            id: id,
            name: name,
            artist: artistName,
            artistId: artistId,
            coverArt: coverArtId,
            songCount: songCount,
            duration: duration,
            year: year,
            genre: g.first,
            genres: g.map { ItemGenre(name: $0) },
            starred: isStarred ? "true" : nil,
            created: created,
            userRating: userRating > 0 ? userRating : nil,
            song: nil,
            replayGain: nil,
            musicBrainzId: nil,
            recordLabels: label.map { [RecordLabel(name: $0)] }
        )
    }
}
