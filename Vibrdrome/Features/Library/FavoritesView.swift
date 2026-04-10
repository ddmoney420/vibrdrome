import SwiftUI

struct FavoritesView: View {
    @Environment(AppState.self) private var appState
    @State private var starred: Starred2?
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var selectedSongs = Set<String>()
    @State private var isSelecting = false
    @State private var showBatchAddToPlaylist = false

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
        List {
            if starred != nil {
                // Starred Artists
                if !filteredArtists.isEmpty {
                    Section("Artists") {
                        ForEach(filteredArtists) { artist in
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
                if !filteredAlbums.isEmpty {
                    Section("Albums") {
                        ForEach(filteredAlbums) { album in
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
                if !filteredSongs.isEmpty {
                    Section("Songs") {
                        HStack(spacing: 12) {
                            Button {
                                AudioEngine.shared.play(song: filteredSongs[0], from: filteredSongs, at: 0)
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
                                let shuffled = filteredSongs.shuffled()
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

                        ForEach(Array(filteredSongs.enumerated()), id: \.element.id) { index, song in
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
                                    .trackContextMenu(song: song, queue: filteredSongs, index: index)
                                    .accessibilityIdentifier("favSongRow_\(song.id)")
                                    .onTapGesture {
                                        if isSelecting {
                                            toggleSelection(song.id)
                                        } else {
                                            AudioEngine.shared.play(song: song, from: filteredSongs, at: index)
                                        }
                                    }
                            }
                        }

                        // Batch action bar
                        if isSelecting && !selectedSongs.isEmpty {
                            favoritesBatchActionBar(songs: filteredSongs)
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
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Favorites")
        #else
        .searchable(text: $searchText, prompt: "Search Favorites")
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
