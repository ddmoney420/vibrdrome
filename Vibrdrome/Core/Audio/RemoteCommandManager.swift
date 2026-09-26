import Foundation
import MediaPlayer
import os.log

@MainActor
final class RemoteCommandManager {
    static let shared = RemoteCommandManager()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var isSetup = false

    /// The application playback façade.
    ///
    /// Resolved through the composition point on **every** access rather than stored at init. Two
    /// reasons: this manager can never end up holding a different playback authority than the rest
    /// of the app, and state reads stay live — a cached `currentSong` here would go stale the
    /// moment the track changed, and the lock-screen Like button would star the wrong song.
    private var playback: any ApplicationPlaybackControlling {
        #if DEBUG
        playbackOverride ?? ApplicationPlayback.shared
        #else
        ApplicationPlayback.shared
        #endif
    }

    #if DEBUG
    /// Test seam. `MPRemoteCommandCenter` offers no way to fire a registered command, and the real
    /// transport members start AVQueuePlayer — which cannot happen in the unit suites, because they
    /// run alongside the gapless real-time suites and two engines contending for the audio stack
    /// kills the test process. Tests substitute a recorder here and call the command bodies below
    /// directly. Production never sets this, and the property does not exist in release builds.
    var playbackOverride: (any ApplicationPlaybackControlling)?

    /// Counts completed `setup()` registrations so a test can prove the `isSetup` guard really does
    /// stop a second set of handlers being attached. A duplicated handler is the defect that makes
    /// one lock-screen press skip two tracks.
    private(set) var registrationCount = 0
    #endif

    func setup() {
        guard !isSetup else { return }
        isSetup = true

        setupPlaybackCommands()
        setupNavigationCommands()
        setupSeekCommands()
        setupSkipCommands()
        setupRatingCommands()

        #if DEBUG
        registrationCount += 1
        #endif
    }

    // MARK: - Command bodies
    //
    // One method per remote command, each returning exactly the status the original inline handler
    // returned. The `addTarget` closures below do nothing but call these.
    //
    // The split exists purely so the behaviour is reachable from a test: `MPRemoteCommandCenter`
    // cannot invoke a registered command, and `MPRemoteCommandEvent` has no public initialiser, so
    // without it "one press produces exactly one engine call" would be unprovable. Registration,
    // command availability and `MPRemoteCommandCenter` ownership are unchanged.

    func handlePlay() -> MPRemoteCommandHandlerStatus {
        playback.resume()
        return .success
    }

    func handlePause() -> MPRemoteCommandHandlerStatus {
        playback.pause()
        return .success
    }

    func handleTogglePlayPause() -> MPRemoteCommandHandlerStatus {
        playback.togglePlayPause()
        return .success
    }

    func handleNextTrack() -> MPRemoteCommandHandlerStatus {
        playback.next()
        return .success
    }

    func handlePreviousTrack() -> MPRemoteCommandHandlerStatus {
        playback.previous()
        return .success
    }

    /// `position` is `nil` when the event was not an `MPChangePlaybackPositionCommandEvent` — the
    /// only case the original handler mapped to `.commandFailed`. Taking the already-extracted
    /// position rather than the event keeps that mapping testable without a MediaPlayer event.
    func handleChangePlaybackPosition(to position: TimeInterval?) -> MPRemoteCommandHandlerStatus {
        guard let position else { return .commandFailed }
        playback.seek(to: position)
        return .success
    }

    func handleLike() -> MPRemoteCommandHandlerStatus {
        guard let song = playback.currentSong else { return .success }
        Task { @MainActor in
            do {
                try await AppState.shared.subsonicClient.star(id: song.id)
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "RemoteCommand")
                    .error("Failed to star track: \(error)")
            }
            if UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoDownloadFavorites) {
                DownloadManager.shared.download(song: song, client: AppState.shared.subsonicClient)
            }
        }
        return .success
    }

    func handleDislike() -> MPRemoteCommandHandlerStatus {
        guard let song = playback.currentSong else { return .success }
        Task {
            do {
                try await AppState.shared.subsonicClient.unstar(id: song.id)
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "RemoteCommand")
                    .error("Failed to unstar track: \(error)")
            }
        }
        return .success
    }

    // MARK: - Registration

    private func setupPlaybackCommands() {
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in self.handlePlay() }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in self.handlePause() }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in self.handleTogglePlayPause() }
    }

    private func setupNavigationCommands() {
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in self.handleNextTrack() }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in self.handlePreviousTrack() }
    }

    private func setupSeekCommands() {
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            self.handleChangePlaybackPosition(
                to: (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
            )
        }
    }

    private func setupSkipCommands() {
        // Disable skip forward/backward so iOS shows next/previous track
        // buttons on the lock screen instead of 15-second skip buttons.
        // The seek bar handles position scrubbing.
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
    }

    private func setupRatingCommands() {
        commandCenter.likeCommand.isEnabled = true
        commandCenter.likeCommand.addTarget { _ in self.handleLike() }

        commandCenter.dislikeCommand.isEnabled = true
        commandCenter.dislikeCommand.addTarget { _ in self.handleDislike() }
    }
}
