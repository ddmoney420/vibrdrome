import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var engine: AudioEngine { AudioEngine.shared }
    @State private var showMiniPlayer = true
    @State private var hideTask: Task<Void, Never>?
    @AppStorage("reduceMotion") private var reduceMotion = false

    var body: some View {
        Group {
            if appState.isConfigured {
                if sizeClass == .regular {
                    // iPad — sidebar layout
                    SidebarContentView()
                } else {
                    // iPhone — tab bar layout
                    mainTabView
                }
            } else {
                ServerConfigView()
                    .environment(appState)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard appState.isConfigured else { return }
            switch newPhase {
            case .background:
                savePlayQueue()
                createBookmarkIfNeeded()
            case .active:
                restorePlayQueue()
            default:
                break
            }
        }
    }

    private var mainTabView: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "music.note.house") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            PlaylistsView()
                .tabItem { Label("Playlists", systemImage: "music.note.list") }
            RadioView()
                .tabItem { Label("Radio", systemImage: "antenna.radiowaves.left.and.right") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .overlay(alignment: .bottom) {
            if engine.currentSong != nil || engine.currentRadioStation != nil {
                MiniPlayerView()
                    .padding(.bottom, 68)
                    .offset(y: showMiniPlayer ? 0 : 140)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showMiniPlayer)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 15)
                .onChanged { _ in
                    hideTask?.cancel()
                    if showMiniPlayer {
                        showMiniPlayer = false
                    }
                }
                .onEnded { _ in
                    hideTask?.cancel()
                    hideTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        showMiniPlayer = true
                    }
                }
        )
    }

    // MARK: - Play Queue Persistence

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
        // Only restore if nothing is currently playing
        guard engine.currentSong == nil, engine.queue.isEmpty else { return }
        Task {
            guard let playQueue = try? await appState.subsonicClient.getPlayQueue(),
                  let songs = playQueue.entry, !songs.isEmpty else { return }

            engine.queue = songs

            if let currentId = playQueue.current,
               let index = songs.firstIndex(where: { $0.id == currentId }) {
                engine.currentIndex = index
                // Load the song but don't auto-play
                engine.currentSong = songs[index]
                // V2: Restore saved position
                if let position = playQueue.position, position > 0 {
                    engine.currentTime = Double(position) / 1000.0
                }
                NowPlayingManager.shared.update(song: songs[index], isPlaying: false)
            }
        }
    }
}
