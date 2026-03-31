import Foundation
import MediaPlayer
import os.log

@MainActor
final class RemoteCommandManager {
    static let shared = RemoteCommandManager()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var isSetup = false

    func setup() {
        guard !isSetup else { return }
        isSetup = true

        setupPlaybackCommands()
        setupNavigationCommands()
        setupSeekCommands()
        setupSkipCommands()
        setupRatingCommands()
    }

    private func setupPlaybackCommands() {
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            AudioEngine.shared.resume()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            AudioEngine.shared.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            AudioEngine.shared.togglePlayPause()
            return .success
        }
    }

    private func setupNavigationCommands() {
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            AudioEngine.shared.next()
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            AudioEngine.shared.previous()
            return .success
        }
    }

    private func setupSeekCommands() {
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            AudioEngine.shared.seek(to: event.positionTime)
            return .success
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
        commandCenter.likeCommand.addTarget { _ in
            if let song = AudioEngine.shared.currentSong {
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
            }
            return .success
        }

        commandCenter.dislikeCommand.isEnabled = true
        commandCenter.dislikeCommand.addTarget { _ in
            if let song = AudioEngine.shared.currentSong {
                Task {
                    do {
                        try await AppState.shared.subsonicClient.unstar(id: song.id)
                    } catch {
                        Logger(subsystem: "com.vibrdrome.app", category: "RemoteCommand")
                            .error("Failed to unstar track: \(error)")
                    }
                }
            }
            return .success
        }
    }
}
