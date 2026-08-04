import Foundation

// The application's playback contract, split by capability.
//
// **Why this is separate from `GaplessPlaybackControlling`.** That protocol is engine-facing: it
// describes what the persistent PCM engine can actually do — transport over a scheduled timeline.
// This one is application-facing, and the application needs things no audio engine should be asked
// to implement: internet radio, smart-shuffle caches, predownload progress, playback context
// strings. Forcing one protocol to serve both would either bloat the engine contract with concepts
// it cannot honour, or starve the UI. So there are two, and the façade below is where they meet.
//
// **Scoped to what is actually used.** `AudioEngine` exposes 101 members; a repository sweep of all
// 194 production call sites shows only ~32 distinct members are ever called. This surface covers
// those, not the other sixty-nine — an implementation detail is not an API just because it is
// currently reachable.

// MARK: - Transport

@MainActor
protocol PlaybackTransportControlling: AnyObject {
    func play(song: Song, from queue: [Song]?, at index: Int)
    func pause()
    func resume()
    func stop()
    func togglePlayPause()
    func next()
    func previous()
    func seek(to time: TimeInterval)
}

// MARK: - Queue

@MainActor
protocol PlaybackQueueControlling: AnyObject {
    func addToQueue(_ song: Song)
    func addToQueue(_ songs: [Song])
    func addToQueueNext(_ song: Song)
    func addToQueueNext(_ songs: [Song])
    func updateQueueSongStarred(id: String, starred: Bool)
}

// MARK: - Observable state

@MainActor
protocol PlaybackStateProviding: AnyObject {
    var isPlaying: Bool { get }
    var currentSong: Song? { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    /// Server-declared duration reconciled against what the player reports.
    var effectiveDuration: TimeInterval { get }
    var queue: [Song] { get }
    var currentIndex: Int { get }
    /// Where playback was started from, for UI attribution.
    var playingFromContext: String? { get }
}

// MARK: - Repeat and shuffle

@MainActor
protocol PlaybackModeControlling: AnyObject {
    var shuffleEnabled: Bool { get }
    var repeatMode: RepeatMode { get }
    func toggleShuffle()
    func cycleRepeatMode()
}

// MARK: - Radio and live streams

/// Deliberately its own capability. Radio is a **legacy-path concern**: the persistent PCM engine
/// schedules a known finite timeline, which a live stream does not have. A future selector routes
/// radio to AVQueuePlayer regardless of what else moves.
@MainActor
protocol PlaybackRadioControlling: AnyObject {
    var isRadioMode: Bool { get }
    var currentRadioStation: InternetRadioStation? { get }
    func startRadio(artistName: String)
    func startRadioFromSong(_ song: Song)
    func startSongSimilarityMix(_ song: Song)
    func playRadio(station: InternetRadioStation)
}

// MARK: - Processing

@MainActor
protocol PlaybackProcessingControlling: AnyObject {
    var eqEnabled: Bool { get }
    var volume: Float { get set }
    func applyEQToggle(enabled: Bool)
    func applyEffectiveVolume()
}

// MARK: - Predownload

/// Read-mostly status for the UI. Another legacy-path concern: the persistent engine's preparation
/// window is a different mechanism with different semantics, and conflating the two would make the
/// UI lie about one of them.
@MainActor
protocol PlaybackDownloadStateProviding: AnyObject {
    var predownloadStatus: PredownloadStatus { get }
    var predownloadSpeed: Double { get }
    var predownloadsPending: Int { get }
    func prepareLookahead()
}

// MARK: - History and restoration

@MainActor
protocol PlaybackHistoryProviding: AnyObject {
    var recentlyPlayed: [Song] { get }
    func addRandomSongPlayed(songId: String)
    func restorePlayQueue(client: SubsonicClient)
}

/// The composed application-facing contract.
///
/// A future selector implements this by routing supported non-live track playback to the persistent
/// PCM engine while radio, predownload, history and application context stay on shared services.
/// Lane 1 does none of that: the only conformer delegates everything to `AudioEngine.shared`.
@MainActor
protocol ApplicationPlaybackControlling: PlaybackTransportControlling, PlaybackQueueControlling,
                                          PlaybackStateProviding, PlaybackModeControlling,
                                          PlaybackRadioControlling, PlaybackProcessingControlling,
                                          PlaybackDownloadStateProviding, PlaybackHistoryProviding {}
