#if os(iOS)
import Foundation

/// The playback operations CarPlay triggers, separated from template plumbing.
///
/// **Why this exists.** `CPInterfaceController` has no public initialiser, so `CarPlayManager`
/// cannot be constructed in a test — and without that, "one CarPlay tap produces exactly one engine
/// call" is unverifiable, which is the one property this migration could plausibly break. Every
/// playback-triggering `CPListItem` handler and Now Playing button in `CarPlayManager` calls one of
/// these methods and does nothing else, so exercising them here exercises the exact code a tap runs.
///
/// It is an `enum` of static members on purpose: handlers reference it the same way they previously
/// referenced `AudioEngine.shared`, so no closure gains a capture of `self` and no `CPListItem`
/// retained by a template can start retaining the manager.
///
/// Deliberately **not** CarPlay-gated — it imports no CarPlay symbols, so it stays visible to the
/// test target regardless of whether `CARPLAY_ENABLED` is set there. A test that silently compiles
/// out is worse than no test.
///
/// This is the same shape as `RemoteCommandManager`'s extracted command bodies, deliberately: one
/// pattern for "UI callback → named method → façade".
@MainActor
enum CarPlayPlaybackActions {

    #if DEBUG
    /// Test seam. The real transport members would start AVQueuePlayer, which cannot happen while
    /// the gapless real-time suites are running. Tests substitute a recorder and reset it in
    /// teardown. Production never sets this, and it does not exist in release builds.
    static var playbackOverride: (any ApplicationPlaybackControlling)?
    #endif

    /// Resolved per call, never stored — CarPlay must read live playback state, not a snapshot.
    static var playback: any ApplicationPlaybackControlling {
        #if DEBUG
        playbackOverride ?? ApplicationPlayback.shared
        #else
        ApplicationPlayback.shared
        #endif
    }

    // MARK: - Now Playing buttons

    static func toggleShuffle() { playback.toggleShuffle() }

    static func cycleRepeatMode() { playback.cycleRepeatMode() }

    // MARK: - Up Next

    /// The absolute queue index for row `offset` of the Up Next list.
    ///
    /// **The mapping is unchanged from before the façade migration and must stay that way.** The
    /// list is built from `upNext`, the raw linear tail `queue[(currentIndex + 1)...]`, so row
    /// `offset` is at absolute index `currentIndex + 1 + offset`.
    ///
    /// Two properties this deliberately preserves:
    ///
    /// - `currentIndex` is read **at tap time**, not when the template was built. If playback moved
    ///   on while the list was on screen, the row resolves against the queue as it is now — which is
    ///   the existing behaviour, not a bug being introduced here.
    /// - It is positional, never identity-based. Two queue positions holding the same song id stay
    ///   distinct; matching by `song.id` would collapse them onto the first occurrence.
    ///
    /// Note this is *not* `upNextEntries`, which under shuffle returns true playback order capped at
    /// five entries. Using that here would silently reorder and truncate the CarPlay list.
    static func upNextAbsoluteIndex(currentIndex: Int, offset: Int) -> Int {
        currentIndex + 1 + offset
    }

    /// Select row `offset` of the Up Next list.
    static func selectUpNext(offset: Int) {
        playback.skipToIndex(upNextAbsoluteIndex(currentIndex: playback.currentIndex, offset: offset))
    }

    // MARK: - Playing from lists

    static func play(song: Song, from queue: [Song], at index: Int) {
        playback.play(song: song, from: queue, at: index)
    }

    static func play(song: Song, from queue: [Song]) {
        playback.play(song: song, from: queue)
    }

    static func playRadio(station: InternetRadioStation) {
        playback.playRadio(station: station)
    }

    static func startRadio(artistName: String) {
        playback.startRadio(artistName: artistName)
    }
}
#endif
