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

    init(songId: String, songTitle: String, artistName: String?, albumName: String?,
         coverArtId: String?, duration: Int?, localFilePath: String) {
        self.songId = songId
        self.songTitle = songTitle
        self.artistName = artistName
        self.albumName = albumName
        self.coverArtId = coverArtId
        self.duration = duration
        self.localFilePath = localFilePath
    }

    convenience init(from song: Song, localFilePath: String) {
        self.init(
            songId: song.id,
            songTitle: song.title,
            artistName: song.artist,
            albumName: song.album,
            coverArtId: song.coverArt,
            duration: song.duration,
            localFilePath: localFilePath
        )
    }
}
