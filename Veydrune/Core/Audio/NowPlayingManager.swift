import Foundation
import MediaPlayer
#if os(macOS)
import AppKit
#endif

@MainActor
final class NowPlayingManager {
    static let shared = NowPlayingManager()
    private let infoCenter = MPNowPlayingInfoCenter.default()

    private var currentInfo = [String: Any]()

    func update(song: Song, isPlaying: Bool) {
        currentInfo = [String: Any]()
        currentInfo[MPMediaItemPropertyTitle] = song.title
        currentInfo[MPMediaItemPropertyArtist] = song.artist ?? "Unknown Artist"
        currentInfo[MPMediaItemPropertyAlbumTitle] = song.album ?? ""
        currentInfo[MPMediaItemPropertyPlaybackDuration] = song.duration ?? 0
        currentInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        currentInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

        if let track = song.track {
            currentInfo[MPMediaItemPropertyAlbumTrackNumber] = track
        }

        infoCenter.nowPlayingInfo = currentInfo

        // Load cover art asynchronously
        if let coverArtId = song.coverArt {
            let songId = song.id
            let url = AppState.shared.subsonicClient.coverArtURL(id: coverArtId, size: 600)
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    // Verify we're still on the same song before applying artwork
                    guard AudioEngine.shared.currentSong?.id == songId else { return }
                    #if os(iOS)
                    guard let image = UIImage(data: data) else { return }
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    #else
                    guard let image = NSImage(data: data) else { return }
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    #endif
                    self.currentInfo[MPMediaItemPropertyArtwork] = artwork
                    self.infoCenter.nowPlayingInfo = self.currentInfo
                } catch {
                    // Cover art loading failed, not critical
                }
            }
        }
    }

    func updateElapsedTime(_ time: TimeInterval) {
        currentInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
        infoCenter.nowPlayingInfo = currentInfo
    }

    func updateDuration(_ duration: TimeInterval) {
        currentInfo[MPMediaItemPropertyPlaybackDuration] = duration
        infoCenter.nowPlayingInfo = currentInfo
    }

    func updatePlaybackState(isPlaying: Bool, elapsed: TimeInterval) {
        currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        currentInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        infoCenter.nowPlayingInfo = currentInfo
    }

    func clear() {
        currentInfo.removeAll()
        infoCenter.nowPlayingInfo = nil
    }
}
