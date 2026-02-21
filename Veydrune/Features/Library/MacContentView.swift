#if os(macOS)
import SwiftUI

struct MacContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    private var engine: AudioEngine { AudioEngine.shared }

    private var windowTitle: String {
        if let song = engine.currentSong {
            let artist = song.artist ?? ""
            return artist.isEmpty ? "\(song.title) — Veydrune" : "\(song.title) - \(artist) — Veydrune"
        }
        if let station = engine.currentRadioStation {
            return "\(station.name) — Veydrune"
        }
        return "Veydrune"
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
            try? await appState.subsonicClient.savePlayQueue(
                ids: ids, current: currentId, position: position)
        }
    }

    private func createBookmarkIfNeeded() {
        guard let song = engine.currentSong,
              engine.currentTime > 30 else { return }
        let position = Int(engine.currentTime * 1000)
        Task {
            try? await appState.subsonicClient.createBookmark(
                id: song.id, position: position, comment: "Auto-bookmark")
        }
    }

    private func restorePlayQueue() {
        guard engine.currentSong == nil, engine.queue.isEmpty else { return }
        Task {
            guard let playQueue = try? await appState.subsonicClient.getPlayQueue(),
                  let songs = playQueue.entry, !songs.isEmpty else { return }

            engine.queue = songs

            if let currentId = playQueue.current,
               let index = songs.firstIndex(where: { $0.id == currentId }) {
                engine.currentIndex = index
                engine.currentSong = songs[index]
                if let position = playQueue.position, position > 0 {
                    engine.currentTime = Double(position) / 1000.0
                }
                NowPlayingManager.shared.update(song: songs[index], isPlaying: false)
            }
        }
    }
}
#endif
