import Foundation
import SwiftData

@Model
final class CachedPlaylistEntry {
    var songId: String
    var order: Int

    @Relationship(inverse: \CachedPlaylist.entries) var playlist: CachedPlaylist?

    init(songId: String, order: Int) {
        self.songId = songId
        self.order = order
    }
}
