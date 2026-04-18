import SwiftData
import SwiftUI
import os.log

/// Sidebar-based navigation layout used on iPad and macOS.
struct SidebarContentView: View {
    @Environment(AppState.self) private var appState
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @SceneStorage("sidebarSelection") private var selectionRaw: String = SidebarItem.artists.rawValue
    #if os(macOS)
    @AppStorage(UserDefaultsKeys.macSidePanelWidth) private var sidePanelWidthChoice: String = "medium"
    #endif
    @State private var detailPath = NavigationPath()
    @State private var randomActionInFlight = false
    @State private var selectedCollectionId: String?
    @Query(sort: \AlbumCollection.order) private var collections: [AlbumCollection]
    @Environment(\.modelContext) private var modelContext

    #if os(macOS)
    private var sidePanelWidth: CGFloat {
        switch sidePanelWidthChoice {
        case "small": return 300
        case "large": return 480
        default: return 360
        }
    }
    #endif

    private var selection: Binding<String?> {
        Binding(
            get: { selectionRaw },
            set: {
                selectionRaw = $0 ?? SidebarItem.artists.rawValue
                if let val = $0, val.hasPrefix("collection:") {
                    selectedCollectionId = String(val.dropFirst("collection:".count))
                } else {
                    selectedCollectionId = nil
                }
            }
        )
    }

    private var selectedSidebarItem: SidebarItem? {
        SidebarItem(rawValue: selectionRaw)
    }

    private var engine: AudioEngine { AudioEngine.shared }

    enum SidebarItem: String, CaseIterable, Hashable {
        case artists, albums, songs, genres, labels, favorites, recentlyAdded, mostPlayed, recentlyPlayed
        case bookmarks, folders
        case search
        case playlists
        case radio
        case nowPlaying
        case downloads
        case settings
    }

    enum SidebarNavRoute: Hashable {
        case album(String)
        case artist(String)
        case song(String)
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Library") {
                    Label("Artists", systemImage: "music.mic")
                        .tag(SidebarItem.artists.rawValue)
                    Label("Albums", systemImage: "square.stack")
                        .tag(SidebarItem.albums.rawValue)
                    Label("Songs", systemImage: "music.note")
                        .tag(SidebarItem.songs.rawValue)
                    Label("Genres", systemImage: "guitars")
                        .tag(SidebarItem.genres.rawValue)
                    #if os(macOS)
                    Label("Labels", systemImage: "tag")
                        .tag(SidebarItem.labels.rawValue)
                    #endif
                    Label("Favorites", systemImage: "heart.fill")
                        .tag(SidebarItem.favorites.rawValue)
                    Label("Recently Added", systemImage: "clock")
                        .tag(SidebarItem.recentlyAdded.rawValue)
                    Label("Most Played", systemImage: "star")
                        .tag(SidebarItem.mostPlayed.rawValue)
                    Label("Recently Played", systemImage: "play.circle")
                        .tag(SidebarItem.recentlyPlayed.rawValue)

                    Button {
                        Task { await playRandomAlbum() }
                    } label: {
                        Label("Random Album", systemImage: "shuffle")
                    }
                    .buttonStyle(.plain)
                    .disabled(randomActionInFlight)
                    .accessibilityIdentifier("randomAlbumButton")

                    Button {
                        Task { await playRandomMix() }
                    } label: {
                        Label("Random Mix", systemImage: "sparkles")
                    }
                    .buttonStyle(.plain)
                    .disabled(randomActionInFlight)
                    .accessibilityIdentifier("randomMixButton")

