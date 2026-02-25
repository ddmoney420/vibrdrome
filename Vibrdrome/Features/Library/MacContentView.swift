#if os(macOS)
import os.log
import SwiftUI

struct MacContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    private var engine: AudioEngine { AudioEngine.shared }

    private var windowTitle: String {
        if let song = engine.currentSong {
            let artist = song.artist ?? ""
            return artist.isEmpty ? "\(song.title) — Vibrdrome" : "\(song.title) - \(artist) — Vibrdrome"
        }
        if let station = engine.currentRadioStation {
            return "\(station.name) — Vibrdrome"
        }
        return "Vibrdrome"
    }

    var body: some View {
        Group {
            if appState.isConfigured {
                SidebarContentView()
            } else {
                ServerConfigView()
                    .environment(appState)
            }
        }
        .navigationTitle(windowTitle)
        .onChange(of: scenePhase) { _, newPhase in
            guard appState.isConfigured else { return }
            switch newPhase {
            case .inactive:
                // macOS rarely gets .background; save on .inactive
                savePlayQueue()
                createBookmarkIfNeeded()
            case .active:
                restorePlayQueue()
            default:
                break
            }
        }
    }

    private func savePlayQueue() {
        let queue = engine.queue
        guard !queue.isEmpty else { return }
        let ids = queue.map(\.id)
        let currentId = engine.currentSong?.id
        let position = Int(engine.currentTime * 1000)
        Task {
            do {
                try await appState.subsonicClient.savePlayQueue(
                    ids: ids, current: currentId, position: position)
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "PlayQueue")
                    .error("Failed to save play queue: \(error)")
            }
        }
    }

    private func createBookmarkIfNeeded() {
        guard let song = engine.currentSong,
              engine.currentTime > 30 else { return }
        let position = Int(engine.currentTime * 1000)
        Task {
            do {
                try await appState.subsonicClient.createBookmark(
                    id: song.id, position: position, comment: "Auto-bookmark")
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "PlayQueue")
                    .error("Failed to create auto-bookmark: \(error)")
            }
        }
    }

    private func restorePlayQueue() {
        guard engine.currentSong == nil, engine.queue.isEmpty else { return }
        Task {
            let playQueue: PlayQueue?
            do {
                playQueue = try await appState.subsonicClient.getPlayQueue()
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "PlayQueue")
                    .error("Failed to restore play queue: \(error.localizedDescription)")
                return
            }
            guard let songs = playQueue?.entry, !songs.isEmpty else { return }

            engine.queue = songs

            if let currentId = playQueue?.current,
               let index = songs.firstIndex(where: { $0.id == currentId }) {
                engine.currentIndex = index
                engine.currentSong = songs[index]
                if let position = playQueue?.position, position > 0 {
                    engine.currentTime = Double(position) / 1000.0
                }
                NowPlayingManager.shared.update(song: songs[index], isPlaying: false)
            }
        }
    }
}
#endif
