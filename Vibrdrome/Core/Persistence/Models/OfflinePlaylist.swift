import Foundation
import SwiftData

@Model
final class OfflinePlaylist {
    @Attribute(.unique) var compositeKey: String = ""
    var serverId: String = ""
    var playlistId: String = ""
    var playlistName: String = ""
    var coverArtId: String?
    var songIds: [String] = []
    var cachedAt: Date = Date()
    var totalSongs: Int = 0

    init(serverId: String, playlistId: String, playlistName: String,
         coverArtId: String?, songIds: [String]) {
        self.compositeKey = "\(serverId)_\(playlistId)"
        self.serverId = serverId
        self.playlistId = playlistId
        self.playlistName = playlistName
        self.coverArtId = coverArtId
        self.songIds = songIds
        self.totalSongs = songIds.count
    }
}
