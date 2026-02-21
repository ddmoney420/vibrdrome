import Foundation
import SwiftData

@Model
final class ServerConfig {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = "My Server"
    var url: String
    var username: String
    var isActive: Bool = true
    var maxBitRateWifi: Int = 0
    var maxBitRateCellular: Int = 320
    var scrobblingEnabled: Bool = true
    var lastConnected: Date?

    init(url: String, username: String) {
        self.url = url
        self.username = username
    }
}
