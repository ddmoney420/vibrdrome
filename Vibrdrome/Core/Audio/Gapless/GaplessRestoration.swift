import AVFoundation
import Foundation

/// A persisted playback session, as the app actually stores it.
///
/// Mapped from `SavedQueue` (SwiftData) plus the settings that live in `UserDefaults`. Only the
/// first group is per-session state; the second is global user settings that are restored simply by
/// being read, and are listed here so the split is explicit rather than implied.
///
/// **Authoritative (persisted per session):** song IDs, current index, elapsed seconds, repeat mode,
/// shuffle flag, radio mode.
/// **Global settings (UserDefaults, not per-session):** ReplayGain mode/preamp/fallback, EQ enabled
/// and gains, preload count.
/// **Derived, never persisted:** queue-slot identity, play instance, tail generation, scheduled
/// frames, audible frames, prepared/decoded state.
/// **Deliberately not persisted:** playback state (restoration is always paused — `SavedQueue` has
/// no playing field), shuffle history, in-flight scrobble eligibility, artwork, and — importantly —
/// stream URLs, auth tokens and expiring transcode URLs, none of which are stored.
struct GaplessRestorationState: Sendable, Equatable {
    let songIDs: [String]
    let currentIndex: Int
    let elapsedSeconds: TimeInterval
    let repeatMode: RepeatMode
    let shuffleEnabled: Bool

    /// Parse a persisted repeat value. An unknown string restores to `off` rather than failing the
    /// whole restoration for one bad field.
    static func repeatMode(fromPersisted raw: String) -> RepeatMode {
        switch raw {
        case "all": return .all
        case "one": return .one
        default: return .off
        }
    }
}

/// What a restoration attempt produced.
enum GaplessRestorationOutcome: Equatable, Sendable {
    /// Usable: queue and a valid current slot, with the position clamped into range.
    case restored(elapsedSeconds: TimeInterval, currentIndex: Int)
    /// Queue is usable but the persisted current slot was not; playback starts at the first item.
    case restoredWithCorrectedIndex(elapsedSeconds: TimeInterval, currentIndex: Int, reason: String)
    /// Nothing usable. Metadata may still be shown, but there is nothing to play.
    case unusable(reason: String)
}

/// Validates and restores a persisted session onto the engine, passively.
///
/// **Nothing here activates the audio session.** Restoration is exactly the situation the Build 60
/// cold-launch fix exists for: the app comes back, shows what was playing, and must not interrupt
/// whatever the user is currently listening to in another app. Activation is deferred to an explicit
/// Play, and that separation is asserted rather than assumed.
@MainActor
final class GaplessRestorationCoordinator {
    /// Distinguishes one restoration attempt from the next.
    ///
    /// Needed separately from the queue generation because a restoration can be superseded *before*
    /// it ever reaches the queue: the user taps an album while the restored track is still being
    /// prepared. Work carrying an old restoration generation is discarded on arrival.
    private(set) var restorationGeneration: UInt64 = 0
    private(set) var lastOutcome: GaplessRestorationOutcome?
    private(set) var discardedStaleRestorations = 0

    private let session: GaplessPlaybackSession

    init(session: GaplessPlaybackSession) {
        self.session = session
    }

    /// Load a persisted session into the queue. Passive: no session activation, no engine start.
    ///
    /// The restored position is clamped rather than trusted — a persisted duration can disagree with
    /// the file's real one (a re-encode, a different transcode), and a position past the end would
    /// otherwise schedule a zero-length segment.
    @discardableResult
    func restorePassively(_ state: GaplessRestorationState,
                          durations: [String: TimeInterval] = [:]) -> GaplessRestorationOutcome {
        restorationGeneration += 1

        guard !state.songIDs.isEmpty else {
            lastOutcome = .unusable(reason: "empty queue")
            return lastOutcome!
        }

        var index = state.currentIndex
        var correction: String?
        if !state.songIDs.indices.contains(index) {
            correction = "current index \(state.currentIndex) out of bounds for \(state.songIDs.count) items"
            index = 0
        }

        session.replaceQueue(songIDs: state.songIDs, startIndex: index)
        session.setRepeatMode(state.repeatMode)
        session.setShuffleEnabled(state.shuffleEnabled)
        for (songID, duration) in durations { session.songDurations[songID] = duration }
        // Restoration always comes back paused: the app never persists a playing state, so there is
        // no "was playing" to honour and nothing may start on its own.
        session.pause()

        let duration = durations[state.songIDs[index]]
        let elapsed = Self.clampedElapsed(state.elapsedSeconds, duration: duration)
        lastOutcome = correction.map {
            .restoredWithCorrectedIndex(elapsedSeconds: elapsed, currentIndex: index, reason: $0)
        } ?? .restored(elapsedSeconds: elapsed, currentIndex: index)
        return lastOutcome!
    }

    /// Clamp a persisted position into a playable range.
    ///
    /// Negative values and values past the end both come from real situations (a corrupt record, a
    /// file that changed since it was persisted). Restarting the track is the safe answer for a
    /// position that no longer exists — silently scheduling nothing would look like a broken track.
    static func clampedElapsed(_ elapsed: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        guard let duration, duration > 0 else { return elapsed }
        return elapsed >= duration ? 0 : elapsed
    }

    /// Whether asynchronous restoration work is still valid.
    func isCurrent(restorationGeneration candidate: UInt64) -> Bool {
        candidate == restorationGeneration
    }

    /// Record that a restoration result arrived too late to matter.
    func discardStaleRestoration() { discardedStaleRestorations += 1 }

    /// A restored track begins a **new play instance**.
    ///
    /// It is not a continuation of the interrupted one, because the evidence a continuation would
    /// need is not persisted: audible frames and scrobble eligibility live only in memory. Treating
    /// it as new is also the safe direction — the new instance starts with zero audible frames, so
    /// it must earn its own scrobble rather than inheriting credit for audio the user may never have
    /// heard. A naturally completed play is never resurrected, since only the elapsed position is
    /// stored and a completed track persists as position 0 of the next one.
    static let restoredTrackStartsNewPlayInstance = true
}
