import SwiftData
import SwiftUI

private let recentSearchesKey = "recentSearches"
private let maxRecentSearches = 10

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var query = ""
    @State private var results: SearchResult3?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
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
        .onSubmit(of: .search) {
            saveRecentSearch(query)
        }
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()

            guard newValue.count >= 2 else {
                results = nil
                return
            }

            searchTask = Task {
                await performSearch(newValue)
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
            Text("Artists (\(artists.count))")
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
            Text("Albums (\(albums.count))")
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
            Text("Songs (\(songs.count))")
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
            #if os(iOS)
            Haptics.light()
            #endif
            AudioEngine.shared.play(song: song, from: songs, at: index)
        }
        .trackContextMenu(song: song, queue: songs, index: index)
    }

    // MARK: - Empty & Error States

    @ViewBuilder
    private var emptyContent: some View {
        if recentSearches.isEmpty {
            ContentUnavailableView {
                Label("Search", systemImage: "magnifyingglass")
            } description: {
                Text("Search for artists, albums, and songs")
            }
            .padding(.top, 100)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recent")
                        .font(.headline)
                    Spacer()
                    Button("Clear") {
                        withAnimation { clearRecentSearches() }
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                    .accessibilityIdentifier("clearRecentButton")
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                ForEach(recentSearches, id: \.self) { recent in
                    Button {
                        query = recent
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text(recent)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

    // MARK: - Search Logic

    private func performSearch(_ query: String) async {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            let variants = fuzzyVariants(of: query)

            // If we have fuzzy variants, search them first (more specific)
            // then merge with the original query results
            var searchResults: SearchResult3
            if !variants.isEmpty {
                // Search the dotted/specific variant first
                searchResults = try await appState.subsonicClient.search(query: variants[0])
                guard !Task.isCancelled else { return }

                // Try remaining variants if still few results
                for variant in variants.dropFirst() {
                    guard !Task.isCancelled else { return }
                    if resultCount(searchResults) >= 3 { break }
                    let extra = try await appState.subsonicClient.search(query: variant)
                    searchResults = mergeResults(searchResults, extra)
                }

                // Merge with original query results (adds broader matches)
                let original = try await appState.subsonicClient.search(query: query)
                guard !Task.isCancelled else { return }
                searchResults = mergeResults(searchResults, original)
            } else {
                searchResults = try await appState.subsonicClient.search(query: query)
                guard !Task.isCancelled else { return }
            }

            searchError = nil
            results = searchResults
        } catch {
            guard !Task.isCancelled else { return }
            // Offline fallback: search downloaded songs locally
            let offlineResults = searchDownloadsLocally(query: query)
            if let songs = offlineResults, !songs.isEmpty {
                searchError = nil
                results = SearchResult3(artist: nil, album: nil, song: songs)
            } else {
                searchError = ErrorPresenter.userMessage(for: error)
                results = nil
            }
        }
    }

    private func searchDownloadsLocally(query: String) -> [Song]? {
        let lowered = query.lowercased()
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.isComplete == true }
        )
        guard let downloads = try? modelContext.fetch(descriptor) else { return nil }
        let matched = downloads.filter {
            $0.songTitle.localizedCaseInsensitiveContains(lowered)
                || ($0.artistName?.localizedCaseInsensitiveContains(lowered) ?? false)
                || ($0.albumName?.localizedCaseInsensitiveContains(lowered) ?? false)
        }
        guard !matched.isEmpty else { return nil }
        return matched.map { $0.toSong() }
    }

    private func saveRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        var recents = recentSearches
        recents.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recents.insert(trimmed, at: 0)
        if recents.count > maxRecentSearches { recents = Array(recents.prefix(maxRecentSearches)) }
        recentSearches = recents
        UserDefaults.standard.set(recents, forKey: recentSearchesKey)
    }

    private func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }

    private func resultCount(_ r: SearchResult3) -> Int {
        (r.artist?.count ?? 0) + (r.album?.count ?? 0) + (r.song?.count ?? 0)
    }

    // MARK: - Fuzzy Search Helpers

    /// Generate fuzzy search variants for acronym-style queries
    /// Returns multiple variants to try (e.g. "REM" → ["R.E.M.", "R.E.M", "R E M"])
    private func fuzzyVariants(of query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var variants = [String]()

        // If query is all letters with no spaces/dots (likely an acronym), try dotted versions
        let lettersOnly = trimmed.filter(\.isLetter)
        if lettersOnly.count == trimmed.count && trimmed.count >= 2 && trimmed.count <= 6 {
            let upper = trimmed.uppercased()
            // R.E.M.
            variants.append(upper.map { String($0) }.joined(separator: ".") + ".")
            // R.E.M (no trailing dot)
            variants.append(upper.map { String($0) }.joined(separator: "."))
        }

        // If query contains dots/punctuation, try without them
        let stripped = trimmed.filter { $0.isLetter || $0.isNumber }
        if stripped != trimmed && stripped.count >= 2 {
            variants.append(stripped)
        }

        return variants.filter { $0 != trimmed }
    }

    /// Merge two search results, deduplicating by ID
    private func mergeResults(_ a: SearchResult3, _ b: SearchResult3) -> SearchResult3 {
        let artists = dedup((a.artist ?? []) + (b.artist ?? []))
        let albums = dedupAlbums((a.album ?? []) + (b.album ?? []))
        let songs = dedupSongs((a.song ?? []) + (b.song ?? []))
        return SearchResult3(
            artist: artists.isEmpty ? nil : artists,
            album: albums.isEmpty ? nil : albums,
            song: songs.isEmpty ? nil : songs
        )
    }

    private func dedup(_ artists: [Artist]) -> [Artist] {
        var seen = Set<String>()
        return artists.filter { seen.insert($0.id).inserted }
    }

    private func dedupAlbums(_ albums: [Album]) -> [Album] {
        var seen = Set<String>()
        return albums.filter { seen.insert($0.id).inserted }
    }

    private func dedupSongs(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return songs.filter { seen.insert($0.id).inserted }
    }
}
