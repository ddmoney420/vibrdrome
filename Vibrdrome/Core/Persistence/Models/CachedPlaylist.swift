import Foundation
import SwiftData

@Model
final class CachedPlaylist {
    @Attribute(.unique) var id: String
    var name: String
    var songCount: Int?
    var duration: Int?
    var coverArtId: String?
    var owner: String?
    var isPublic: Bool = false
    var changed: String?
    var cachedAt: Date = Date()

    @Relationship(deleteRule: .cascade) var entries: [CachedPlaylistEntry] = []

    init(from playlist: Playlist) {
        self.id = playlist.id
        self.name = playlist.name
        self.songCount = playlist.songCount
        self.duration = playlist.duration
        self.coverArtId = playlist.coverArt
        self.owner = playlist.owner
        self.isPublic = playlist.isPublic ?? false
        self.changed = playlist.changed
    }

    func toPlaylist() -> Playlist {
        Playlist(
            id: id,
            name: name,
            songCount: songCount,
            duration: duration,
            created: nil,
            changed: changed,
            coverArt: coverArtId,
            owner: owner,
            isPublic: isPublic,
            entry: nil
        )
    }
}
