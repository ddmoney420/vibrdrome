import SwiftUI
import Network

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab = "library"
    @State private var libraryNavPath = NavigationPath()
    @State private var isOffline = false
    @AppStorage(UserDefaultsKeys.tabBarOrder) private var tabBarOrderJSON = "[]"
    @AppStorage(UserDefaultsKeys.showSearchTab) private var showSearchTab = true
    @AppStorage(UserDefaultsKeys.showPlaylistsTab) private var showPlaylistsTab = true
    @AppStorage(UserDefaultsKeys.showRadioTab) private var showRadioTab = true
    @AppStorage(UserDefaultsKeys.settingsInNavBar) private var settingsInNavBar = false
    @AppStorage(UserDefaultsKeys.showDownloadsTab) private var showDownloadsTab = false
    @AppStorage(UserDefaultsKeys.showArtistsTab) private var showArtistsTab = false
    @AppStorage(UserDefaultsKeys.showAlbumsTab) private var showAlbumsTab = false
    @AppStorage(UserDefaultsKeys.showSongsTab) private var showSongsTab = false
    @AppStorage(UserDefaultsKeys.showGenresTab) private var showGenresTab = false
    @AppStorage(UserDefaultsKeys.showFavoritesTab) private var showFavoritesTab = false

    private var engine: AudioEngine { AudioEngine.shared }

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
        #if os(iOS)
        .background(Color(.systemBackground))
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: Bindable(appState).showNowPlaying, onDismiss: {
            handlePendingNavigation()
        }) {
            NowPlayingView()
                .environment(appState)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
        #endif
        .onChange(of: scenePhase) { _, newPhase in
            guard appState.isConfigured else { return }
            switch newPhase {
            case .background:
                engine.savePlayQueue(client: appState.subsonicClient)
                engine.saveQueueLocally()
                engine.createBookmarkIfNeeded(client: appState.subsonicClient)
            case .active:
                engine.restorePlayQueue(client: appState.subsonicClient)
                engine.refreshPlaybackState()
                handleWidgetCommand()
                if !isOffline {
                    autoSyncIfNeeded()
                }
            default:
                break
            }
        }
        .overlay(alignment: .top) {
            if isOffline {
                Button {
                    selectedTab = "library"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        libraryNavPath.append(OfflineNavItem())
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.caption)
                        Text("Offline — Tap to browse downloads")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.orange.gradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: isOffline)
            }
        }
        .onChange(of: appState.pendingNavigation) { _, newValue in
            if newValue != nil && !appState.showNowPlaying {
                handlePendingNavigation()
            }
        }
        .task {
            let monitor = NWPathMonitor()
            for await path in monitor.paths() {
                withAnimation {
                    isOffline = path.status != .satisfied
                }
            }
        }
        .sheet(isPresented: Bindable(appState).requiresReAuth) {
            ReAuthView()
                .environment(appState)
                .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private var mainTabView: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            modernTabView
        } else {
            legacyTabView
        }
    }

    private var orderedTabIds: [String] {
        if let data = tabBarOrderJSON.data(using: .utf8),
           let saved = try? JSONDecoder().decode([String].self, from: data),
           !saved.isEmpty {
            // Ensure all known tabs are in the list (append missing ones)
            let allIds = ["library", "artists", "albums", "songs", "genres",
                          "favorites", "search", "playlists", "radio", "downloads", "settings"]
            var result = saved.filter { allIds.contains($0) }
            for id in allIds where !result.contains(id) {
                result.append(id)
            }
            return result
        }
        return ["library", "artists", "albums", "songs", "genres",
                "favorites", "search", "playlists", "radio", "downloads", "settings"]
    }

    private func isTabVisible(_ id: String) -> Bool {
        switch id {
        case "library": return true
        case "artists": return showArtistsTab
        case "albums": return showAlbumsTab
        case "songs": return showSongsTab
        case "genres": return showGenresTab
        case "favorites": return showFavoritesTab
        case "search": return showSearchTab
        case "playlists": return showPlaylistsTab
        case "radio": return showRadioTab
        case "downloads": return showDownloadsTab
        case "settings": return !settingsInNavBar
        default: return false
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    private var modernTabView: some View {
        let order = orderedTabIds
        return TabView(selection: $selectedTab) {
            // Tabs rendered in saved order. Each tab checks its own visibility.
            // Home is always first regardless of saved order.
            Tab("Home", systemImage: "house", value: "library") {
                LibraryView(navPath: $libraryNavPath)
            }
            ForEach(order.filter { $0 != "library" && isTabVisible($0) }, id: \.self) { tabId in
                // Use AnyView to erase types in ForEach
                Tab(tabLabel(tabId), systemImage: tabIcon(tabId), value: tabId) {
                    tabView(for: tabId)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .id(tabBarOrderJSON)
        .animation(.smooth, value: selectedTab)
        .onChange(of: selectedTab) { _, _ in
            #if os(iOS)
            Haptics.light()
            #endif
        }
        .overlay(alignment: .bottom) {
            if engine.currentSong != nil || engine.currentRadioStation != nil {
                MiniPlayerView()
                    .padding(.bottom, 54)
            }
        }
    }

    private func tabLabel(_ id: String) -> String {
        switch id {
        case "artists": return "Artists"
        case "albums": return "Albums"
        case "songs": return "Songs"
        case "genres": return "Genres"
        case "favorites": return "Favorites"
        case "search": return "Search"
        case "playlists": return "Playlists"
        case "radio": return "Radio"
        case "downloads": return "Downloads"
        case "settings": return "Settings"
        default: return "Home"
        }
    }

    private func tabIcon(_ id: String) -> String {
        switch id {
        case "artists": return "music.mic"
        case "albums": return "square.stack.fill"
        case "songs": return "music.note"
        case "genres": return "guitars.fill"
        case "favorites": return "heart.fill"
        case "search": return "magnifyingglass"
        case "playlists": return "music.note.list"
        case "radio": return "antenna.radiowaves.left.and.right"
        case "downloads": return "arrow.down.circle"
        case "settings": return "gear"
        default: return "house"
        }
    }

    @ViewBuilder
    private func tabView(for id: String) -> some View {
        switch id {
        case "artists": NavigationStack { ArtistsView() }
        case "albums": NavigationStack { AlbumsView(listType: .alphabeticalByName, title: "Albums") }
        case "songs": NavigationStack { SongsView() }
        case "genres": NavigationStack { GenresView() }
        case "favorites": NavigationStack { FavoritesView() }
        case "search": NavigationStack { SearchView() }
        case "playlists": NavigationStack { PlaylistsView() }
        case "radio": NavigationStack { RadioView() }
        case "downloads": NavigationStack { DownloadsView() }
        case "settings": NavigationStack { SettingsView() }
        default: EmptyView()
        }
    }

    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            LibraryView(navPath: $libraryNavPath)
                .tabItem { Label("Home", systemImage: "house") }
                .tag("library")
            if showArtistsTab {
                NavigationStack { ArtistsView() }
                    .tabItem { Label("Artists", systemImage: "music.mic") }
                    .tag("artists")
            }
            if showAlbumsTab {
                NavigationStack { AlbumsView(listType: .alphabeticalByName, title: "Albums") }
                    .tabItem { Label("Albums", systemImage: "square.stack.fill") }
                    .tag("albums")
            }
            if showSongsTab {
                NavigationStack { SongsView() }
                    .tabItem { Label("Songs", systemImage: "music.note") }
                    .tag("songs")
            }
            if showGenresTab {
                NavigationStack { GenresView() }
                    .tabItem { Label("Genres", systemImage: "guitars.fill") }
                    .tag("genres")
            }
            if showFavoritesTab {
                NavigationStack { FavoritesView() }
                    .tabItem { Label("Favorites", systemImage: "heart.fill") }
                    .tag("favorites")
            }
            if showSearchTab {
                NavigationStack { SearchView() }
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag("search")
            }
            if showPlaylistsTab {
                NavigationStack { PlaylistsView() }
                    .tabItem { Label("Playlists", systemImage: "music.note.list") }
                    .tag("playlists")
            }
            if showRadioTab {
                NavigationStack { RadioView() }
                    .tabItem { Label("Radio", systemImage: "antenna.radiowaves.left.and.right") }
                    .tag("radio")
            }
            if showDownloadsTab {
                NavigationStack { DownloadsView() }
                    .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                    .tag("downloads")
            }
            if !settingsInNavBar {
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag("settings")
            }
        }
        .animation(.smooth, value: selectedTab)
        .onChange(of: selectedTab) { _, _ in
            #if os(iOS)
            Haptics.light()
            #endif
        }
        .overlay(alignment: .bottom) {
            if engine.currentSong != nil || engine.currentRadioStation != nil {
                MiniPlayerView()
                    .padding(.bottom, 54)
            }
        }
    }

    private func handlePendingNavigation() {
        guard let nav = appState.pendingNavigation else { return }
        appState.pendingNavigation = nil
        selectedTab = "library"
        // Small delay to ensure tab switch completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch nav {
            case .artist(let id):
                libraryNavPath.append(ArtistNavItem(id: id))
            case .album(let id):
                libraryNavPath.append(AlbumNavItem(id: id))
            case .song(let id):
                libraryNavPath.append(SongNavItem(id: id))
            case .genre(let name):
                libraryNavPath.append(GenreNavItem(name: name))
            case .playlist(let id):
                libraryNavPath.append(PlaylistNavItem(id: id))
            }
        }
    }

    private func autoSyncIfNeeded() {
        guard appState.isConfigured else { return }
        let client = appState.subsonicClient

        // Auto-sync playlists
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoSyncPlaylists) {
            Task {
                guard let playlists = try? await client.getPlaylists() else { return }
                for playlist in playlists {
                    guard let detail = try? await client.getPlaylist(id: playlist.id),
                          let songs = detail.entry else { continue }
                    for song in songs {
                        DownloadManager.shared.download(song: song, client: client)
                    }
                }
            }
        }

        // Auto-sync favorites
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoDownloadFavorites) {
            Task {
                guard let starred = try? await client.getStarred(),
                      let songs = starred.song else { return }
                for song in songs {
                    DownloadManager.shared.download(song: song, client: client)
                }
            }
        }
    }

    private func handleWidgetCommand() {
        guard let command = WidgetCommand.consume() else { return }
        switch command {
        case .togglePlayback:
            engine.togglePlayPause()
        case .skipTrack:
            engine.next()
        }
    }
}

// Navigation items for typed NavigationPath
struct ArtistNavItem: Hashable {
    let id: String
}

struct AlbumNavItem: Hashable {
    let id: String
}

struct GenreNavItem: Hashable {
    let name: String
}

struct PlaylistNavItem: Hashable {
    let id: String
}

struct SongNavItem: Hashable {
    let id: String
}

struct OfflineNavItem: Hashable {
}

// MARK: - NWPathMonitor AsyncStream

extension NWPathMonitor {
    func paths() -> AsyncStream<NWPath> {
        AsyncStream { continuation in
            pathUpdateHandler = { path in
                continuation.yield(path)
            }
            start(queue: DispatchQueue(label: "com.vibrdrome.networkmonitor"))
            continuation.onTermination = { @Sendable _ in
                self.cancel()
            }
        }
    }
}
