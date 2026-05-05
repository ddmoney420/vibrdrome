import Foundation
import SwiftData

@Model
final class CachedSong {
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
    var bitDepth: Int?
    var samplingRate: Int?
    var comment: String?
    var suffix: String?
    var contentType: String?
    var size: Int?
    var bpm: Int?
    var channels: Int?
    var hasCoverArt: Bool = false
    var isCompilation: Bool = false
    var dateAdded: Date?
    var mbzRecordingId: String?
    var mbzArtistId: String?
    var mbzAlbumArtistId: String?
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
        self.bitDepth = song.bitDepth
        self.samplingRate = song.samplingRate
        self.comment = song.comment
        self.suffix = song.suffix
        self.contentType = song.contentType
        self.size = song.size
        self.bpm = song.bpm
        self.dateAdded = song.created.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.mbzRecordingId = song.musicBrainzId
        self.isStarred = song.starred != nil
    }

    convenience init(from ndSong: NDSong) {
        self.init(from: Song(
            id: ndSong.id, title: ndSong.title, album: ndSong.album,
            artist: ndSong.artist, albumArtist: ndSong.albumArtist,
            albumId: ndSong.albumId, artistId: ndSong.artistId,
            track: ndSong.trackNumber, year: ndSong.year, genre: ndSong.genre,
            size: ndSong.size, suffix: ndSong.suffix,
            duration: ndSong.duration.map { Int($0) }, bitRate: ndSong.bitRate,
            bitDepth: ndSong.bitDepth, samplingRate: ndSong.sampleRate, comment: ndSong.comment,
            discNumber: ndSong.discNumber, created: ndSong.createdAt,
            starred: ndSong.starred == true ? "true" : nil,
            userRating: ndSong.rating, bpm: ndSong.bpm,
            musicBrainzId: ndSong.mbzReleaseTrackId
        ))
        self.channels = ndSong.channels
        self.hasCoverArt = ndSong.hasCoverArt ?? false
        self.isCompilation = ndSong.compilation ?? false
        self.mbzArtistId = ndSong.mbzArtistId
        self.mbzAlbumArtistId = ndSong.mbzAlbumArtistId
        self.playCount = ndSong.playCount ?? 0
        if let playDate = ndSong.playDate {
            self.lastPlayed = ISO8601DateFormatter().date(from: playDate)
        }
    }

    func update(from ndSong: NDSong) {
        title = ndSong.title
        artist = ndSong.artist
        albumArtist = ndSong.albumArtist
        albumName = ndSong.album
        albumId = ndSong.albumId
        artistId = ndSong.artistId
        track = ndSong.trackNumber
        discNumber = ndSong.discNumber
        year = ndSong.year
        genre = ndSong.genre
        duration = ndSong.duration.map { Int($0) }
        bitRate = ndSong.bitRate
        bitDepth = ndSong.bitDepth
        samplingRate = ndSong.sampleRate
        channels = ndSong.channels
        comment = ndSong.comment
        suffix = ndSong.suffix
        size = ndSong.size
        bpm = ndSong.bpm
        hasCoverArt = ndSong.hasCoverArt ?? false
        isCompilation = ndSong.compilation ?? false
        dateAdded = ndSong.createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        mbzRecordingId = ndSong.mbzReleaseTrackId
        mbzArtistId = ndSong.mbzArtistId
        mbzAlbumArtistId = ndSong.mbzAlbumArtistId
        isStarred = ndSong.starred ?? false
        rating = ndSong.rating ?? 0
        playCount = ndSong.playCount ?? 0
        if let playDate = ndSong.playDate {
            lastPlayed = ISO8601DateFormatter().date(from: playDate)
        }
        cachedAt = Date()
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
            bitDepth: bitDepth,
            samplingRate: samplingRate,
            comment: comment,
            path: nil,
            discNumber: discNumber,
            created: nil,
            starred: isStarred ? "true" : nil,
            userRating: rating,
            bpm: bpm,
            replayGain: nil,
            musicBrainzId: mbzRecordingId
        )
    }
}
