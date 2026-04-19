import AVFoundation
import Foundation
import os.log

private let sessionLog = Logger(subsystem: "com.vibrdrome.app", category: "AudioSession")

final class AudioSessionManager: @unchecked Sendable {
    static let shared = AudioSessionManager()
    private var isConfigured = false

    /// Playback state captured at interruption `.began` so `.ended` can resume
    /// even when iOS omits `AVAudioSessionInterruptionOptions.shouldResume`.
    /// Siri / Messages announcements on CarPlay often drop that flag, which
    /// leaves the user stuck paused after returning to CarPlay.
    @MainActor private static var wasPlayingBeforeInterruption = false

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { notification in
            Self.handleInterruption(notification)
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { notification in
            Self.handleRouteChange(notification)
        }
        #endif
    }

    #if os(iOS)
    private static func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        // Extract values before crossing isolation boundary
        let shouldResume: Bool
        if type == .ended,
           let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
            shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
        } else {
            shouldResume = false
        }

        Task { @MainActor in
            switch type {
            case .began:
                wasPlayingBeforeInterruption = AudioEngine.shared.isPlaying
                sessionLog.info("Interruption began: wasPlaying=\(wasPlayingBeforeInterruption)")
                AudioEngine.shared.pause()
            case .ended:
                let shouldRestore = shouldResume || wasPlayingBeforeInterruption
                sessionLog.info("Interruption ended: shouldResume=\(shouldResume) wasPlaying=\(wasPlayingBeforeInterruption) -> restore=\(shouldRestore)")
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    sessionLog.error("Failed to reactivate audio session: \(error.localizedDescription)")
                }
                if shouldRestore {
                    AudioEngine.shared.resume()
                }
                wasPlayingBeforeInterruption = false
            @unknown default:
                break
            }
        }
    }

    private static func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        let session = AVAudioSession.sharedInstance()
        let currentOutputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        sessionLog.info("RouteChange: reason=\(reasonString(reason)) currentOutputs=[\(currentOutputs, privacy: .public)]")

        // Only pause when the route change actually leaves us with no audio outputs.
        // CarPlay and Bluetooth connections can fire `.oldDeviceUnavailable` during
        // transient hiccups even though a valid output remains — pausing in that
        // case is what produces the "random pause" users see on CarPlay.
        if reason == .oldDeviceUnavailable && session.currentRoute.outputs.isEmpty {
            sessionLog.info("Pausing: old device unavailable with no remaining outputs")
            Task { @MainActor in
                AudioEngine.shared.pause()
            }
        }
    }

    private static func reasonString(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        @unknown default: return "other(\(reason.rawValue))"
        }
    }
    #endif
}
