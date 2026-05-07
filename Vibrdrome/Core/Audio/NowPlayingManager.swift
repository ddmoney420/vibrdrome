import Foundation
import MediaPlayer
import WidgetKit
import os.log
#if os(macOS)
import AppKit
#endif

private let npLog = Logger(subsystem: "com.vibrdrome.app", category: "NowPlaying")

// Free function outside @MainActor class so the closure doesn't inherit MainActor isolation.
// MPMediaItemArtwork calls its requestHandler on an internal background queue (*/accessQueue),
// which would crash if the closure were @MainActor-isolated.
#if os(iOS)
private func makeArtwork(from image: UIImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
}
#else
private func makeArtwork(from image: NSImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
}
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

        // Update widget
        updateWidget(title: song.title, artist: song.artist ?? "",
                     album: song.album ?? "", isPlaying: isPlaying,
                     coverArtId: song.coverArt)

        // Update watch companion app
        #if os(iOS)
        WatchSessionManager.shared.sendNowPlayingUpdate(
            title: song.title,
            artist: song.artist ?? "Unknown Artist",
            album: song.album ?? "",
            isPlaying: isPlaying
        )
        #endif

        // Update Discord Rich Presence
        #if os(macOS)
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.discordRPCEnabled) {
            let presenceInfo = DiscordPresenceInfo(
                title: song.title,
                artist: song.artist ?? "Unknown Artist",
                album: song.album,
                isPlaying: isPlaying,
                elapsed: 0,
                duration: song.duration.map { TimeInterval($0) }
            )
            Task {
                await DiscordRPCClient.shared.updatePresence(presenceInfo)
            }
        }
        #endif

        Task { await loadAndApplyArtwork(for: song) }
    }

    func update(station: InternetRadioStation, isPlaying: Bool) {
        currentInfo = [String: Any]()
        currentInfo[MPMediaItemPropertyTitle] = station.name
        currentInfo[MPMediaItemPropertyArtist] = "Internet Radio"
        currentInfo[MPMediaItemPropertyAlbumTitle] = ""
        currentInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        currentInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        currentInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        currentInfo.removeValue(forKey: MPMediaItemPropertyArtwork)
        infoCenter.nowPlayingInfo = currentInfo

        updateWidget(title: station.name, artist: "Internet Radio",
                     album: "", isPlaying: isPlaying,
                     coverArtId: station.radioCoverArtId)

        #if os(iOS)
        WatchSessionManager.shared.sendNowPlayingUpdate(
            title: station.name,
            artist: "Internet Radio",
            album: "",
            isPlaying: isPlaying
        )
        #endif
    }

    func setCurrentArtwork(_ artwork: MPMediaItemArtwork?) {
        if let artwork {
            currentInfo[MPMediaItemPropertyArtwork] = artwork
        } else {
            currentInfo.removeValue(forKey: MPMediaItemPropertyArtwork)
        }
        infoCenter.nowPlayingInfo = currentInfo
    }

    private func loadAndApplyArtwork(for song: Song) async {
        guard let coverArtId = song.coverArt else {
            npLog.warning("No coverArt ID for \(song.title)")
            return
        }
        let songId = song.id
        let url = AppState.shared.subsonicClient.coverArtURL(id: coverArtId, size: 600)
        npLog.info("Loading cover art for \(song.title) (id: \(songId))")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard AudioEngine.shared.currentSong?.id == songId else {
                npLog.warning("Song changed during art load, skipping (was: \(songId))")
                return
            }
            #if os(iOS)
            guard let image = UIImage(data: data) else {
                npLog.error("Failed to create UIImage from \(data.count) bytes")
                return
            }
            #else
            guard let image = NSImage(data: data) else { return }
            #endif
            currentInfo[MPMediaItemPropertyArtwork] = makeArtwork(from: image)
            infoCenter.nowPlayingInfo = currentInfo
            #if os(iOS)
            npLog.info("Sending artwork to watch (\(Int(image.size.width))x\(Int(image.size.height)))")
            sendArtworkToWatch(image: image, song: song)
            #endif
        } catch {
            npLog.error("Cover art load failed: \(error)")
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

        // Update watch companion app
        #if os(iOS)
        WatchSessionManager.shared.sendPlaybackStateUpdate(isPlaying: isPlaying)
        #endif

        // Update widget play/pause state
        if let state = NowPlayingState.load() {
            let updated = NowPlayingState(
                title: state.title, artist: state.artist, album: state.album,
                isPlaying: isPlaying, coverArtId: state.coverArtId,
                serverURL: state.serverURL, timestamp: .now
            )
            updated.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func updatePlaybackRate(_ rate: Float) {
        currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
        currentInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = rate
        infoCenter.nowPlayingInfo = currentInfo
    }

    func clear() {
        currentInfo.removeAll()
        infoCenter.nowPlayingInfo = nil
        NowPlayingState.clear()
        WidgetCenter.shared.reloadAllTimelines()

        // Clear Discord Rich Presence
        #if os(macOS)
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.discordRPCEnabled) {
            Task {
                await DiscordRPCClient.shared.clearPresence()
            }
        }
        #endif
    }

    #if os(iOS)
    private func sendArtworkToWatch(image: UIImage, song: Song) {
        guard let small = image.preparingThumbnail(of: CGSize(width: 120, height: 120)) else {
            npLog.error("Failed to create 120x120 thumbnail")
            return
        }
        guard let jpegData = small.jpegData(compressionQuality: 0.6) else {
            npLog.error("Failed to create JPEG from thumbnail")
            return
        }
        npLog.info("Watch art ready: \(jpegData.count) bytes")
        WatchSessionManager.shared.sendNowPlayingUpdate(
            title: song.title,
            artist: song.artist ?? "Unknown Artist",
            album: song.album ?? "",
            isPlaying: AudioEngine.shared.isPlaying,
            coverArtData: jpegData
        )
    }
    #endif

    private func updateWidget(title: String, artist: String, album: String,
                              isPlaying: Bool, coverArtId: String?) {
        let state = NowPlayingState(
            title: title, artist: artist, album: album,
            isPlaying: isPlaying, coverArtId: coverArtId,
            serverURL: AppState.shared.serverURL,
            timestamp: .now
        )
        state.save()

        // Cache cover art for the widget
        if let coverArtId {
            let url = AppState.shared.subsonicClient.coverArtURL(id: coverArtId, size: 200)
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                NowPlayingState.shared?.set(data, forKey: "widgetCoverArt_\(coverArtId)")
                WidgetCenter.shared.reloadAllTimelines()
            }
        } else {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
