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

    /// The playback façade interruption handling drives.
    ///
    /// Routed rather than reaching `AudioEngine.shared` directly: an interruption must pause
    /// whichever backend owns the session, and reaching the engine paused a quiesced player while
    /// the persistent engine kept playing.
    @MainActor
    static var playback: any ApplicationPlaybackControlling {
        #if DEBUG
        if let override = playbackOverrideForTesting { return override }
        #endif
        return ApplicationPlayback.shared
    }

    #if DEBUG
    /// Test seam: lets a test point interruption handling at its own router rather than the
    /// process-wide composition point.
    @MainActor static var playbackOverrideForTesting: (any ApplicationPlaybackControlling)?
    #endif

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // `.longFormAudio` is Apple's recommended route sharing policy
            // for music apps. It signals to iOS that this is a long-form
            // audio app (vs game audio / VoIP / etc.), which is one of the
            // signals iOS uses when deciding to promote an app to the
            // system "Now Playing" app -- the status that surfaces the
            // Now Playing button at the top right of CarPlay and the
            // lock-screen widget. Without it, iOS treats the session as
            // generic playback and the promotion can fail on cold launch.
            // Issue #45.
            try session.setCategory(
                .playback, mode: .default, policy: .longFormAudio, options: []
            )
            // Do NOT activate the session here. Configuring the category at launch
            // is harmless, but activating it interrupts other apps' audio (e.g.
            // Spotify) on cold launch even though the user hasn't pressed Play (#134).
            // Activation happens only when playback actually starts or resumes
            // (`AudioEngine.play(song:)` / `resume()`), and is re-established by the
            // interruption `.ended` handler below. #45 Now-Playing still surfaces
            // because `preloadCurrentSong()` loads the AVPlayerItem + sets
            // NowPlayingInfoCenter — activation is not required for that.
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

        // Media services (mediaserverd) can reset — every AVPlayer/AVAudioEngine object is then
        // invalidated and new items fail with AVError.mediaServicesWereReset (-11819). Observe it so
        // the router can discard the orphaned objects and recover (Apple QA1749). Registered once at
        // launch; observers survive the reset, so this does not need re-registering.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { _ in
            Self.handleMediaServicesReset()
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
                // Through the façade, not the engine: an interruption must pause whichever
                // backend owns the session. Reaching AudioEngine directly paused a quiesced
                // player while the persistent engine kept playing.
                wasPlayingBeforeInterruption = playback.isPlaying
                sessionLog.info("Interruption began: wasPlaying=\(wasPlayingBeforeInterruption)")
                playback.pause()
            case .ended:
                let shouldRestore = shouldResume || wasPlayingBeforeInterruption
                sessionLog.info("Interruption ended: shouldResume=\(shouldResume) wasPlaying=\(wasPlayingBeforeInterruption) -> restore=\(shouldRestore)")
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    AudioSessionDiagnostics.record(.activate, source: .interruptionEnded, error: nil)
                } catch {
                    AudioSessionDiagnostics.record(.activate, source: .interruptionEnded, error: error)
                    sessionLog.error("Failed to reactivate audio session: \(error.localizedDescription)")
                }
                if shouldRestore {
                    // Resume, never re-play: this continues the existing session on its current
                    // owner and must not start a new one or re-run selection.
                    playback.resume()
                }
                wasPlayingBeforeInterruption = false
            @unknown default:
                break
            }
        }
    }

    private static func handleMediaServicesReset() {
        sessionLog.error("Media services were reset — routing recovery through the playback façade")
        // Through the façade so recovery dispatches by ownership: the router discards the orphaned
        // persistent engine and hands the legacy path its own reset. Serialized on the main actor.
        Task { @MainActor in
            playback.handleMediaServicesReset()
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
                playback.pause()
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
