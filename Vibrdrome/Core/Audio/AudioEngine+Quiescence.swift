import AVFoundation
import Foundation

extension AudioEngine {

    /// Whether legacy is allowed to build transport right now.
    ///
    /// **The narrowest stable boundary.** Everything that can put audio on the legacy player passes
    /// through `replacePlayerItem` (the only place `gaplessPlayer` is constructed or given an item,
    /// and the only place the observers are re-armed) or `prepareLookahead` (the only place an item
    /// is inserted ahead of the audible one). Gating those two covers scene restoration, CarPlay
    /// connection, predownload and any future caller, without a check scattered across call sites
    /// that a new path could simply forget.
    ///
    /// This is not a second routing flag: it is the latch that quiescence closes and that an
    /// explicit new legacy session opens, so it always follows the handover rather than deciding it.
    var admitsTransportRebuild: Bool { !isQuiescedForPersistentSession }

    /// Re-admit legacy transport, because it is being given a session of its own.
    ///
    /// Deliberately reached only from `play(...)` — an explicit new legacy session is the one
    /// legitimate way transport comes back, and it is what the router calls when a plan or a
    /// fallback hands legacy the session. Stop does *not* re-admit: stopping during a persistent
    /// session must not arm legacy to rebuild behind it.
    func admitTransportForNewLegacySession() {
        isQuiescedForPersistentSession = false
    }
}

/// Making the legacy transport genuinely passive so the persistent engine can own audio.
///
/// **Pausing is not releasing.** A paused `AVQueuePlayer` still holds its current and queued
/// `AVPlayerItem`s, its periodic time observer, its item-end observer and its property observers —
/// so it can still advance, still publish Now Playing through the time observer, still accrue
/// scrobble progress, and still hold its claim on the audio session. `isPlaying == false` proves
/// none of that is gone.
extension AudioEngine {

    /// What the legacy transport is actually holding. The item counts are the evidence; the
    /// playing flag is not.
    var legacyTransportState: LegacyTransportState {
        let player = activePlayer
        return LegacyTransportState(
            rate: player?.rate ?? 0,
            hasCurrentItem: player?.currentItem != nil,
            queuedItemCount: gaplessPlayer?.items().count ?? 0,
            isPlaying: isPlaying
        )
    }

    /// Capture what the persistent session needs before transport is torn down.
    ///
    /// Must run **before** `quiesceForPersistentSession()`: teardown removes the items and observers
    /// that would otherwise be the only record of position. Queue occurrences are carried
    /// positionally, so duplicate song ids remain distinct.
    func captureSessionSnapshot(startOffsetSeconds: TimeInterval? = nil) -> PlaybackSessionSnapshot {
        PlaybackSessionSnapshot(
            songs: queue,
            currentIndex: currentIndex,
            startOffsetSeconds: startOffsetSeconds ?? currentTime,
            repeatMode: repeatMode,
            shuffleEnabled: shuffleEnabled,
            playingFromContext: playingFromContext,
            userVolume: userVolume,
            eqEnabled: eqEnabled
        )
    }

    /// Release legacy transport ownership without destroying the logical session.
    ///
    /// Deliberately **not** `stop()`. That submits a scrobble, clears Now Playing and nils
    /// `currentSong` and `currentRadioStation` — it ends the session, which is wrong here: the
    /// session is being *handed over*, not finished, and crediting a scrobble for a track the
    /// persistent engine is about to play would double-count it.
    ///
    /// What this does release, via `tearDownCurrentMode()`:
    ///
    /// - increments the generation, invalidating in-flight async EQ tasks that could otherwise
    ///   replace a player item after teardown;
    /// - tears down the periodic time observer (the Now Playing and scrobble progress feed), the
    ///   item-end observer (queue advancement) and the property observers (including stall
    ///   recovery, which would otherwise try to resurrect playback);
    /// - clears the lookahead item;
    /// - pauses, taking rate to 0;
    /// - **removes every current and queued `AVPlayerItem`**, so nothing remains that could become
    ///   audible;
    /// - tears down the crossfade controller's secondary player when that mode is active.
    ///
    /// Downloads, predownload state, bookmarks, history and radio configuration are untouched —
    /// those are shared services, not transport.
    ///
    /// Application-level transport commands are prevented separately, by the router: while
    /// authority is persistent it routes to the persistent adapter and never to legacy, so legacy
    /// receives no commands to execute. Teardown removes its ability to act on its own.
    func quiesceForPersistentSession() {
        guard !isUITesting else {
            isPlaying = false
            isQuiescedForPersistentSession = true
            return
        }
        tearDownCurrentMode()
        isPlaying = false
        // Closed here rather than at each caller because tearing transport down is not the same as
        // *keeping* it down. Scene activation, a CarPlay connect, an audio interruption, the sleep
        // timer and the predownload manager can all reach legacy transport without passing the
        // router, and several of them rebuild an `AVPlayerItem` and re-arm the observers — which
        // would put a second live transport under an audible persistent session. See
        // `admitsTransportRebuild`.
        isQuiescedForPersistentSession = true
        // Deliberately preserved: queue, currentIndex, currentSong, repeat/shuffle,
        // playingFromContext, volume and EQ state. The persistent session adopts them, and a later
        // legacy re-entry rebuilds player items from them.
    }
}
