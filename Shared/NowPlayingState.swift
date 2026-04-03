import Foundation
import os.log

private let widgetLog = Logger(subsystem: "com.vibrdrome.app", category: "Widget")

/// Shared now-playing state between the main app and widget extension.
/// Stored in the App Group shared UserDefaults.
struct NowPlayingState: Codable {
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let coverArtId: String?
    let serverURL: String?
    let timestamp: Date

    static let appGroupId = "group.com.vibrdrome.app"
    static let userDefaultsKey = "nowPlayingState"

    static var shared: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    func save() {
        guard let defaults = Self.shared else {
            widgetLog.error("App Group UserDefaults is nil — group not configured?")
            return
        }
        guard let data = try? JSONEncoder().encode(self) else {
            widgetLog.error("Failed to encode NowPlayingState")
            return
        }
        defaults.set(data, forKey: Self.userDefaultsKey)
        defaults.synchronize()
        widgetLog.info("Widget state saved: \(self.title) by \(self.artist)")
    }

    static func load() -> NowPlayingState? {
        guard let defaults = shared else {
            widgetLog.error("App Group UserDefaults is nil in load()")
            return nil
        }
        guard let data = defaults.data(forKey: userDefaultsKey) else {
            widgetLog.info("No widget state data found")
            return nil
        }
        guard let state = try? JSONDecoder().decode(NowPlayingState.self, from: data) else {
            widgetLog.error("Failed to decode NowPlayingState")
            return nil
        }
        widgetLog.info("Widget state loaded: \(state.title)")
        return state
    }

    static func clear() {
        shared?.removeObject(forKey: userDefaultsKey)
    }
}
