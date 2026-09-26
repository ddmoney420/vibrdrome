import AVFoundation
import Foundation

/// DEBUG-adjacent playback diagnostics for the CarPlay-J / beta-OFF silent-Legacy investigation.
///
/// Observational only — nothing here changes playback, routing, ownership or audio-session
/// behavior. Values are written by existing call sites and read by the Debug export, which is the
/// one device channel that works on this iOS/host pairing (os_log streaming does not).
@MainActor
enum AudioSessionDiagnostics {
    enum Operation: String { case activate, deactivate }
    /// Which existing call site performed the operation — never a new activation path.
    enum Source: String {
        case legacyPlay, legacyResume, radio, interruptionEnded
        case persistentStart, persistentTeardown, other
    }
    /// The app's *believed* session state. There is no public `AVAudioSession.isActive`, so this is
    /// the app's own record, advanced only after a successful `setActive`.
    enum BelievedState: String { case active, inactive, unknown }

    private(set) static var lastOperation: Operation?
    private(set) static var lastSource: Source?
    private(set) static var lastResult = "none"
    private(set) static var believedState: BelievedState = .unknown

    /// Record an audio-session operation and its result. The caller performs the real `setActive`;
    /// this only observes. Believed state advances only on success — a throw leaves it unchanged so
    /// a failed activation cannot masquerade as active.
    static func record(_ operation: Operation, source: Source, error: Error?) {
        lastOperation = operation
        lastSource = source
        if let error {
            lastResult = "error: \(error._domain) code \(error._code)"
            return
        }
        lastResult = "success"
        believedState = operation == .activate ? .active : .inactive
    }
}

/// A bounded, sanitized event log for playback routing and beta-flag transitions, mirrored into the
/// Debug export. Same pullable-file spirit as the visualizer trace: os_log does not stream on this
/// device, so the events must live somewhere `devicectl` can retrieve.
@MainActor
enum PlaybackEventLog {
    private static var lines: [String] = []
    private static var counter = 0
    private static let maxLines = 80

    /// Wall-clock stamp so durations between events (e.g. item insert → readyToPlay = the startup
    /// pause) are computable straight from the log.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// Append one timestamped event. Bounded to the last `maxLines`. Callers pass only
    /// closed/sanitized values — never URLs, tokens, or credentials.
    static func record(_ event: String) {
        counter += 1
        lines.append("#\(counter) \(timeFormatter.string(from: Date())) \(event)")
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }

    static var snapshot: [String] { lines }
}

/// Sanitized one-word descriptions of AVPlayer state for the pullable event log. Carry no URLs,
/// tokens or credentials — just the closed-set status of the transport.
enum PlaybackStateDescribe {
    static func timeControl(_ status: AVPlayer.TimeControlStatus?) -> String {
        switch status {
        case .paused: "paused"
        case .waitingToPlayAtSpecifiedRate: "waiting"
        case .playing: "playing"
        case nil: "nil"
        @unknown default: "unknown"
        }
    }

    static func itemStatus(_ status: AVPlayerItem.Status?) -> String {
        switch status {
        case .unknown: "unknown"
        case .readyToPlay: "ready"
        case .failed: "failed"
        case nil: "nil"
        @unknown default: "unknown"
        }
    }

    /// A sanitized snapshot of a queue player's transport for one log line.
    @MainActor
    static func snapshot(_ player: AVQueuePlayer?) -> String {
        guard let player else { return "player=nil" }
        let itemError = player.currentItem?.error.map { "\($0._domain)#\($0._code)" } ?? "none"
        return "rate=\(player.rate) tc=\(timeControl(player.timeControlStatus)) "
            + "item=\(itemStatus(player.currentItem?.status)) itemErr=\(itemError) "
            + "queued=\(player.items().count)"
    }
}
