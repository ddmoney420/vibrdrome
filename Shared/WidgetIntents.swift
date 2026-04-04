import AppIntents
import Foundation

/// Commands the widget can send to the app via App Group UserDefaults
enum WidgetCommand: String {
    case togglePlayback
    case skipTrack
}

extension WidgetCommand {
    static let key = "widgetCommand"
    static let timestampKey = "widgetCommandTimestamp"

    func send() {
        guard let defaults = UserDefaults(suiteName: NowPlayingState.appGroupId) else { return }
        defaults.set(rawValue, forKey: Self.key)
        defaults.set(Date().timeIntervalSince1970, forKey: Self.timestampKey)
        defaults.synchronize()
    }

    static func consume() -> WidgetCommand? {
        guard let defaults = UserDefaults(suiteName: NowPlayingState.appGroupId),
              let raw = defaults.string(forKey: key),
              let command = WidgetCommand(rawValue: raw) else { return nil }
        // Only consume commands less than 5 seconds old
        let ts = defaults.double(forKey: timestampKey)
        guard Date().timeIntervalSince1970 - ts < 5 else {
            defaults.removeObject(forKey: key)
            return nil
        }
        defaults.removeObject(forKey: key)
        return command
    }
}

/// Toggle play/pause from widget — writes command to shared storage, opens app to execute
struct WidgetTogglePlaybackIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Toggle Playback"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WidgetCommand.togglePlayback.send()
        return .result()
    }
}

/// Skip track from widget
struct WidgetSkipTrackIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Skip Track"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WidgetCommand.skipTrack.send()
        return .result()
    }
}
