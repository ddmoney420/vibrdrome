import Foundation
import SwiftData

nonisolated(unsafe) private let iso8601Album = ISO8601DateFormatter()

@Model
final class CachedAlbum {
    #Index<CachedAlbum>([\.name], [\.artistId], [\.year], [\.isStarred], [\.userRating], [\.label], [\.releaseType], [\.mood], [\.releaseCountry])

    @Attribute(.unique) var id: String
    var name: String
    var artistName: String?
    var artistId: String?
    var coverArtId: String?
    var year: Int?
    var songCount: Int?
    var duration: Int?
    var isStarred: Bool = false
    var starredAt: Date?
    var lastPlayed: Date?
    var created: String?
    var userRating: Int = 0
    var label: String?
    var cachedAt: Date = Date()

    // Extended metadata — stored so AlbumDetailView can seed the full header from disk.
    // These are optional with no default so SwiftData treats them as lightweight migrations.
    var replayGainAlbumGain: Double?
    var replayGainTrackGain: Double?
    var replayGainBaseGain: Double?
    var musicBrainzId: String?
    var mbzAlbumArtistId: String?
    var mbzReleaseGroupId: String?
    var mbzAlbumType: String?
    var mbzAlbumComment: String?
    var playCount: Int = 0
    var isCompilation: Bool = false

    // ND native API tag fields (album: true in mappings.yml)
    var catalogNum: String?
    var releaseType: String?
    var releaseCountry: String?
    var releaseStatus: String?
    var mood: String?
    var grouping: String?
    var mediaType: String?
    var sortAlbumName: String?
    var sortAlbumArtistName: String?
    var minYear: Int?
    var maxYear: Int?
    var edition: String?

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
        self.replayGainAlbumGain = album.replayGain?.albumGain
        self.replayGainTrackGain = album.replayGain?.trackGain
        self.replayGainBaseGain = album.replayGain?.baseGain
        self.musicBrainzId = album.musicBrainzId
        self.edition = album.version
        self.genreLinks = album.allGenres.map { AlbumGenre(name: $0) }
    }

    init(from ndAlbum: NDAlbum) {
        self.id = ndAlbum.id
        self.name = ndAlbum.name
        self.artistName = ndAlbum.albumArtist
        self.artistId = ndAlbum.albumArtistId
        self.coverArtId = ndAlbum.id
        self.year = ndAlbum.minYear ?? ndAlbum.year
        self.minYear = ndAlbum.minYear
        self.maxYear = ndAlbum.maxYear
        self.songCount = ndAlbum.songCount
        self.duration = ndAlbum.duration.map { Int($0) }
        self.isStarred = ndAlbum.starred ?? false
        if let at = ndAlbum.starredAt { self.starredAt = iso8601Album.date(from: at) }
        if let pd = ndAlbum.playDate { self.lastPlayed = iso8601Album.date(from: pd) }
        self.userRating = ndAlbum.rating ?? 0
        self.label = ndAlbum.recordLabel
        self.catalogNum = ndAlbum.catalogNum
        self.releaseType = ndAlbum.releaseType
        self.releaseCountry = ndAlbum.releaseCountry
        self.releaseStatus = ndAlbum.releaseStatus
        self.mood = ndAlbum.mood
        self.grouping = ndAlbum.grouping
        self.mediaType = ndAlbum.mediaType
        self.sortAlbumName = ndAlbum.sortAlbumName
        self.sortAlbumArtistName = ndAlbum.sortAlbumArtistName
        self.musicBrainzId = ndAlbum.mbzAlbumId
        self.mbzAlbumArtistId = ndAlbum.mbzAlbumArtistId
        self.mbzReleaseGroupId = ndAlbum.mbzReleaseGroupId
        self.mbzAlbumType = ndAlbum.mbzAlbumType
        self.mbzAlbumComment = ndAlbum.mbzAlbumComment
        self.playCount = ndAlbum.playCount ?? 0
        self.isCompilation = ndAlbum.compilation ?? false
        self.edition = ndAlbum.edition
        self.genreLinks = ndAlbum.allGenres.map { AlbumGenre(name: $0) }
    }

    func update(from ndAlbum: NDAlbum) {
        name = ndAlbum.name
        artistName = ndAlbum.albumArtist
        artistId = ndAlbum.albumArtistId
        coverArtId = ndAlbum.id
        year = ndAlbum.minYear ?? ndAlbum.year
        minYear = ndAlbum.minYear
        maxYear = ndAlbum.maxYear
        songCount = ndAlbum.songCount
        duration = ndAlbum.duration.map { Int($0) }
        isStarred = ndAlbum.starred ?? false
        starredAt = ndAlbum.starredAt.flatMap { iso8601Album.date(from: $0) }
        lastPlayed = ndAlbum.playDate.flatMap { iso8601Album.date(from: $0) }
        userRating = ndAlbum.rating ?? 0
        label = ndAlbum.recordLabel
        catalogNum = ndAlbum.catalogNum
        releaseType = ndAlbum.releaseType
        releaseCountry = ndAlbum.releaseCountry
        releaseStatus = ndAlbum.releaseStatus
        mood = ndAlbum.mood
        grouping = ndAlbum.grouping
        mediaType = ndAlbum.mediaType
        sortAlbumName = ndAlbum.sortAlbumName
        sortAlbumArtistName = ndAlbum.sortAlbumArtistName
        musicBrainzId = ndAlbum.mbzAlbumId
        mbzAlbumArtistId = ndAlbum.mbzAlbumArtistId
        mbzReleaseGroupId = ndAlbum.mbzReleaseGroupId
        mbzAlbumType = ndAlbum.mbzAlbumType
        mbzAlbumComment = ndAlbum.mbzAlbumComment
        playCount = ndAlbum.playCount ?? 0
        isCompilation = ndAlbum.compilation ?? false
        edition = ndAlbum.edition
        let incoming = Set(ndAlbum.allGenres)
        let existing = Set(genreLinks.map(\.name))
        for removed in existing.subtracting(incoming) {
            genreLinks.removeAll { $0.name == removed }
        }
        for added in incoming.subtracting(existing) {
            genreLinks.append(AlbumGenre(name: added))
        }
        cachedAt = Date()
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
        replayGainAlbumGain = album.replayGain?.albumGain
        replayGainTrackGain = album.replayGain?.trackGain
        replayGainBaseGain = album.replayGain?.baseGain
        musicBrainzId = album.musicBrainzId
        edition = album.version
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
        let album = Album(
            id: id,
            name: name,
            artist: artistName,
            artistId: artistId,
            artists: nil, displayArtist: nil,
            coverArt: coverArtId,
            songCount: songCount,
            duration: duration, playCount: nil,
            year: year,
            genre: g.first,
            genres: g.map { ItemGenre(name: $0) },
            starred: isStarred ? "true" : nil, played: nil,
            created: created,
            userRating: userRating > 0 ? userRating : nil,
            song: nil,
            replayGain: replayGainAlbumGain.map {
                ReplayGain(trackGain: replayGainTrackGain, albumGain: $0,
                           trackPeak: nil, albumPeak: nil, baseGain: replayGainBaseGain)
            },
            musicBrainzId: musicBrainzId,
            recordLabels: label.map { [RecordLabel(name: $0)] },
            version: edition, releaseTypes: nil, moods: nil, sortName: nil,
            originalReleaseDate: nil, releaseDate: nil,
            isCompilation: nil, explicitStatus: nil, discTitles: nil
        )
        return album
    }
}
