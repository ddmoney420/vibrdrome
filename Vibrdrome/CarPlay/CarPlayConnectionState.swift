#if os(iOS)
import Foundation

/// Cached CarPlay connection state for the Debug screen — so device QA can confirm the app's scene
/// delegate actually observed a head-unit connect/disconnect, independent of what the car shows.
///
/// **Cached application state, never a live query.** The Debug screen reads these stored values; it
/// does not reach into the audio domain or the scene. Deliberately NOT `CARPLAY_ENABLED`-gated so
/// the Debug screen compiles and reads it in every build; only the scene delegate (which is gated)
/// ever writes it.
@MainActor
final class CarPlayConnectionState {
    static let shared = CarPlayConnectionState()

    private(set) var isConnected = false
    /// Human-readable last transition, e.g. "connected" / "disconnected", for the Debug row.
    private(set) var lastEvent = "never"
    private(set) var connectCount = 0

    func recordConnect() {
        isConnected = true
        lastEvent = "connected"
        connectCount += 1
    }

    func recordDisconnect() {
        isConnected = false
        lastEvent = "disconnected"
    }
}
#endif
