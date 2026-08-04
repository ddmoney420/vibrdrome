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
    /// Jump straight to a queue position — a tapped queue row.
    func skipToIndex(_ index: Int)
}

extension PlaybackTransportControlling {
    /// The form ~40 call sites use. A protocol requirement cannot carry default arguments, so the
    /// defaults live here — and delegate exactly once to the semantic requirement.
    func play(song: Song, from queue: [Song]? = nil) {
        play(song: song, from: queue, at: 0)
    }
}

// MARK: - Queue

@MainActor
protocol PlaybackQueueControlling: AnyObject {
    func addToQueue(_ song: Song)
    func addToQueue(_ songs: [Song])
    func addToQueueNext(_ song: Song)
    func addToQueueNext(_ songs: [Song])
    func updateQueueSongStarred(id: String, starred: Bool)
    func updateQueueSongRating(id: String, rating: Int?)
    func clearQueue()
    func removeFromQueue(atAbsolute index: Int)
    func moveInUpNext(from source: IndexSet, to destination: Int)
}

// MARK: - Observable state

@MainActor
protocol PlaybackStateProviding: AnyObject {
    var isPlaying: Bool { get }
    var currentSong: Song? { get }
    var currentTime: TimeInterval { get }
    /// Live position sampled from the player rather than the periodic tick. The karaoke lyrics view
    /// re-reads this up to 30 fps for word placement; it is a time value, not the player itself.
    var smoothCurrentTime: TimeInterval { get }
    var isBuffering: Bool { get }
    var duration: TimeInterval { get }
    /// Server-declared duration reconciled against what the player reports.
    var effectiveDuration: TimeInterval { get }
    var queue: [Song] { get }
    var currentIndex: Int { get }
    /// What plays next, honouring shuffle. Derived by the engine, not stored.
    var upNextEntries: [(index: Int, song: Song)] { get }
    /// Index the engine would advance to. The mini player peeks at it to name the next track.
    func nextSongIndex() -> Int?
    /// Where playback was started from, for UI attribution. Views set it alongside starting
    /// playback, so it is read-write — it is an application concept, not engine state.
    var playingFromContext: String? { get set }
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
    /// Artist the radio session was seeded from, shown in the queue header.
    var radioSeedArtistName: String? { get }
    func startRadio(artistName: String)
    func startRadioFromSong(_ song: Song)
    func startSongSimilarityMix(_ song: Song)
    func playRadio(station: InternetRadioStation)
    func stopRadioMode()
}

// MARK: - Processing

@MainActor
protocol PlaybackProcessingControlling: AnyObject {
    var eqEnabled: Bool { get }
    /// Output volume as the engine applies it, after ReplayGain scaling.
    var volume: Float { get set }
    /// The user's own volume setting, distinct from ReplayGain scaling.
    var userVolume: Float { get set }
    var playbackRate: Float { get set }
    /// Whether a visualizer is attached; the visualizer view sets it as it appears and disappears.
    var visualizerActive: Bool { get set }
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
