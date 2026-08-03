import AVFoundation
import Foundation

/// One published Now Playing update, stamped with everything needed to reject a stale one.
///
/// Every field here exists because something can arrive late: a queue edit supersedes a generation,
/// a tail replacement supersedes a schedule, and a slow artwork fetch belongs to a play that may
/// already be over. Carrying the identity with the update is what lets a late arrival be discarded
/// instead of overwriting the current track.
struct GaplessNowPlayingUpdate: Sendable, Equatable {
    let songID: String
    let itemID: GaplessQueueItemID
    let playInstance: GaplessPlayInstanceID
    let queueGeneration: UInt64
    let tailGeneration: UInt64
    let scheduledStartFrame: AVAudioFramePosition
    let observedRenderFrame: AVAudioFramePosition
    let queueIndex: Int
    let elapsedSeconds: TimeInterval
    let isPlaying: Bool
}

/// Publishes Now Playing metadata **only** when a track actually becomes audible.
///
/// The old path updated metadata when an item was prepared or scheduled. On this architecture that
/// is a whole track early: the next track is decoded and handed to the player node long before it is
/// heard, so preparation-driven updates would show the wrong song on the lock screen for the rest of
/// the outgoing track. Every update here originates from a clock-observed boundary.
///
/// Existing production fields are preserved exactly — this changes *when* metadata is published,
/// never *what*. `NowPlayingManager` remains the single writer to `MPNowPlayingInfoCenter`.
@MainActor
final class GaplessNowPlayingBridge {
    /// How often elapsed time may be republished. Matches the existing app's periodic cadence and
    /// keeps `MPNowPlayingInfoCenter` from being flooded — it is a system-wide service, and a
    /// per-render-slice update would be thousands of writes a second.
    static let elapsedUpdateInterval: TimeInterval = 1.0

    /// The play instance currently on screen. Anything not matching it is stale by definition.
    private(set) var publishedInstance: GaplessPlayInstanceID?
    private(set) var lastUpdate: GaplessNowPlayingUpdate?
    private(set) var publishedUpdates: [GaplessNowPlayingUpdate] = []
    private(set) var rejectedStaleUpdates = 0
    private var lastElapsedPublish: Date?

    /// Injected so the bridge is testable without a live `MPNowPlayingInfoCenter`, and so the
    /// existing manager stays the only thing that talks to the system.
    var publishMetadata: ((GaplessNowPlayingUpdate) -> Void)?
    var publishElapsed: ((TimeInterval, Bool) -> Void)?
    var publishArtwork: ((String) -> Void)?

    /// Publish a track becoming audible. The only entry point that changes the displayed item.
    func trackBecameAudible(_ update: GaplessNowPlayingUpdate) {
        // A boundary from a superseded tail describes audio that will never be heard.
        if let current = lastUpdate,
           update.queueGeneration < current.queueGeneration
            || (update.queueGeneration == current.queueGeneration
                && update.tailGeneration < current.tailGeneration) {
            rejectedStaleUpdates += 1
            return
        }
        publishedInstance = update.playInstance
        lastUpdate = update
        publishedUpdates.append(update)
        lastElapsedPublish = nil
        publishMetadata?(update)
    }

    /// Publish elapsed time, rate-limited. Returns whether anything was published.
    ///
    /// The clock is already normalised to be monotonic internally, so the value handed to the system
    /// never exposes the backwards steps the hardware clock can take across a tail rebuild.
    @discardableResult
    func publishElapsed(seconds: TimeInterval, isPlaying: Bool, now: Date = Date()) -> Bool {
        if let last = lastElapsedPublish,
           now.timeIntervalSince(last) < Self.elapsedUpdateInterval {
            return false
        }
        lastElapsedPublish = now
        publishElapsed?(max(0, seconds), isPlaying)
        return true
    }

    /// Force an immediate elapsed publish — used for pause, resume and seek, where waiting for the
    /// next tick would leave the lock screen visibly wrong.
    func publishElapsedImmediately(seconds: TimeInterval, isPlaying: Bool) {
        lastElapsedPublish = Date()
        publishElapsed?(max(0, seconds), isPlaying)
    }

    /// Publish artwork for a specific play instance.
    ///
    /// Artwork is often fetched ahead of the boundary and can complete after the user has already
    /// moved on. Keying on play instance — not song ID — is what makes that safe: the same song in
    /// two queue slots, or replayed under Repeat One, produces different instances.
    @discardableResult
    func publishArtwork(songID: String, for instance: GaplessPlayInstanceID) -> Bool {
        guard instance == publishedInstance else {
            rejectedStaleUpdates += 1
            return false
        }
        publishArtwork?(songID)
        return true
    }

    /// Clear on stop, so nothing later is accepted against a finished play.
    func reset() {
        publishedInstance = nil
        lastUpdate = nil
        lastElapsedPublish = nil
    }
}
