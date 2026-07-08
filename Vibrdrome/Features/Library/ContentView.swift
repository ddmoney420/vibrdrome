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
    @AppStorage(UserDefaultsKeys.showPlaylistsTab) private var showPlaylistsTab = false
    @AppStorage(UserDefaultsKeys.showRadioTab) private var showRadioTab = true
    @AppStorage(UserDefaultsKeys.showLibraryHomeTab) private var showLibraryHomeTab = true
    @AppStorage(UserDefaultsKeys.settingsInNavBar) private var settingsInNavBar = false
    @AppStorage(UserDefaultsKeys.showDownloadsTab) private var showDownloadsTab = false
    @AppStorage(UserDefaultsKeys.showArtistsTab) private var showArtistsTab = false
    @AppStorage(UserDefaultsKeys.showAlbumsTab) private var showAlbumsTab = false
    @AppStorage(UserDefaultsKeys.showSongsTab) private var showSongsTab = false
    @AppStorage(UserDefaultsKeys.showGenresTab) private var showGenresTab = false
    @AppStorage(UserDefaultsKeys.showFavoritesTab) private var showFavoritesTab = true

    private var engine: AudioEngine { AudioEngine.shared }

    /// Baseline gap between the mini player and a phone that has a bottom
    /// safe-area inset (notched). These phones get their home-indicator inset
    /// "for free" from the safe-area-respecting overlay, so 54pt on top clears
    /// the tab bar.
    private static let miniPlayerBaseClearance: CGFloat = 54

    /// Clearance for the smallest phones, which have **no** bottom safe-area
    /// inset (iPhone SE / mini). iOS 26's tab bar is taller, so the old fixed
    /// 54pt overlapped the tab-bar icons there (#69). Subtracting the live
    /// bottom inset means notched phones floor back to `miniPlayerBaseClearance`
    /// and stay exactly as before, while zero-inset phones get the full value.
    private static let miniPlayerTabBarClearance: CGFloat = 72

    /// The mini player, hung above the tab bar. Shared by both tab-bar layouts
    /// so the clearance stays consistent. Uses a `GeometryReader` to read the
    /// live bottom safe-area inset (SwiftUI-native, no UIKit).
    @ViewBuilder
    private var miniPlayerOverlay: some View {
        if engine.currentSong != nil || engine.currentRadioStation != nil {
            GeometryReader { geometry in
                let clearance = max(Self.miniPlayerBaseClearance,
                                    Self.miniPlayerTabBarClearance - geometry.safeAreaInsets.bottom)
                MiniPlayerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, clearance)
            }
            // Pin to the screen bottom regardless of keyboard presence. Without
            // this, iPad floating keyboards drag the mini player up to where a
            // docked keyboard would sit.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    /// Attach the mini player to a tab view. On iOS 26+ it becomes a system `tabViewBottomAccessory`,
    /// auto-positioned above the tab bar on every device (#91, follow-up to #69). On iOS 18–25 (and
    /// macOS) it stays the existing safe-area-aware bottom overlay — that fallback path is unchanged.
    @ViewBuilder
    private func withMiniPlayer(_ tabView: some View) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            // Attach the accessory ONLY while something is playing — an accessory with empty content
            // still renders an empty container strip above the tab bar, so we omit it when idle. The
            // selection binding ($selectedTab) lives in ContentView, so toggling the modifier doesn't
            // lose the active tab.
            if engine.currentSong != nil || engine.currentRadioStation != nil {
                tabView.tabViewBottomAccessory { MiniPlayerView() }
            } else {
                tabView
            }
        } else {
            tabView.overlay(alignment: .bottom) { miniPlayerOverlay }
        }
        #else
        tabView.overlay(alignment: .bottom) { miniPlayerOverlay }
        #endif
    }

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
        let allIds = ["library", "favorites", "library-home", "search", "radio",
                      "artists", "albums", "songs", "genres",
                      "playlists", "downloads", "settings"]
        if let data = tabBarOrderJSON.data(using: .utf8),
           let saved = try? JSONDecoder().decode([String].self, from: data),
           !saved.isEmpty {
            // Ensure all known tabs are in the list (append missing ones)
            var result = saved.filter { allIds.contains($0) }
            for id in allIds where !result.contains(id) {
                result.append(id)
            }
            return result
        }
        return allIds
    }

    private func isTabVisible(_ id: String) -> Bool {
        switch id {
        case "library": return true
        case "library-home": return showLibraryHomeTab
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

    /// Slots the compact iPhone tab bar shows before the system would create
    /// its own "More" overflow. We keep the declared `Tab` count at or below
    /// this so the system never builds its overflow navigation container —
    /// that container nesting with each tab's own NavigationStack is what
    /// produced the stacked double back-chevron (#70). When the visible set
    /// exceeds this, the extra tabs go into an app-owned "More" tab instead.
    private static let compactTabSlots = 5

    @available(iOS 18.0, macOS 15.0, *)
    private var modernTabView: some View {
        // Visible tabs in the user's saved order. Home ("library") is always
        // first and always a real tab.
        let visible = orderedTabIds.filter { isTabVisible($0) }
        let secondary = visible.filter { $0 != "library" }

        // If everything fits, show all tabs directly. Otherwise keep the first
        // four (Home + 3) as real tabs and route the rest into an app-owned
        // "More" tab. `- 2` reserves a slot for Home and for the More tab.
        let fitsDirectly = visible.count <= Self.compactTabSlots
        let primarySecondary = fitsDirectly
            ? secondary
            : Array(secondary.prefix(Self.compactTabSlots - 2))
        let overflow = fitsDirectly
            ? []
            : Array(secondary.dropFirst(Self.compactTabSlots - 2))

        var validValues = Set(["library", "more"])
        validValues.formUnion(primarySecondary)

        let configuredTabView = TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: "library") {
                LibraryView(navPath: $libraryNavPath)
            }
            ForEach(primarySecondary, id: \.self) { tabId in
                Tab(tabLabel(tabId), systemImage: tabIcon(tabId), value: tabId) {
                    tabView(for: tabId)
                }
            }
            if !overflow.isEmpty {
                Tab("More", systemImage: "ellipsis", value: "more") {
                    appMoreMenu(overflow)
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
        // If a reorder/visibility change moves the selected tab into the More
        // overflow (so it's no longer a declared Tab value), fall back to Home
        // so the TabView always has a valid selection.
        .onAppear { normalizeSelectedTab(valid: validValues) }
        .onChange(of: tabBarOrderJSON) { _, _ in normalizeSelectedTab(valid: validValues) }

        return withMiniPlayer(configuredTabView)
    }

    private func normalizeSelectedTab(valid: Set<String>) {
        if !valid.contains(selectedTab) {
            selectedTab = "library"
        }
    }

    private func tabLabel(_ id: String) -> String {
        switch id {
        case "library-home": return "Library"
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
        case "library-home": return "music.note.house.fill"
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

    /// The bare root view for a tab id, WITHOUT a NavigationStack wrapper. Used
    /// both as the content of a tab's own stack (`tabView(for:)`) and as a
    /// pushed destination inside the app-owned More menu — pushing it bare onto
    /// the More menu's single stack avoids nesting a second NavigationStack
    /// (the cause of the #70 double back-chevron).
    @ViewBuilder
    private func tabRootContent(for id: String) -> some View {
        switch id {
        case "library-home": LibraryHomeView()
        case "artists": ArtistsView()
        case "albums": AlbumsView(listType: .alphabeticalByName, title: "Albums")
        case "songs": SongsView()
        case "genres": GenresView()
        case "favorites": FavoritesView()
        case "search": SearchView()
        case "playlists": PlaylistsView()
        case "radio": RadioView()
        case "downloads": DownloadsView()
        case "settings": SettingsView()
        default: EmptyView()
        }
    }

    /// A tab's content as a real tab: its root wrapped in its own NavigationStack.
    @ViewBuilder
    private func tabView(for id: String) -> some View {
        NavigationStack { tabRootContent(for: id) }
    }

    /// App-owned "More" menu. A single NavigationStack listing the overflow
    /// tabs; each pushes its bare root onto this one stack, so deeper pushes
    /// (e.g. Settings -> Player) keep a single back-chevron.
    @ViewBuilder
    private func appMoreMenu(_ ids: [String]) -> some View {
        NavigationStack {
            List {
                ForEach(ids, id: \.self) { id in
                    NavigationLink {
                        tabRootContent(for: id)
                    } label: {
                        Label(tabLabel(id), systemImage: tabIcon(id))
                    }
                }
            }
            .navigationTitle("More")
        }
    }

    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            LibraryView(navPath: $libraryNavPath)
                .tabItem { Label("Home", systemImage: "house") }
                .tag("library")
            if showLibraryHomeTab {
                NavigationStack { LibraryHomeView() }
                    .tabItem { Label("Library", systemImage: "music.note.house.fill") }
                    .tag("library-home")
            }
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
            miniPlayerOverlay
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
            case .label(let name):
                libraryNavPath.append(LabelNavItem(name: name))
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

struct LabelNavItem: Hashable {
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
