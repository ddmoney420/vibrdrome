import SwiftUI

struct FavoritesView: View {
    @Environment(AppState.self) private var appState
    @State private var starred: Starred2?
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var searchIsActive = false
    @State private var selectedSongs = Set<String>()
    @State private var isSelecting = false
    @State private var showBatchAddToPlaylist = false
    @State private var selectedCategory: FavoriteCategory = .songs
    @AppStorage("favoritesViewAsList") private var showAsList = true
    @AppStorage(UserDefaultsKeys.gridColumnsPerRow) private var gridColumns = 2
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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

    private var filteredArtists: [Artist] {
        guard let artists = starred?.artist else { return [] }
        if searchText.isEmpty { return artists }
        return artists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredAlbums: [Album] {
        guard let albums = starred?.album else { return [] }
        if searchText.isEmpty { return albums }
        return albums.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredSongs: [Song] {
        guard let songs = starred?.song else { return [] }
        if searchText.isEmpty { return songs }
        return songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist ?? "").localizedCaseInsensitiveContains(searchText)
        }
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
            if isLoading && starred == nil {
                ProgressView("Loading favorites...")
            } else if let error, starred == nil {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadStarred() } }
                        .buttonStyle(.bordered)
                }
            } else if !isLoading && isEmpty {
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
                Button { Task { await loadStarred() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            #endif
        }
        .sheet(isPresented: $showBatchAddToPlaylist) {
            AddToPlaylistView(songIds: Array(selectedSongs))
                .environment(appState)
        }
        .task { await loadStarred() }
        .refreshable { await loadStarred() }
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
        let songs = filteredSongs
        if songs.isEmpty {
            emptyCategory("No Favorited Songs")
        } else {
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
                    BatchActionBar(
                        selectedSongIds: selectedSongs,
                        songs: songs,
                        onAddToPlaylist: { showBatchAddToPlaylist = true }
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Albums

    @ViewBuilder
    private var albumsContent: some View {
        let albums = filteredAlbums
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
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16),
                                         count: Theme.effectiveGridColumns(base: gridColumns, verticalSizeClass: verticalSizeClass)),
                          spacing: 20) {
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
        let artists = filteredArtists
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
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16),
                                         count: Theme.effectiveGridColumns(base: gridColumns, verticalSizeClass: verticalSizeClass)),
                          spacing: 20) {
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

    private func toggleSelection(_ songId: String) {
        if selectedSongs.contains(songId) {
            selectedSongs.remove(songId)
        } else {
            selectedSongs.insert(songId)
        }
    }

    private var isEmpty: Bool {
        guard let starred else { return true }
        return (starred.artist?.isEmpty ?? true) &&
               (starred.album?.isEmpty ?? true) &&
               (starred.song?.isEmpty ?? true)
    }

    private func loadStarred() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            starred = try await appState.subsonicClient.getStarred()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }
}
