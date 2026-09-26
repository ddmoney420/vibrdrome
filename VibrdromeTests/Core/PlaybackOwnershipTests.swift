import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Lane 3D-B1 (partial): the ownership model and the legacy quiescence mechanism.
///
/// **`isPlaying == false` is not evidence of anything.** A paused `AVQueuePlayer` still holds its
/// current and queued items, its periodic time observer, its item-end observer and its property
/// observers — so it can still advance, still feed Now Playing, still accrue scrobble progress and
/// still hold its claim on the session. These tests assert on the items, not the flag.
@Suite(.serialized)
@MainActor
struct PlaybackOwnershipTests {

    private func makeSong(id: String) -> Song {
        Song(id: id, parent: nil, title: "Track \(id)",
             album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
             track: nil, year: nil, genre: nil, coverArt: nil,
             size: nil, contentType: nil, suffix: nil,
             duration: 180, bitRate: nil, path: nil,
             discNumber: nil, created: nil, starred: nil, userRating: nil,
             bpm: nil, replayGain: nil, musicBrainzId: nil)
    }

    // MARK: - Ownership coordinator

    /// The invariant is a count: never two owners.
    @Test func ownershipIsAlwaysZeroOrOne() {
        let coordinator = PlaybackOwnershipCoordinator()
        #expect(coordinator.authority == .none)
        #expect(coordinator.ownerCount == 0)

        for authority in [PlaybackAuthority.legacy, .persistent, .legacy, .none] {
            coordinator.grant(authority)
            #expect(coordinator.ownerCount <= 1, "two backends claimed ownership at once")
            #expect(coordinator.authority == authority)
        }
        coordinator.release()
        #expect(coordinator.ownerCount == 0)
    }

    /// Only the holder may execute transport; the other backend is deterministically refused.
    @Test func onlyTheAuthorityHolderMayExecuteTransport() {
        let coordinator = PlaybackOwnershipCoordinator()

        coordinator.grant(.legacy)
        #expect(coordinator.mayExecuteTransport(.legacy))
        #expect(coordinator.mayExecuteTransport(.persistent) == false,
                "the inactive backend was allowed to execute transport")

        coordinator.grant(.persistent)
        #expect(coordinator.mayExecuteTransport(.persistent))
        #expect(coordinator.mayExecuteTransport(.legacy) == false)

