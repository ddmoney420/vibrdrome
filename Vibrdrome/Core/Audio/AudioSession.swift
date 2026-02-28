import AVFoundation
import Foundation

final class AudioSessionManager: @unchecked Sendable {
    static let shared = AudioSessionManager()
    private var isConfigured = false

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
                AudioEngine.shared.pause()
            case .ended:
                // Reactivate audio session — iOS deactivates it during interruptions
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("Failed to reactivate audio session: \(error)")
                }
                if shouldResume {
                    AudioEngine.shared.resume()
                }
            @unknown default:
                break
            }
        }
    }

    private static func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        if reason == .oldDeviceUnavailable {
            Task { @MainActor in
                AudioEngine.shared.pause()
            }
        }
    }
    #endif
}
