import SwiftUI
import os.log

/// Sidebar-based navigation layout used on iPad and macOS.
struct SidebarContentView: View {
    @Environment(AppState.self) private var appState
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @SceneStorage("sidebarSelection") private var selectionRaw: String = SidebarItem.artists.rawValue
    @State private var detailPath = NavigationPath()
    @State private var randomActionInFlight = false

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: selectionRaw) },
            set: { selectionRaw = $0?.rawValue ?? SidebarItem.artists.rawValue }
        )
    }

    private var engine: AudioEngine { AudioEngine.shared }

    enum SidebarItem: String, CaseIterable, Hashable {
        case artists, albums, songs, genres, favorites, recentlyAdded, mostPlayed, recentlyPlayed
        case bookmarks, folders
        case search
        case playlists
        case radio
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
                        .tag(SidebarItem.artists)
                    Label("Albums", systemImage: "square.stack")
                        .tag(SidebarItem.albums)
                    Label("Songs", systemImage: "music.note")
                        .tag(SidebarItem.songs)
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
                        .tag(SidebarItem.bookmarks)
                    Label("Folders", systemImage: "folder")
                        .tag(SidebarItem.folders)
                    Label("Downloads", systemImage: "arrow.down.circle")
                        .tag(SidebarItem.downloads)
                }
                Section {
                    Label("Search", systemImage: "magnifyingglass")
                        .tag(SidebarItem.search)
                    Label("Playlists", systemImage: "music.note.list")
                        .tag(SidebarItem.playlists)
                    Label("Stations", systemImage: "antenna.radiowaves.left.and.right")
                        .tag(SidebarItem.radio)
                    Label("Settings", systemImage: "gear")
                        .tag(SidebarItem.settings)
                }
            }
            .navigationTitle("Vibrdrome")
        } detail: {
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
        }
        .onChange(of: selectionRaw) { _, _ in
            if !detailPath.isEmpty {
                detailPath = NavigationPath()
            }
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
            if engine.currentSong != nil || engine.currentRadioStation != nil {
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
        switch selection.wrappedValue {
        case .artists:
            ArtistsView()
        case .albums:
            AlbumsView(listType: .alphabeticalByName, title: "Albums")
        case .songs:
            SongsView()
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
            appState.pendingNowPlayingAction = .showQueue
            openWindow(id: "now-playing")
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
