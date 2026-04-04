#if os(iOS)
import ActivityKit
import Foundation

struct NowPlayingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var isPlaying: Bool
    }

    var albumName: String
}
#endif
