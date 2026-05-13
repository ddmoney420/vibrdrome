import Foundation
import SwiftData

nonisolated(unsafe) private let iso8601 = ISO8601DateFormatter()

@Model
final class CachedSong {
    #Index<CachedSong>([\.title], [\.albumId], [\.artistId], [\.genre], [\.isStarred], [\.lastPlayed])

    @Attribute(.unique) var id: String
    var title: String
    var artist: String?
    var albumArtist: String?
    /// Comma-joined OpenSubsonic `artists` names. When present, used instead of `artist` for display.
    var displayArtistOverride: String?
    var albumName: String?
    var albumId: String?
    var artistId: String?
    var coverArtId: String?
    var track: Int?
    var discNumber: Int?
    var year: Int?
    var genre: String?
    var genres: [String] = []
    var duration: Int?
    var bitRate: Int?
    var bitDepth: Int?
    var samplingRate: Int?
    var channels: Int?
    var comment: String?
    var suffix: String?
    var contentType: String?
    var size: Int?
    var bpm: Int?
    var hasCoverArt: Bool = false
    var isCompilation: Bool = false
    var dateAdded: Date?
    var mbzRecordingId: String?
    var mbzAlbumId: String?
    var mbzArtistId: String?
    var mbzAlbumArtistId: String?
    var rgTrackGain: Double?
    var rgTrackPeak: Double?
    var rgAlbumGain: Double?
    var rgAlbumPeak: Double?
    var isStarred: Bool = false
    var starredAt: Date?
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
        if let names = song.artists?.map(\.name), !names.isEmpty {
            self.displayArtistOverride = names.joined(separator: ", ")
        }
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
        self.dateAdded = song.created.flatMap { iso8601.date(from: $0) }
        self.mbzRecordingId = song.musicBrainzId
        self.isStarred = song.starred != nil
        self.rgTrackGain = song.replayGain?.trackGain
        self.rgTrackPeak = song.replayGain?.trackPeak
        self.rgAlbumGain = song.replayGain?.albumGain
        self.rgAlbumPeak = song.replayGain?.albumPeak
    }

    convenience init(from ndSong: NDSong) {
        self.init(from: Song(
            id: ndSong.id, title: ndSong.title, album: ndSong.album,
            artist: ndSong.artist, albumArtist: ndSong.albumArtist,
            albumId: ndSong.albumId, artistId: ndSong.artistId,
            track: ndSong.trackNumber, year: ndSong.year, genre: ndSong.allGenres.first,
            coverArt: ndSong.id,
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
        self.mbzAlbumId = ndSong.mbzAlbumId
        self.mbzArtistId = ndSong.mbzArtistId
        self.mbzAlbumArtistId = ndSong.mbzAlbumArtistId
        self.genres = ndSong.allGenres
        self.playCount = ndSong.playCount ?? 0
        self.rgTrackGain = ndSong.rgTrackGain
        self.rgTrackPeak = ndSong.rgTrackPeak
        self.rgAlbumGain = ndSong.rgAlbumGain
        self.rgAlbumPeak = ndSong.rgAlbumPeak
        self.displayArtistOverride = ndSong.participantArtistOverride
        if let playDate = ndSong.playDate { self.lastPlayed = iso8601.date(from: playDate) }
        if let at = ndSong.starredAt { self.starredAt = iso8601.date(from: at) }
    }

    func update(from ndSong: NDSong) {
        title = ndSong.title
        artist = ndSong.artist
        albumArtist = ndSong.albumArtist
        albumName = ndSong.album
        albumId = ndSong.albumId
        artistId = ndSong.artistId
        coverArtId = ndSong.id
        track = ndSong.trackNumber
        discNumber = ndSong.discNumber
        year = ndSong.year
        genre = ndSong.allGenres.first
        genres = ndSong.allGenres
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
        dateAdded = ndSong.createdAt.flatMap { iso8601.date(from: $0) }
        mbzRecordingId = ndSong.mbzReleaseTrackId
        mbzArtistId = ndSong.mbzArtistId
        mbzAlbumArtistId = ndSong.mbzAlbumArtistId
        mbzAlbumId = ndSong.mbzAlbumId
        isStarred = ndSong.starred ?? false
        if let at = ndSong.starredAt { starredAt = iso8601.date(from: at) } else { starredAt = nil }
        rating = ndSong.rating ?? 0
        playCount = ndSong.playCount ?? 0
        rgTrackGain = ndSong.rgTrackGain
        rgTrackPeak = ndSong.rgTrackPeak
        rgAlbumGain = ndSong.rgAlbumGain
        rgAlbumPeak = ndSong.rgAlbumPeak
        displayArtistOverride = ndSong.participantArtistOverride
        if let playDate = ndSong.playDate { lastPlayed = iso8601.date(from: playDate) }
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
            displayArtistOverride: displayArtistOverride,
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
            replayGain: rgTrackGain.map {
                ReplayGain(trackGain: $0, albumGain: rgAlbumGain,
                           trackPeak: rgTrackPeak, albumPeak: rgAlbumPeak, baseGain: nil)
            },
            musicBrainzId: mbzRecordingId
        )
    }
}
