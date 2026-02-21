import Foundation
import SwiftData

@Model
final class PlayHistory {
    var songId: String
    var songTitle: String
    var artistName: String?
    var albumName: String?
    var coverArtId: String?
    var playedAt: Date = Date()
    var wasScrobbled: Bool = false

    init(songId: String, songTitle: String, artistName: String?, albumName: String? = nil, coverArtId: String? = nil) {
        self.songId = songId
        self.songTitle = songTitle
        self.artistName = artistName
        self.albumName = albumName
        self.coverArtId = coverArtId
    }

    init(from song: Song) {
        self.songId = song.id
        self.songTitle = song.title
        self.artistName = song.artist
        self.albumName = song.album
        self.coverArtId = song.coverArt
    }
}
