import Foundation
import SwiftData

@Model
final class PendingAction {
    var serverId: String = ""
    var actionType: String = ""
    var targetId: String = ""
    var createdAt: Date = Date()
    var retryCount: Int = 0
    var submission: Bool = true
    /// "pending", "failed"
    var status: String = "pending"

    // Song metadata for external scrobble services (ListenBrainz, Last.fm)
    var songTitle: String?
    var songArtist: String?
    var songAlbum: String?
    var songAlbumArtist: String?
    var songDuration: Int?

    init(serverId: String, actionType: String, targetId: String, submission: Bool = true) {
        self.serverId = serverId
        self.actionType = actionType
        self.targetId = targetId
        self.submission = submission
        self.createdAt = Date()
        self.retryCount = 0
        self.status = "pending"
    }
}
