import Foundation
import SwiftData

@Model
final class SavedQueue {
    @Attribute(.unique) var id: String = "current"
    var songIds: [String] = []
    var currentIndex: Int = 0
    var currentTime: Double = 0
    var shuffleEnabled: Bool = false
    var repeatMode: String = "off"
    var savedAt: Date = Date()

    init(
        id: String = "current",
        songIds: [String] = [],
        currentIndex: Int = 0,
        currentTime: Double = 0,
        shuffleEnabled: Bool = false,
        repeatMode: String = "off",
        savedAt: Date = Date()
    ) {
        self.id = id
        self.songIds = songIds
        self.currentIndex = currentIndex
        self.currentTime = currentTime
        self.shuffleEnabled = shuffleEnabled
        self.repeatMode = repeatMode
        self.savedAt = savedAt
    }
}
