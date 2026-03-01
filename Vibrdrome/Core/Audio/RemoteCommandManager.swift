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
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { _ in
            let engine = AudioEngine.shared
            guard engine.duration > 0 else { return .commandFailed }
            let target = min(engine.currentTime + 15, engine.duration - 0.5)
            engine.seek(to: max(0, target))
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { _ in
            let engine = AudioEngine.shared
            guard engine.duration > 0 else { return .commandFailed }
            engine.seek(to: max(0, engine.currentTime - 15))
            return .success
        }
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
