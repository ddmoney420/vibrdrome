import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var results: SearchResult3?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private var showAlbumArtInLists: Bool = true

    var body: some View {
        ScrollView {
            if let results {
                resultsContent(results)
            } else if let searchError, !query.isEmpty {
                errorContent(searchError)
            } else if query.isEmpty {
                emptyContent
            }
        }
        #if os(iOS)
        .padding(.bottom, 80)
        #endif
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Artists, albums, songs...")
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()

            guard newValue.count >= 2 else {
                results = nil
                return
            }

            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }

                isSearching = true
                defer { isSearching = false }

                do {
                    let searchResults = try await appState.subsonicClient.search(query: newValue)
                    guard !Task.isCancelled else { return }
                    searchError = nil
                    results = searchResults
                } catch {
                    guard !Task.isCancelled else { return }
                    searchError = ErrorPresenter.userMessage(for: error)
                    results = nil
                }
            }
        }
        .overlay {
            if isSearching {
                ProgressView()
            }
        }
    }

    // MARK: - Results

    private func resultsContent(_ results: SearchResult3) -> some View {
        let artists = results.artist ?? []
        let albums = results.album ?? []
        let songs = results.song ?? []

        return VStack(spacing: 24) {
            if artists.isEmpty && albums.isEmpty && songs.isEmpty {
                ContentUnavailableView.search(text: query)
            }

            if !artists.isEmpty { artistsSection(artists) }
            if !albums.isEmpty { albumsSection(albums) }
            if !songs.isEmpty { songsSection(songs) }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func artistsSection(_ artists: [Artist]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Artists")
                .font(.title3).bold()
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(artists) { artist in
                        NavigationLink {
                            ArtistDetailView(artistId: artist.id)
                        } label: {
                            artistBubble(artist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func albumsSection(_ albums: [Album]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Albums")
                .font(.title3).bold()
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(albumId: album.id)
                        } label: {
                            albumTile(album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func songsSection(_ songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Songs")
                .font(.title3).bold()
                .padding(.horizontal, 16)

            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    songRow(song: song, songs: songs, index: index)
                    if index < songs.count - 1 {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Artist Bubble

    private func artistBubble(_ artist: Artist) -> some View {
        VStack(spacing: 8) {
            AlbumArtView(coverArtId: artist.coverArt, size: Theme.artistBubbleSize, cornerRadius: Theme.artistBubbleSize / 2)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            Text(artist.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: Theme.artistBubbleSize + 8)
    }

    // MARK: - Album Tile

    private func albumTile(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AlbumArtView(coverArtId: album.coverArt, size: Theme.searchAlbumTileSize, cornerRadius: 10)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(album.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(album.artist ?? "")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: Theme.searchAlbumTileSize)
    }

    // MARK: - Song Row (with album art)

    private func songRow(song: Song, songs: [Song], index: Int) -> some View {
        HStack(spacing: 12) {
            if showAlbumArtInLists {
                AlbumArtView(coverArtId: song.coverArt, size: 48, cornerRadius: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let artist = song.artist {
                        Text(artist)
                    }
                    if let album = song.album {
                        Text("·")
                        Text(album)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if song.starred != nil {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
                    .accessibilityLabel("Favorited")
            }

            if let duration = song.duration {
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            AudioEngine.shared.play(song: song, from: songs, at: index)
        }
        .trackContextMenu(song: song, queue: songs, index: index)
    }

    // MARK: - Empty & Error States

    private var emptyContent: some View {
        ContentUnavailableView {
            Label("Search", systemImage: "magnifyingglass")
        } description: {
            Text("Search for artists, albums, and songs")
        }
        .padding(.top, 100)
    }

    private func errorContent(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Search Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Retry") {
                let q = query
                searchTask?.cancel()
                searchTask = Task {
                    isSearching = true
                    defer { isSearching = false }
                    do {
                        let searchResults = try await appState.subsonicClient.search(query: q)
                        guard !Task.isCancelled else { return }
                        self.searchError = nil
                        results = searchResults
                    } catch {
                        guard !Task.isCancelled else { return }
                        self.searchError = ErrorPresenter.userMessage(for: error)
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 100)
    }
}
