import AVFoundation
import Foundation

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
            return
        }
        tearDownCurrentMode()
        isPlaying = false
        // Deliberately preserved: queue, currentIndex, currentSong, repeat/shuffle,
        // playingFromContext, volume and EQ state. The persistent session adopts them, and a later
        // legacy re-entry rebuilds player items from them.
    }
}
