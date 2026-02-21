#if os(macOS)
import SwiftUI

struct MacContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: SidebarItem? = .artists

    private var engine: AudioEngine { AudioEngine.shared }

    enum SidebarItem: String, CaseIterable, Hashable {
        case artists, albums, genres, favorites, recentlyAdded, mostPlayed, recentlyPlayed, random
        case bookmarks
        case search
        case playlists
        case radio
        case downloads
        case settings
    }

    var body: some View {
        Group {
            if appState.isConfigured {
                mainView
            } else {
                ServerConfigView()
                    .environment(appState)
            }
        }
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

    private var mainView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    Label("Artists", systemImage: "music.mic")
                        .tag(SidebarItem.artists)
                    Label("Albums", systemImage: "square.stack")
                        .tag(SidebarItem.albums)
                    Label("Genres", systemImage: "guitars")
                        .tag(SidebarItem.genres)
                    Label("Favorites", systemImage: "heart.fill")
                        .tag(SidebarItem.favorites)
                    Label("Recently Added", systemImage: "clock")
                        .tag(SidebarItem.recentlyAdded)
                    Label("Most Played", systemImage: "star")
                        .tag(SidebarItem.mostPlayed)
                    Label("Recently Played", systemImage: "play.circle")
                        .tag(SidebarItem.recentlyPlayed)
                    Label("Random", systemImage: "shuffle")
                        .tag(SidebarItem.random)
                    Label("Bookmarks", systemImage: "bookmark")
                        .tag(SidebarItem.bookmarks)
                    Label("Downloads", systemImage: "arrow.down.circle")
                        .tag(SidebarItem.downloads)
                    Label("Search", systemImage: "magnifyingglass")
                        .tag(SidebarItem.search)
                }
                Section("Playlists") {
                    Label("Playlists", systemImage: "music.note.list")
                        .tag(SidebarItem.playlists)
                }
                Section("Radio") {
                    Label("Stations", systemImage: "antenna.radiowaves.left.and.right")
                        .tag(SidebarItem.radio)
                }
                Section {
                    Label("Settings", systemImage: "gear")
                        .tag(SidebarItem.settings)
                }
            }
            .navigationTitle("Veydrune")
        } detail: {
            detailView
        }
        .safeAreaInset(edge: .bottom) {
            if engine.currentSong != nil || engine.currentRadioStation != nil {
                MiniPlayerView()
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .artists:
            ArtistsView()
        case .albums:
            AlbumsView(listType: .alphabeticalByName, title: "Albums")
        case .genres:
            GenresView()
        case .favorites:
            FavoritesView()
        case .recentlyAdded:
            AlbumsView(listType: .newest, title: "Recently Added")
        case .mostPlayed:
            AlbumsView(listType: .frequent, title: "Most Played")
        case .recentlyPlayed:
            AlbumsView(listType: .recent, title: "Recently Played")
        case .random:
            AlbumsView(listType: .random, title: "Random")
        case .bookmarks:
            BookmarksView()
        case .downloads:
            DownloadsView()
        case .search:
            SearchView()
        case .playlists:
            PlaylistsView()
        case .radio:
            RadioView()
        case .settings:
            SettingsView()
        case nil:
            ContentUnavailableView {
                Label("Select a Section", systemImage: "music.note.house")
            } description: {
                Text("Choose a section from the sidebar")
            }
        }
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
