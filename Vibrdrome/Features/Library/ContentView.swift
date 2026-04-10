import SwiftUI
import Network

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab = 0
    @State private var libraryNavPath = NavigationPath()
    @State private var isOffline = false
    @AppStorage(UserDefaultsKeys.showSearchTab) private var showSearchTab = true
    @AppStorage(UserDefaultsKeys.showPlaylistsTab) private var showPlaylistsTab = true
    @AppStorage(UserDefaultsKeys.showRadioTab) private var showRadioTab = true
    @AppStorage(UserDefaultsKeys.settingsInNavBar) private var settingsInNavBar = false
    @AppStorage(UserDefaultsKeys.showDownloadsTab) private var showDownloadsTab = false

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
                    selectedTab = 0
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

    @available(iOS 18.0, macOS 15.0, *)
    private var modernTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: 0) {
                LibraryView(navPath: $libraryNavPath)
            }
            if showSearchTab {
                Tab("Search", systemImage: "magnifyingglass", value: 1) {
                    NavigationStack { SearchView() }
                }
            }
            if showPlaylistsTab {
                Tab("Playlists", systemImage: "music.note.list", value: 2) {
                    NavigationStack { PlaylistsView() }
                }
            }
            if showRadioTab {
                Tab("Radio", systemImage: "antenna.radiowaves.left.and.right", value: 3) {
                    NavigationStack { RadioView() }
                }
            }
            if showDownloadsTab {
                Tab("Downloads", systemImage: "arrow.down.circle", value: 5) {
                    NavigationStack { DownloadsView() }
                }
            }
            if !settingsInNavBar {
                Tab("Settings", systemImage: "gear", value: 4) {
                    NavigationStack { SettingsView() }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
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

    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            LibraryView(navPath: $libraryNavPath)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            if showSearchTab {
                NavigationStack { SearchView() }
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(1)
            }
            if showPlaylistsTab {
                NavigationStack { PlaylistsView() }
                    .tabItem { Label("Playlists", systemImage: "music.note.list") }
                    .tag(2)
            }
            if showRadioTab {
                NavigationStack { RadioView() }
                    .tabItem { Label("Radio", systemImage: "antenna.radiowaves.left.and.right") }
                    .tag(3)
            }
            if showDownloadsTab {
                NavigationStack { DownloadsView() }
                    .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                    .tag(5)
                }
            if !settingsInNavBar {
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag(4)
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
        selectedTab = 0
        // Small delay to ensure tab switch completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch nav {
            case .artist(let id):
                libraryNavPath.append(ArtistNavItem(id: id))
            case .album(let id):
                libraryNavPath.append(AlbumNavItem(id: id))
            case .genre(let name):
                libraryNavPath.append(GenreNavItem(name: name))
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