        coordinator.release()
        #expect(coordinator.mayExecuteTransport(.legacy) == false)
        #expect(coordinator.mayExecuteTransport(.persistent) == false)
        #expect(coordinator.mayExecuteTransport(.none) == false, ".none must never own transport")
    }

    /// All four signals derive from the one authority, so they cannot disagree — a Now Playing
    /// owner that differs from the audio owner is how duplicate metadata happens.
    @Test func everySignalOwnerFollowsTheSingleAuthority() {
        let coordinator = PlaybackOwnershipCoordinator()
        for authority in PlaybackAuthority.allCases {
            coordinator.grant(authority)
            #expect(coordinator.audioSessionOwner == authority)
            #expect(coordinator.nowPlayingOwner == authority)
            #expect(coordinator.scrobbleOwner == authority)
            #expect(coordinator.visualizerOwner == authority)
        }
    }

    /// Fallback is permitted until audio has been heard, and prohibited afterwards.
    @Test func fallbackIsPermittedOnlyBeforeTheAudibleBoundary() {
        let coordinator = PlaybackOwnershipCoordinator()
        coordinator.grant(.persistent)
        #expect(coordinator.isFallbackPermitted, "fallback must be allowed before anything is heard")

        coordinator.markAudibleBoundaryReached()
        #expect(coordinator.audibleBoundaryReached)
        #expect(coordinator.isFallbackPermitted == false,
                "fallback stayed permitted after persistent became audible")

        // A new session resets the boundary.
        coordinator.grant(.legacy)
        #expect(coordinator.audibleBoundaryReached == false)
        #expect(coordinator.isFallbackPermitted)
    }

    /// Nothing can reach the audible boundary without owning audio first.
    @Test func theAudibleBoundaryRequiresAnOwner() {
        let coordinator = PlaybackOwnershipCoordinator()
        coordinator.markAudibleBoundaryReached()
        #expect(coordinator.audibleBoundaryReached == false,
                "the audible boundary was reached with no owner")
    }

    // MARK: - Session snapshot

    /// The snapshot carries occurrences positionally, so duplicate song ids stay distinct.
    @Test func theSnapshotKeepsDuplicateIdsAsDistinctOccurrences() {
        let duplicate = makeSong(id: "same")
        let snapshot = PlaybackSessionSnapshot(
            songs: [makeSong(id: "a"), duplicate, makeSong(id: "b"), duplicate],
            currentIndex: 1, startOffsetSeconds: 12,
            repeatMode: .all, shuffleEnabled: true,
            playingFromContext: "Album: Probe", userVolume: 0.4, eqEnabled: true)

        #expect(snapshot.songs.count == 4, "duplicate occurrences were collapsed")
        #expect(snapshot.songs[1].id == "same")
        #expect(snapshot.songs[3].id == "same")
        #expect(snapshot.currentSong?.id == "same")
        #expect(snapshot.currentIndex == 1, "position must stay positional, not identity-based")
    }

    /// Capturing the snapshot reads the live engine and changes nothing.
    @Test func capturingASnapshotIsNonDestructive() {
        let engine = AudioEngine.shared
        let queueBefore = engine.queue.map(\.id)
        let indexBefore = engine.currentIndex
        let contextBefore = engine.playingFromContext
        defer {
            engine.queue = engine.queue
            engine.playingFromContext = contextBefore
        }

        let snapshot = engine.captureSessionSnapshot()

        #expect(snapshot.songs.map(\.id) == queueBefore)
        #expect(snapshot.currentIndex == indexBefore)
        #expect(snapshot.repeatMode == engine.repeatMode)
        #expect(snapshot.shuffleEnabled == engine.shuffleEnabled)
        #expect(snapshot.userVolume == engine.userVolume)
        #expect(snapshot.eqEnabled == engine.eqEnabled)
        // Nothing moved.
        #expect(engine.queue.map(\.id) == queueBefore, "capturing a snapshot changed the queue")
        #expect(engine.currentIndex == indexBefore)
    }

    // MARK: - Legacy quiescence

    /// Transport state reports on items, not on the playing flag.
    @Test func transportStateIsJudgedByItemsNotThePlayingFlag() {
        let idle = LegacyTransportState(rate: 0, hasCurrentItem: false,
                                        queuedItemCount: 0, isPlaying: false)
        #expect(idle.isTransportActive == false)

        // Paused but still holding an item: still active, and this is the case that matters.
        let pausedWithItem = LegacyTransportState(rate: 0, hasCurrentItem: true,
                                                  queuedItemCount: 0, isPlaying: false)
        #expect(pausedWithItem.isTransportActive,
                "a paused player still holding an item was reported as released")

        let queuedOnly = LegacyTransportState(rate: 0, hasCurrentItem: false,
                                              queuedItemCount: 2, isPlaying: false)
        #expect(queuedOnly.isTransportActive, "queued items were ignored")

        let rolling = LegacyTransportState(rate: 1, hasCurrentItem: false,
                                           queuedItemCount: 0, isPlaying: false)
        #expect(rolling.isTransportActive, "a non-zero rate was ignored")
    }

    /// Quiescing releases transport and leaves nothing that could become audible, while preserving
    /// the logical session the persistent engine is about to adopt.
    @Test func quiescingReleasesTransportButKeepsTheLogicalSession() {
        let engine = AudioEngine.shared
        let queueBefore = engine.queue
        let indexBefore = engine.currentIndex
        let contextBefore = engine.playingFromContext
        let volumeBefore = engine.userVolume
        defer {
            engine.queue = queueBefore
            engine.currentIndex = indexBefore
            engine.playingFromContext = contextBefore
            engine.userVolume = volumeBefore
        }

        engine.queue = [makeSong(id: "q0"), makeSong(id: "q1"), makeSong(id: "q2")]
        engine.currentIndex = 1
        engine.playingFromContext = "Album: Handoff"

        let snapshot = engine.captureSessionSnapshot()
        engine.quiesceForPersistentSession()

        // Transport released.
        let state = engine.legacyTransportState
        #expect(state.rate == 0, "legacy rate was not zero after quiescence")
        #expect(state.hasCurrentItem == false,
                "legacy still holds a current AVPlayerItem after quiescence")
        #expect(state.queuedItemCount == 0,
                "legacy still holds \(state.queuedItemCount) queued AVPlayerItems")
        #expect(state.isTransportActive == false, "legacy transport is still active")
        #expect(engine.isPlaying == false)

        // Logical session preserved for the handoff.
        #expect(engine.queue.map(\.id) == ["q0", "q1", "q2"],
                "quiescence destroyed the queue the persistent session must adopt")
        #expect(engine.currentIndex == 1, "quiescence lost the current position")
        #expect(engine.playingFromContext == "Album: Handoff",
                "quiescence cleared the playback context")
        #expect(snapshot.songs.map(\.id) == ["q0", "q1", "q2"])
        #expect(snapshot.currentIndex == 1)
    }

    /// Quiescence is idempotent and does not disturb shared services.
    @Test func quiescingIsIdempotentAndLeavesSharedServicesAlone() {
        let engine = AudioEngine.shared
        let recentBefore = engine.recentlyPlayed.count
        let radioBefore = engine.isRadioMode
        let predownloadBefore = engine.predownloadsPending

        for _ in 0..<5 { engine.quiesceForPersistentSession() }

        #expect(engine.legacyTransportState.isTransportActive == false)
        #expect(engine.recentlyPlayed.count == recentBefore, "quiescence cleared history")
        #expect(engine.isRadioMode == radioBefore, "quiescence changed radio configuration")
        #expect(engine.predownloadsPending == predownloadBefore,
                "quiescence disturbed predownload state")
    }

    /// Quiescence must not activate the audio session or start anything.
    @Test func quiescingActivatesNothing() {
        let engine = AudioEngine.shared
        let categoryBefore = AVAudioSession.sharedInstance().category
        let modeBefore = AVAudioSession.sharedInstance().mode
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        engine.quiesceForPersistentSession()

        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "quiescence changed the audio session category")
        #expect(AVAudioSession.sharedInstance().mode == modeBefore)
        #expect(engine.isPlaying == false)
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore)
        #expect(GaplessDiagnosticsRegistry.current == nil)
    }

    // MARK: - Routing unchanged

    /// The DEBUG flag defaults Off, so the shared router never selects persistent.
    ///
    /// Deliberately asserts "not persistent" rather than "no authority at all": another suite in
    /// the same process may legitimately have started a legacy session on the shared router, and
    /// what matters is that nothing reached the persistent engine without a selection.
    @Test func routingRemainsLegacyUntilSelectionIsWired() {
        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        #expect(router.ownership.authority != .persistent,
                "something granted persistent authority with the flag Off")
        #expect(router.isPersistentSessionActive == false)
        #expect(router.selectedBackend == .legacy)
        #expect(PersistentRoutingSetting.isEnabled == false,
                "the persistent routing flag is not Off by default")
    }
}
