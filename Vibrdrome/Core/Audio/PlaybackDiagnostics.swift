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

    /// Append one event. Bounded to the last 40. Callers pass only closed/sanitized values — never
    /// URLs, tokens, or credentials.
    static func record(_ event: String) {
        counter += 1
        lines.append("#\(counter) \(event)")
        if lines.count > 40 { lines.removeFirst(lines.count - 40) }
    }

    static var snapshot: [String] { lines }
}
