import Foundation

/// Chooses between the persistent gapless engine and the existing AVQueuePlayer engine.
///
/// **Not user-facing.** There is no setting for this and there should not be one yet: the persistent
/// engine is still being brought to parity, and the fallback exists so development can proceed
/// without risking playback. The selector's job is to make the choice *explicit and recorded* rather
/// than implicit, so a fallback is a reportable event and not a mystery.
///
/// **Never mid-track.** A decision is made when a track is about to be prepared, never while one is
/// audible. Swapping engines under a playing track would cut the output stream — precisely the
/// defect this architecture exists to remove.
enum GaplessEngineSelection: String, Sendable, Equatable {
    case persistentGapless
    case queuePlayerFallback
}

/// Why the persistent engine was declined for a given item.
enum GaplessFallbackReason: String, Sendable, Equatable, CaseIterable {
    /// The container or codec has no exact-length decode path.
    case unsupportedSource
    /// The file could not be opened or decoded.
    case decoderFailure
    /// Protected or non-file-backed stream the engine cannot schedule.
    case unsupportedStreamOrDRM
    /// The item could not be made local in time for its boundary.
    case preparationDeadlineMissed
    /// The engine itself failed to start.
    case engineInitializationFailure
}

/// Per-source capability, for the current server. Kept as a *capability result*, not a preference
/// change: the user's transcode setting is untouched until AirPlay and device behaviour on the Opus
/// path are verified at Checkpoint 4.
///
/// Measured order of preference for gapless:
/// 1. Direct original (FLAC / ALAC / AAC / stored MP3 with trim metadata) — frame-exact.
/// 2. Opus transcode — frame-exact at 48 kHz, verified against the real server.
/// 3. Completed MP3 *only* when trustworthy trim metadata is present.
///
/// Not advertised as gapless: MP3 transcode with no recoverable gapless metadata.
struct GaplessCapability: Sendable, Equatable {
    let isGaplessCapable: Bool
    let reason: GaplessFallbackReason?

    static let capable = GaplessCapability(isGaplessCapable: true, reason: nil)

    /// Decide from what preparation actually discovered about the file.
    static func evaluate(trimReason: GaplessTrim.Reason) -> GaplessCapability {
        switch trimReason {
        case .wholeFile, .lameGaplessHeader:
            return .capable
        case .mp3WithoutGaplessMetadata:
            // Playable, but the join keeps the codec's inserted frames — so it must not be
            // presented as gapless.
            return GaplessCapability(isGaplessCapable: false, reason: .unsupportedSource)
        }
    }
}

/// Records selections and fallbacks so the reasons are visible rather than inferred.
@MainActor
final class GaplessEngineSelector {
    private(set) var selection: GaplessEngineSelection = .persistentGapless
    private(set) var fallbackHistory: [(itemID: String, reason: GaplessFallbackReason)] = []
    /// True while a track is audible — the window in which no switch may happen.
    var isTrackAudible = false

    /// Request a fallback. Refused while a track is audible, so a switch can never cut playback
    /// mid-track; the caller keeps the current engine and may retry at the next boundary.
    @discardableResult
    func requestFallback(itemID: String, reason: GaplessFallbackReason) -> Bool {
        fallbackHistory.append((itemID, reason))
        guard !isTrackAudible else { return false }
        selection = .queuePlayerFallback
        return true
    }

    /// Return to the persistent engine — likewise only at a boundary.
    @discardableResult
    func restorePersistentEngine() -> Bool {
        guard !isTrackAudible else { return false }
        selection = .persistentGapless
        return true
    }

    func reasons(forItemID itemID: String) -> [GaplessFallbackReason] {
        fallbackHistory.filter { $0.itemID == itemID }.map(\.reason)
    }
}
