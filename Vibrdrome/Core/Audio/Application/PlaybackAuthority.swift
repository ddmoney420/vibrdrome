import Foundation

/// Who owns audible playback right now.
///
/// **The invariant is a count, not a preference: 0 or 1, never 2.** Two engines each holding an
/// audio session, publishing Now Playing and claiming scrobble credit is the failure this whole
/// lane is built to prevent, and it is not the sort of thing that announces itself — it sounds like
/// one engine until something skips twice or a track scrobbles twice.
enum PlaybackAuthority: String, Equatable, Sendable, CaseIterable {
    case none
    case legacy
    case persistent
}

/// The state the persistent session must adopt when legacy hands over.
///
/// Captured **before** legacy transport is torn down, because teardown removes the `AVPlayerItem`s
/// and observers that would otherwise be the only record of where playback was. The inactive
/// `AVQueuePlayer` is explicitly not the queue authority during handoff — this value is.
///
/// Song *occurrences* are carried positionally, so two queue positions holding the same song id
/// stay distinct.
struct PlaybackSessionSnapshot: Equatable, Sendable {
    var songs: [Song]
    var currentIndex: Int
    var startOffsetSeconds: TimeInterval
    var repeatMode: RepeatMode
    var shuffleEnabled: Bool
    var playingFromContext: String?
    var userVolume: Float
    var eqEnabled: Bool

    var currentSong: Song? {
        songs.indices.contains(currentIndex) ? songs[currentIndex] : nil
    }
}

/// What each backend reports about its own transport, for the ownership assertions.
///
/// `isPlaying == false` is deliberately **not** part of this: a paused `AVQueuePlayer` still owns
/// its items, its observers and its claim on the session, so pausing proves nothing about
/// ownership. The item counts are the real evidence.
struct LegacyTransportState: Equatable, Sendable {
    var rate: Float
    var hasCurrentItem: Bool
    var queuedItemCount: Int
    var isPlaying: Bool

    /// Transport is genuinely released only when nothing remains that could become audible.
    var isTransportActive: Bool {
        rate != 0 || hasCurrentItem || queuedItemCount > 0 || isPlaying
    }
}

/// Router-owned ownership coordinator.
///
/// Single source of truth for which backend may execute transport, activate the audio session,
/// publish Now Playing, claim scrobble credit and own the visualizer feed. Ownership is granted
/// **before** the selected backend becomes audible, and released only when the session ends.
@MainActor
final class PlaybackOwnershipCoordinator {
    private(set) var authority: PlaybackAuthority = .none

    /// Set once the selected backend has actually produced audio. After this point automatic
    /// fallback is prohibited — a cutover mid-track is a worse outcome than an error.
    private(set) var audibleBoundaryReached = false

    /// Fallback is only permitted while nothing has been heard yet.
    var isFallbackPermitted: Bool { !audibleBoundaryReached }

    /// How many backends currently claim ownership. Must never exceed one.
    var ownerCount: Int { authority == .none ? 0 : 1 }

    func grant(_ newAuthority: PlaybackAuthority) {
        authority = newAuthority
        audibleBoundaryReached = false
    }

    /// Record that the owning backend has produced audio.
    func markAudibleBoundaryReached() {
        guard authority != .none else { return }
        audibleBoundaryReached = true
    }

    func release() {
        authority = .none
        audibleBoundaryReached = false
    }

    /// Whether `backend` may execute transport right now.
    func mayExecuteTransport(_ backend: PlaybackAuthority) -> Bool {
        authority == backend && backend != .none
    }

    // MARK: - Signal ownership
    //
    // All four derive from the single authority rather than being tracked separately: independent
    // flags could disagree, and "who owns Now Playing" disagreeing with "who owns audio" is exactly
    // how duplicate metadata and double scrobbles happen.

    var audioSessionOwner: PlaybackAuthority { authority }
    var nowPlayingOwner: PlaybackAuthority { authority }
    var scrobbleOwner: PlaybackAuthority { authority }
    var visualizerOwner: PlaybackAuthority { authority }
}
