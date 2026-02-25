import SwiftUI

/// Sidebar-based navigation layout used on iPad and macOS.
struct SidebarContentView: View {
    @Environment(AppState.self) private var appState
    @SceneStorage("sidebarSelection") private var selectionRaw: String = SidebarItem.artists.rawValue

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { SidebarItem(rawValue: selectionRaw) },
            set: { selectionRaw = $0?.rawValue ?? SidebarItem.artists.rawValue }
        )
    }

    private var engine: AudioEngine { AudioEngine.shared }

    enum SidebarItem: String, CaseIterable, Hashable {
        case artists, albums, genres, favorites, recentlyAdded, mostPlayed, recentlyPlayed, random
        case bookmarks, folders
        case search
        case playlists
        case radio
        case downloads
        case settings
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: selection) {
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
                    #if os(iOS)
                    Label("Settings", systemImage: "gear")
                        .tag(SidebarItem.settings)
                    #endif
                }
            }
            .navigationTitle("Vibrdrome")
        } detail: {
            NavigationStack {
                detailView
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
}