                    Label("Bookmarks", systemImage: "bookmark")
                        .tag(SidebarItem.bookmarks.rawValue)
                    Label("Folders", systemImage: "folder")
                        .tag(SidebarItem.folders.rawValue)
                    Label("Downloads", systemImage: "arrow.down.circle")
                        .tag(SidebarItem.downloads.rawValue)
                }
                if !collections.isEmpty {
                    Section("Collections") {
                        ForEach(collections) { collection in
                            Label(collection.name, systemImage: "line.3.horizontal.decrease.circle")
                                .tag("collection:\(collection.id)")
                                .contextMenu {
                                    Button(role: .destructive) {
                                        modelContext.delete(collection)
                                        try? modelContext.save()
                                        if selectedCollectionId == collection.id {
                                            selectedCollectionId = nil
                                        }
                                    } label: {
                                        Label("Delete Collection", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                Section {
                    Label("Search", systemImage: "magnifyingglass")
                        .tag(SidebarItem.search.rawValue)
                    Label("Playlists", systemImage: "music.note.list")
                        .tag(SidebarItem.playlists.rawValue)
                    Label("Stations", systemImage: "antenna.radiowaves.left.and.right")
                        .tag(SidebarItem.radio.rawValue)
                    #if os(macOS)
                    Label("Now Playing", systemImage: "play.circle")
                        .tag(SidebarItem.nowPlaying.rawValue)
                    #endif
                    Label("Settings", systemImage: "gear")
                        .tag(SidebarItem.settings.rawValue)
                }
            }
            #if os(iOS)
            .contentMargins(.bottom, 80)
            #endif
            .navigationTitle("Vibrdrome")
        } detail: {
            #if os(macOS)
            GeometryReader { geometry in
                NavigationStack(path: $detailPath) {
                    detailView
                        .navigationDestination(for: SidebarNavRoute.self) { route in
                            switch route {
                            case .album(let id):
                                AlbumDetailView(albumId: id)
                            case .artist(let id):
                                ArtistDetailView(artistId: id)
                            case .song(let id):
                                SongDetailView(songId: id)
                            }
                        }
                }
                .environment(\.contentWidth, geometry.size.width)
            }
            .inspector(isPresented: Binding(
                get: { appState.activeSidePanel != nil },
                set: { if !$0 { appState.activeSidePanel = nil } }
            )) {
                if let panel = appState.activeSidePanel {
                    sidePanelView(for: panel)
                }
            }
            .inspectorColumnWidth(min: 280, ideal: sidePanelWidth, max: 500)
            #else
            NavigationStack(path: $detailPath) {
                detailView
                    .navigationDestination(for: SidebarNavRoute.self) { route in
                        switch route {
                        case .album(let id):
                            AlbumDetailView(albumId: id)
                        case .artist(let id):
                            ArtistDetailView(artistId: id)
                        case .song(let id):
                            SongDetailView(songId: id)
                        }
                    }
            }
            #endif
        }
        .onChange(of: selectionRaw) { _, _ in
            if !detailPath.isEmpty {
                detailPath = NavigationPath()
            }
            #if os(macOS)
            // Auto-switch filter panel when a filter panel is already open
            if let panel = appState.activeSidePanel,
               panel == .albumFilters || panel == .artistFilters || panel == .songFilters {
                switch SidebarItem(rawValue: selectionRaw) {
                case .albums, .recentlyAdded, .mostPlayed, .recentlyPlayed:
                    appState.activeSidePanel = .albumFilters
                case .artists:
                    appState.activeSidePanel = .artistFilters
                case .songs:
                    appState.activeSidePanel = .songFilters
                default:
                    appState.activeSidePanel = nil
                }
            }
            #endif
        }
        .onChange(of: appState.pendingNavigation) { _, newValue in
            guard let nav = newValue else { return }
            appState.pendingNavigation = nil
            switch nav {
            case .album(let id):
                detailPath.append(SidebarNavRoute.album(id))
            case .artist(let id):
                detailPath.append(SidebarNavRoute.artist(id))
            case .song(let id):
                detailPath.append(SidebarNavRoute.song(id))
            case .genre, .playlist:
                break
            }
        }
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            splitView
            if (engine.currentSong != nil || engine.currentRadioStation != nil)
                && selectedSidebarItem != .nowPlaying {
                Divider()
                MacMiniPlayerView()
            }
        }
        #else
        splitView
            .safeAreaInset(edge: .bottom) {
                if engine.currentSong != nil || engine.currentRadioStation != nil {
                    MiniPlayerView()
                }
            }
        #endif
    }

    @ViewBuilder
    private var detailView: some View {
        if let collectionId = selectedCollectionId,
           let collection = collections.first(where: { $0.id == collectionId }) {
            AlbumsView(
                listType: collection.albumListType,
                title: collection.name,
                genre: collection.genre,
                fromYear: collection.fromYear,
                toYear: collection.toYear
            )
        } else {
            staticDetailView
        }
    }

    @ViewBuilder
    private var staticDetailView: some View {
        switch selectedSidebarItem {
        case .artists:
            ArtistsView()
        case .albums:
            AlbumsView(listType: .alphabeticalByName, title: "Albums")
        case .songs:
            SongsView()
        case .genres:
            GenresView()
        case .labels:
            #if os(macOS)
            LabelsView()
            #else
            EmptyView()
            #endif
        case .favorites:
            FavoritesView()
        case .recentlyAdded:
            AlbumsView(listType: .newest, title: "Recently Added")
        case .mostPlayed:
            AlbumsView(listType: .frequent, title: "Most Played")
        case .recentlyPlayed:
            AlbumsView(listType: .recent, title: "Recently Played")
        case .bookmarks:
            BookmarksView()
        case .folders:
            FolderBrowserView()
        case .downloads:
            DownloadsView()
        case .search:
            SearchView()
        case .playlists:
            PlaylistsView()
        case .radio:
            RadioView()
        case .nowPlaying:
            #if os(macOS)
            NowPlayingView(isInline: true)
            #else
            EmptyView()
            #endif
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

    // MARK: - Side panels

    #if os(macOS)
    @ViewBuilder
    private func sidePanelView(for panel: AppState.SidePanel) -> some View {
        switch panel {
        case .queue:
            QueuePanelView()
        case .lyrics:
            LyricsPanelView()
        case .artistInfo:
            ArtistInfoPanelView()
        case .albumFilters:
            LibraryFilterSidebarView(context: .album)
        case .artistFilters:
            LibraryFilterSidebarView(context: .artist)
        case .songFilters:
            LibraryFilterSidebarView(context: .song)
        }
    }
    #endif

    // MARK: - Random Album / Random Mix actions

    private func playRandomAlbum() async {
        guard !randomActionInFlight else { return }
        randomActionInFlight = true
        defer { randomActionInFlight = false }
        do {
            let albums = try await appState.subsonicClient.getAlbumList(type: .random, size: 1)
            guard let album = albums.first else { return }
            let detail = try await appState.subsonicClient.getAlbum(id: album.id)
            if let songs = detail.song, let first = songs.first {
                AudioEngine.shared.play(song: first, from: songs, at: 0)
            }
            detailPath.append(SidebarNavRoute.album(album.id))
        } catch {
            Logger(subsystem: "com.vibrdrome.app", category: "Sidebar")
                .error("Random album failed: \(error)")
        }
    }

    private func playRandomMix() async {
        guard !randomActionInFlight else { return }
        randomActionInFlight = true
        defer { randomActionInFlight = false }
        do {
            let pool = try await appState.subsonicClient.getRandomSongs(size: 200)
            let mix = Self.diversifyMix(pool, target: 50, maxPerArtist: 3)
            guard let first = mix.first else { return }
            AudioEngine.shared.play(song: first, from: mix, at: 0)
            #if os(macOS)
            selectionRaw = SidebarItem.nowPlaying.rawValue
            appState.activeSidePanel = .queue
            #endif
        } catch {
            Logger(subsystem: "com.vibrdrome.app", category: "Sidebar")
                .error("Random mix failed: \(error)")
        }
    }

    /// Pick up to `target` songs from `pool` where:
    /// - no artist exceeds `maxPerArtist` total
    /// - no two consecutive songs are by the same artist
    static func diversifyMix(_ pool: [Song], target: Int, maxPerArtist: Int) -> [Song] {
        var counts: [String: Int] = [:]
        var result: [Song] = []
        var deferred: [Song] = []
        result.reserveCapacity(target)

        for song in pool.shuffled() {
            if result.count >= target { break }
            let artistKey = song.artist ?? song.artistId ?? "—"
            if (counts[artistKey] ?? 0) >= maxPerArtist { continue }
            if result.last?.artist == song.artist {
                deferred.append(song)
                continue
            }
            result.append(song)
            counts[artistKey, default: 0] += 1
        }

        // Try to slot deferred entries into gaps between unrelated artists
        for song in deferred {
            if result.count >= target { break }
            let artistKey = song.artist ?? song.artistId ?? "—"
            if (counts[artistKey] ?? 0) >= maxPerArtist { continue }
            if let insertion = result.indices.first(where: { idx in
                let prevOK = idx == 0 || result[idx - 1].artist != song.artist
                let nextOK = idx >= result.count || result[idx].artist != song.artist
                return prevOK && nextOK
            }) {
                result.insert(song, at: insertion)
                counts[artistKey, default: 0] += 1
            }
        }

        return result
    }
}
