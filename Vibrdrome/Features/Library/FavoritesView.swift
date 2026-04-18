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
    @State private var selectedSongs = Set<String>()
    @State private var isSelecting = false
    @State private var showBatchAddToPlaylist = false
    @State private var cachedFilteredArtists: [Artist] = []
    @State private var cachedFilteredAlbums: [Album] = []
    @State private var cachedFilteredSongs: [Song] = []

    private func computeFilteredArtists() -> [Artist] {
        let artists = starredArtists.map { $0.toArtist() }
        if searchText.isEmpty { return artists }
        return artists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func computeFilteredAlbums() -> [Album] {
        let albums = starredAlbums.map { $0.toAlbum() }
        if searchText.isEmpty { return albums }
        return albums.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func computeFilteredSongs() -> [Song] {
        let songs = starredSongs.map { $0.toSong() }
        if searchText.isEmpty { return songs }
        return songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if !isEmpty {
                // Starred Artists
                if !cachedFilteredArtists.isEmpty {
                    Section("Artists") {
                        ForEach(cachedFilteredArtists) { artist in
                            NavigationLink {
                                ArtistDetailView(artistId: artist.id)
                            } label: {
                                ArtistRow(artist: artist)
                            }
                            .accessibilityIdentifier("favArtistRow_\(artist.id)")
                        }
                    }
                }

                // Starred Albums
                if !cachedFilteredAlbums.isEmpty {
                    Section("Albums") {
                        ForEach(cachedFilteredAlbums) { album in
                            NavigationLink {
                                AlbumDetailView(albumId: album.id)
                            } label: {
                                AlbumCard(album: album)
                            }
                            .accessibilityIdentifier("favAlbumRow_\(album.id)")
                        }
                    }
                }

                // Starred Songs
                if !cachedFilteredSongs.isEmpty {
                    Section("Songs") {
                        HStack(spacing: 12) {
                            Button {
                                AudioEngine.shared.play(song: cachedFilteredSongs[0], from: cachedFilteredSongs, at: 0)
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
                                let shuffled = cachedFilteredSongs.shuffled()
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

                        ForEach(Array(cachedFilteredSongs.enumerated()), id: \.element.id) { index, song in
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
                                    .trackContextMenu(song: song, queue: cachedFilteredSongs, index: index)
                                    .accessibilityIdentifier("favSongRow_\(song.id)")
                                    .onTapGesture {
                                        if isSelecting {
                                            toggleSelection(song.id)
                                        } else {
                                            AudioEngine.shared.play(song: song, from: cachedFilteredSongs, at: index)
                                        }
                                    }
                            }
                        }

                        // Batch action bar
                        if isSelecting && !selectedSongs.isEmpty {
                            favoritesBatchActionBar(songs: cachedFilteredSongs)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle("Favorites")
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Favorites")
        #else
        .searchable(text: $searchText, prompt: "Search Favorites")
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            ToolbarItem(placement: .primaryAction) {
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

    private func recomputeFilteredLists() {
        cachedFilteredArtists = computeFilteredArtists()
        cachedFilteredAlbums = computeFilteredAlbums()
        cachedFilteredSongs = computeFilteredSongs()
    }

    private func toggleSelection(_ songId: String) {
        if selectedSongs.contains(songId) {
            selectedSongs.remove(songId)
        } else {
            selectedSongs.insert(songId)
        }
    }

    @ViewBuilder
    private func favoritesBatchActionBar(songs: [Song]) -> some View {
        BatchActionBar(
            selectedSongIds: selectedSongs,
            songs: songs,
            onAddToPlaylist: { showBatchAddToPlaylist = true }
        )
    }

    private var isEmpty: Bool {
        starredArtists.isEmpty && starredAlbums.isEmpty && starredSongs.isEmpty
    }
}
