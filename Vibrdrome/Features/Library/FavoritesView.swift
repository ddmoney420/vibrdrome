import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<CachedArtist> { $0.isStarred }, sort: \CachedArtist.name)
    private var starredArtists: [CachedArtist]
    @Query(filter: #Predicate<CachedAlbum> { $0.isStarred }, sort: \CachedAlbum.name)
    private var starredAlbums: [CachedAlbum]
    @Query(filter: #Predicate<CachedSong> { $0.isStarred }, sort: \CachedSong.title)
    private var starredSongs: [CachedSong]
    @State private var searchText = ""
    @State private var searchIsActive = false
    @State private var selectedSongs = Set<String>()
    @State private var isSelecting = false
    @State private var showBatchAddToPlaylist = false
    @State private var selectedCategory: FavoriteCategory = .songs
    @AppStorage("favoritesViewAsList") private var showAsList = true
    @AppStorage(UserDefaultsKeys.gridDensity) private var gridDensityRaw: String = GridDensity.comfortable.rawValue
    private var gridDensity: GridDensity { GridDensity(rawValue: gridDensityRaw) ?? .comfortable }
    #if os(macOS)
    @State private var columnSettings = TrackTableColumnSettings(viewKey: "favorites")
    #endif
    @State private var cachedFilteredArtists: [Artist] = []
    @State private var cachedFilteredAlbums: [Album] = []
    @State private var cachedFilteredSongs: [Song] = []

    enum FavoriteCategory: String, CaseIterable, Identifiable {
        case songs, albums, artists
        var id: String { rawValue }
        var label: String {
            switch self {
            case .songs: "Songs"
            case .albums: "Albums"
            case .artists: "Artists"
            }
        }
        var icon: String {
            switch self {
            case .songs: "music.note"
            case .albums: "square.stack"
            case .artists: "music.mic"
            }
        }
    }

    private func computeFilteredArtists() -> [Artist] {
        if searchText.isEmpty { return starredArtists.map { $0.toArtist() } }
        return starredArtists
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .map { $0.toArtist() }
    }

    private func computeFilteredAlbums() -> [Album] {
        if searchText.isEmpty { return starredAlbums.map { $0.toAlbum() } }
        return starredAlbums
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .map { $0.toAlbum() }
    }

    private func computeFilteredSongs() -> [Song] {
        if searchText.isEmpty { return starredSongs.map { $0.toSong() } }
        return starredSongs
            .filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.artist ?? "").localizedCaseInsensitiveContains(searchText)
            }
            .map { $0.toSong() }
    }

    var body: some View {
        Group {
            switch selectedCategory {
            case .songs:   songsContent
            case .albums:  albumsContent
            case .artists: artistsContent
            }
        }
        .safeAreaInset(edge: .top) {
            categoryPicker
                .background(.bar)
        }
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle("Favorites")
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Favorites")
        .navigationBarTitleDisplayMode(.large)
        #else
        .searchable(text: $searchText, isPresented: $searchIsActive, prompt: "Search Favorites")
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchBar)) { _ in
            searchIsActive = false
            DispatchQueue.main.async { searchIsActive = true }
        }
        .overlay {
            if appState.librarySyncManager.lastSyncDate == nil && isEmpty {
                ContentUnavailableView {
                    Label("Loading Favorites", systemImage: "heart")
                } description: {
                    Text("Syncing your library...")
                }
            } else if isEmpty {
                ContentUnavailableView {
                    Label("No Favorites", systemImage: "heart")
                } description: {
                    Text("Star songs, albums, and artists to see them here")
                }
            }
        }
        .toolbar {
            if selectedCategory != .songs {
                ToolbarItem(placement: .automatic) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAsList.toggle() }
                    } label: {
                        Image(systemName: showAsList ? "square.grid.2x2" : "list.bullet")
                    }
                    .accessibilityLabel(showAsList ? "Grid View" : "List View")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if selectedCategory == .songs {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelecting.toggle()
                            if !isSelecting { selectedSongs.removeAll() }
                        }
                    } label: {
                        Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .accessibilityLabel(isSelecting ? "Done Selecting" : "Select Songs")
                    .accessibilityIdentifier("favSelectButton")
                }
            }
            #if os(macOS)
            ToolbarItem {
                Button { Task { await LibrarySyncManager.shared.syncIfStale() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            #endif
        }
        .sheet(isPresented: $showBatchAddToPlaylist) {
            AddToPlaylistView(songIds: Array(selectedSongs))
                .environment(appState)
        }
        .refreshable { await LibrarySyncManager.shared.syncIfStale() }
        .onChange(of: searchText) { recomputeFilteredLists() }
        .onChange(of: starredArtists) { recomputeFilteredLists() }
        .onChange(of: starredAlbums) { recomputeFilteredLists() }
        .onChange(of: starredSongs) { recomputeFilteredLists() }
        .onAppear { recomputeFilteredLists() }
    }

    // MARK: - Category picker

    private var categoryPicker: some View {
        Picker("Category", selection: $selectedCategory) {
            ForEach(FavoriteCategory.allCases) { cat in
                Text(cat.label).tag(cat)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityIdentifier("favoritesCategoryPicker")
    }

    // MARK: - Songs

    @ViewBuilder
    private var songsContent: some View {
        let songs = cachedFilteredSongs
        if songs.isEmpty {
            emptyCategory("No Favorited Songs")
        } else {
            #if os(macOS)
            MacTrackTableView(songs: songs, settings: columnSettings)
            #else
            List {
                HStack(spacing: 12) {
                    Button {
                        AudioEngine.shared.play(song: songs[0], from: songs, at: 0)
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityIdentifier("favPlayAllButton")

                    Button {
                        let shuffled = songs.shuffled()
                        AudioEngine.shared.play(song: shuffled[0], from: shuffled, at: 0)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityIdentifier("favShuffleButton")
                }
                .listRowSeparator(.hidden)

                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    HStack(spacing: 0) {
                        if isSelecting {
                            Button {
                                toggleSelection(song.id)
                            } label: {
                                Image(systemName: selectedSongs.contains(song.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedSongs.contains(song.id)
                                                     ? Color.accentColor : .secondary)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                        }

                        TrackRow(song: song, showTrackNumber: false)
                            .trackContextMenu(song: song, queue: songs, index: index)
                            .accessibilityIdentifier("favSongRow_\(song.id)")
                            .onTapGesture {
                                if isSelecting {
                                    toggleSelection(song.id)
                                } else {
                                    AudioEngine.shared.play(song: song, from: songs, at: index)
                                }
                            }
                    }
                }

                if isSelecting && !selectedSongs.isEmpty {
                    favoritesBatchActionBar(songs: songs)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            #endif
        }
    }

    // MARK: - Albums

    @ViewBuilder
    private var albumsContent: some View {
        let albums = cachedFilteredAlbums
        if albums.isEmpty {
            emptyCategory("No Favorited Albums")
        } else if showAsList {
            List(albums) { album in
                NavigationLink {
                    AlbumDetailView(albumId: album.id)
                } label: {
                    AlbumCard(album: album)
                }
                .accessibilityIdentifier("favAlbumRow_\(album.id)")
                .albumGetInfoContextMenu(album: album)
            }
            .listStyle(.plain)
        } else {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: gridDensity.minimumWidth), spacing: 16)
                ], spacing: 20) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(albumId: album.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AlbumArtView(coverArtId: album.coverArt, size: 140, cornerRadius: 10)
                                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                                Text(album.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                if let artist = album.artist {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("favAlbumCard_\(album.id)")
                        .albumGetInfoContextMenu(album: album)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Artists

    @ViewBuilder
    private var artistsContent: some View {
        let artists = cachedFilteredArtists
        if artists.isEmpty {
            emptyCategory("No Favorited Artists")
        } else if showAsList {
            List(artists) { artist in
                NavigationLink {
                    ArtistDetailView(artistId: artist.id)
                } label: {
                    ArtistRow(artist: artist)
                }
                .accessibilityIdentifier("favArtistRow_\(artist.id)")
                .artistGetInfoContextMenu(artist: artist)
            }
            .listStyle(.plain)
        } else {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: gridDensity.minimumWidth), spacing: 16)
                ], spacing: 20) {
                    ForEach(artists) { artist in
                        NavigationLink {
                            ArtistDetailView(artistId: artist.id)
                        } label: {
                            VStack(spacing: 8) {
                                AlbumArtView(coverArtId: artist.coverArt, size: 140, cornerRadius: 70)
                                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                                Text(artist.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("favArtistCard_\(artist.id)")
                        .artistGetInfoContextMenu(artist: artist)
                    }
                }
                .padding(16)
            }
        }
    }

    private func emptyCategory(_ message: String) -> some View {
        ContentUnavailableView {
            Label(message, systemImage: "heart")
        } description: {
            Text("Star items to see them here")
        }
    }

    private func recomputeFilteredLists() {
        cachedFilteredArtists = computeFilteredArtists()
        cachedFilteredAlbums = computeFilteredAlbums()
        cachedFilteredSongs = computeFilteredSongs()
    }

    private func favoritesBatchActionBar(songs: [Song]) -> some View {
        BatchActionBar(
            selectedSongIds: selectedSongs,
            songs: songs,
            onAddToPlaylist: { showBatchAddToPlaylist = true }
        )
    }

    private func toggleSelection(_ songId: String) {
        if selectedSongs.contains(songId) {
            selectedSongs.remove(songId)
        } else {
            selectedSongs.insert(songId)
        }
    }

    private var isEmpty: Bool {
        starredArtists.isEmpty && starredAlbums.isEmpty && starredSongs.isEmpty
    }
}
