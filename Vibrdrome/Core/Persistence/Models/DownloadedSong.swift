import Foundation
import SwiftData

@Model
final class DownloadedSong {
    @Attribute(.unique) var songId: String
    var songTitle: String = ""
    var artistName: String?
    var albumName: String?
    var coverArtId: String?
    var duration: Int?
    var localFilePath: String = ""
    var fileSize: Int64 = 0
    var downloadedAt: Date = Date()
    var lastAccessedAt: Date?
    var isComplete: Bool = false
    var song: CachedSong?
    var category: String = ""

    init(songId: String, songTitle: String, artistName: String?, albumName: String?,
         coverArtId: String?, duration: Int?, localFilePath: String, category: String) {
        self.songId = songId
        self.songTitle = songTitle
        self.artistName = artistName
        self.albumName = albumName
        self.coverArtId = coverArtId
        self.duration = duration
        self.localFilePath = localFilePath
        self.category = category
    }

    convenience init(from song: Song, localFilePath: String) {
        self.init(
            songId: song.id,
            songTitle: song.title,
            artistName: song.artist,
            albumName: song.album,
            coverArtId: song.coverArt,
            duration: song.duration,
            localFilePath: localFilePath,
            category: ""
        )
    }

    convenience init(from song: Song, localFilePath: String, category: String) {
        self.init(
            songId: song.id,
            songTitle: song.title,
            artistName: song.artist,
            albumName: song.album,
            coverArtId: song.coverArt,
            duration: song.duration,
            localFilePath: localFilePath,
            category: category
        )
    }
    
    func toSong() -> Song {
        Song(
            id: songId, parent: nil, title: songTitle,
            album: albumName, artist: artistName,
            albumArtist: nil, albumId: nil, artistId: nil,
            track: nil, year: nil, genre: nil,
            coverArt: coverArtId, size: nil,
            contentType: nil, suffix: nil,
            duration: duration, bitRate: nil,
            path: nil, discNumber: nil, created: nil,
            starred: nil, userRating: nil, bpm: nil,
            replayGain: nil, musicBrainzId: nil
        )
    }
}
