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
