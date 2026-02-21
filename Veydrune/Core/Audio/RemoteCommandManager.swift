import Foundation
import MediaPlayer

@MainActor
final class RemoteCommandManager {
    static let shared = RemoteCommandManager()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var isSetup = false

    func setup() {
        guard !isSetup else { return }
        isSetup = true

        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            AudioEngine.shared.resume()
            return .success
        }

        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            AudioEngine.shared.pause()
            return .success
        }

        // Toggle play/pause
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            AudioEngine.shared.togglePlayPause()
            return .success
        }

        // Next track
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            AudioEngine.shared.next()
            return .success
        }

        // Previous track
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            AudioEngine.shared.previous()
            return .success
        }

        // Seek (scrubbing)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            AudioEngine.shared.seek(to: event.positionTime)
            return .success
        }

        // Skip forward (15 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { _ in
            let engine = AudioEngine.shared
            guard engine.duration > 0 else { return .commandFailed }
            let target = min(engine.currentTime + 15, engine.duration - 0.5)
            engine.seek(to: max(0, target))
            return .success
        }

        // Skip backward (15 seconds)
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { _ in
            let engine = AudioEngine.shared
            guard engine.duration > 0 else { return .commandFailed }
            engine.seek(to: max(0, engine.currentTime - 15))
            return .success
        }

        // Like (star) — shows thumbs-up in CarPlay
        commandCenter.likeCommand.isEnabled = true
        commandCenter.likeCommand.addTarget { _ in
            if let song = AudioEngine.shared.currentSong {
                Task { @MainActor in
                    try? await AppState.shared.subsonicClient.star(id: song.id)
                    if UserDefaults.standard.bool(forKey: "autoDownloadFavorites") {
                        DownloadManager.shared.download(song: song, client: AppState.shared.subsonicClient)
                    }
                }
            }
            return .success
        }

        // Dislike (unstar) — shows thumbs-down in CarPlay
        commandCenter.dislikeCommand.isEnabled = true
        commandCenter.dislikeCommand.addTarget { _ in
            if let song = AudioEngine.shared.currentSong {
                Task {
                    try? await AppState.shared.subsonicClient.unstar(id: song.id)
                }
            }
            return .success
        }
    }
}
