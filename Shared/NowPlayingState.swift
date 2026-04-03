import Foundation

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
        guard let defaults = Self.shared,
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    static func load() -> NowPlayingState? {
        guard let defaults = shared,
              let data = defaults.data(forKey: userDefaultsKey),
              let state = try? JSONDecoder().decode(NowPlayingState.self, from: data) else {
            return nil
        }
        return state
    }

    static func clear() {
        shared?.removeObject(forKey: userDefaultsKey)
    }
}
