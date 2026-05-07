import SwiftData
import SwiftUI

struct GenresView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var genreArtworks: [GenreArtwork]
    @State private var genres: [Genre] = []
    @State private var isLoading = true
    @State private var error: String?

    private var genreArtworkMap: [String: String] {
        // `uniqueKeysWithValues:` crashes on duplicate keys. Even with
        // `@Attribute(.unique)` on GenreArtwork.genre, a single stray
        // duplicate (concurrent insert race, pre-existing data, migration
        // edge case) would fatalError every time the user opens Genres.
        // `uniquingKeysWith:` keeps the first entry and moves on.
        Dictionary(
            genreArtworks.map { ($0.genre, $0.coverArtId) },
            uniquingKeysWith: { first, _ in first }
        )
    }
    @State private var searchText = ""
    @State private var searchIsActive = false
    @State private var sortBy: GenreSortOption = .name
    @AppStorage("genresViewStyle") private var showAsList = true
    @AppStorage(UserDefaultsKeys.gridDensity) private var gridDensityRaw: String = GridDensity.comfortable.rawValue
    private var gridDensity: GridDensity { GridDensity(rawValue: gridDensityRaw) ?? .comfortable }
    @State private var cachedFilteredGenres: [Genre] = []

    enum GenreSortOption: String, CaseIterable {
        case name, songCount
        var label: String {
            switch self {
            case .name: "Name (A-Z)"
            case .songCount: "Song Count"
            }
        }
    }

    private func computeFilteredGenres() -> [Genre] {
        let base: [Genre]
        if searchText.isEmpty {
            base = genres
        } else {
            base = genres.filter {
                $0.value.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortBy {
        case .name:
            return base.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        case .songCount:
            return base.sorted { ($0.songCount ?? 0) > ($1.songCount ?? 0) }
        }
    }

    var body: some View {
        Group {
            if showAsList {
                genreList
            } else {
                genreGrid
            }
        }
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle("Genres")
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Genres")
        #else
        .searchable(text: $searchText, isPresented: $searchIsActive, prompt: "Search Genres")
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchBar)) { _ in
            searchIsActive = false
            DispatchQueue.main.async { searchIsActive = true }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .overlay {
            if isLoading && genres.isEmpty {
                ProgressView("Loading genres...")
            } else if let error, genres.isEmpty {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadGenres() } }
                        .buttonStyle(.bordered)
                }
            } else if !isLoading && genres.isEmpty {
                ContentUnavailableView {
                    Label("No Genres", systemImage: "music.note")
                } description: {
                    Text("No genres found in your library")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAsList.toggle()
                    }
                } label: {
                    Image(systemName: showAsList ? "square.grid.2x2" : "list.bullet")
                }
                .accessibilityLabel(showAsList ? "Grid View" : "List View")
                .accessibilityIdentifier("genresViewToggle")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(GenreSortOption.allCases, id: \.self) { option in
                        Button {
                            sortBy = option
                        } label: {
                            HStack {
                                Text(option.label)
                                if sortBy == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        Task { await loadGenres() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .task { await loadGenres() }
        .onChange(of: searchText) { recomputeFilteredGenres() }
        .onChange(of: sortBy) { recomputeFilteredGenres() }
        .refreshable { await loadGenres() }
    }

    // MARK: - List view

    private var genreList: some View {
        List(cachedFilteredGenres) { genre in
            NavigationLink {
                AlbumsView(listType: .byGenre, title: genre.value.cleanedGenreDisplay, genre: genre.value)
            } label: {
                HStack(spacing: 12) {
                    GenreIconView(genre: genre.value, coverArtId: genreArtworkMap[genre.value])
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(genre.value.cleanedGenreDisplay)
                            .font(.body)
                        Text(verbatim: "\(genre.albumCount ?? 0) albums · \(genre.songCount ?? 0) songs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .accessibilityIdentifier("genreRow_\(genre.value)")
        }
        .listStyle(.plain)
    }

    // MARK: - Grid view

    private var genreGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: gridDensity.minimumWidth), spacing: 16)
            ], spacing: 20) {
                ForEach(cachedFilteredGenres) { genre in
                    NavigationLink {
                        AlbumsView(listType: .byGenre, title: genre.value.cleanedGenreDisplay, genre: genre.value)
                    } label: {
                        genreCard(genre)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("genreCard_\(genre.value)")
                }
            }
            .padding(16)
        }
    }

    private func genreCard(_ genre: Genre) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GenreIconView(genre: genre.value, coverArtId: genreArtworkMap[genre.value])
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(genre.value.cleanedGenreDisplay)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(verbatim: "\(genre.albumCount ?? 0) albums · \(genre.songCount ?? 0) songs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func recomputeFilteredGenres() {
        cachedFilteredGenres = computeFilteredGenres()
    }

    private func loadGenres() async {
        let client = appState.subsonicClient

        // Try local SwiftData first — derive genres from cached songs
        if genres.isEmpty {
            let localGenres = deriveGenresFromCache()
            if !localGenres.isEmpty {
                genres = localGenres
                recomputeFilteredGenres()
            }
        }

        // Show cached API response if no local data
        if genres.isEmpty,
           let cached = await client.cachedResponse(for: .getGenres, ttl: 3600) {
            genres = (cached.genres?.genre ?? [])
                .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
            recomputeFilteredGenres()
        }
        isLoading = genres.isEmpty
        error = nil
        defer { isLoading = false }
        do {
            genres = try await client.getGenres()
                .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
            recomputeFilteredGenres()
            await loadGenreArt(client: client)
        } catch {
            // If network fails but we have local data, load art from cache
            if !genres.isEmpty {
                await loadGenreArt(client: client)
            } else {
                self.error = ErrorPresenter.userMessage(for: error)
            }
        }
    }

    private func deriveGenresFromCache() -> [Genre] {
        // Use albums (much fewer records) to derive genre counts
        let allAlbums = (try? modelContext.fetch(FetchDescriptor<CachedAlbum>())) ?? []
        var genreAlbumCount: [String: Int] = [:]
        var genreSongCount: [String: Int] = [:]

        for album in allAlbums {
            for genre in album.genres where !genre.isEmpty {
                genreAlbumCount[genre, default: 0] += 1
                genreSongCount[genre, default: 0] += album.songCount ?? 0
            }
        }

        return genreAlbumCount.map { key, albumCount in
            Genre(songCount: genreSongCount[key] ?? 0, albumCount: albumCount, value: key)
        }.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
    }

    private func loadGenreArt(client: SubsonicClient) async {
        let existing = Set(genreArtworks.map(\.genre))
        for genre in genres where !existing.contains(genre.value) {
            guard let albums = try? await client.getAlbumList(type: .byGenre, size: 1, genre: genre.value),
                  let coverArt = albums.first?.coverArt else { continue }
            modelContext.insert(GenreArtwork(genre: genre.value, coverArtId: coverArt))
        }
        try? modelContext.save()
    }
}
