import Testing
import Foundation
@testable import Vibrdrome

struct WidgetCommandTests {

    @Test func togglePlaybackRawValue() {
        #expect(WidgetCommand.togglePlayback.rawValue == "togglePlayback")
    }

    @Test func skipTrackRawValue() {
        #expect(WidgetCommand.skipTrack.rawValue == "skipTrack")
    }

    @Test func commandFromRawValue() {
        #expect(WidgetCommand(rawValue: "togglePlayback") == .togglePlayback)
        #expect(WidgetCommand(rawValue: "skipTrack") == .skipTrack)
        #expect(WidgetCommand(rawValue: "invalid") == nil)
    }

    @Test func staleCommandIsIgnored() {
        // Write a command with an old timestamp
        let defaults = UserDefaults(suiteName: NowPlayingState.appGroupId)
        defaults?.set("togglePlayback", forKey: WidgetCommand.key)
        defaults?.set(Date().timeIntervalSince1970 - 10, forKey: WidgetCommand.timestampKey)

        let command = WidgetCommand.consume()
        #expect(command == nil)
    }
}
