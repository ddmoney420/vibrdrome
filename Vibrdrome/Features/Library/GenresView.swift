import SwiftUI

struct GenresView: View {
    @Environment(AppState.self) private var appState
    @State private var genres: [Genre] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var genreArt: [String: String] = [:] // genre → coverArtId
    @State private var searchText = ""
    @State private var sortBy: GenreSortOption = .name
    @AppStorage("genresViewStyle") private var showAsList = true
    @AppStorage(UserDefaultsKeys.gridColumnsPerRow) private var gridColumns = 2

    enum GenreSortOption: String, CaseIterable {
        case name, songCount
        var label: String {
            switch self {
            case .name: "Name (A-Z)"
            case .songCount: "Song Count"
            }
        }
    }

    private var filteredGenres: [Genre] {
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
        .searchable(text: $searchText, prompt: "Search Genres")
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
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
        .refreshable { await loadGenres() }
    }

    // MARK: - List view

    private var genreList: some View {
        List(filteredGenres) { genre in
            NavigationLink {
                AlbumsView(listType: .byGenre, title: genre.value.cleanedGenreDisplay, genre: genre.value)
            } label: {
                HStack(spacing: 12) {
                    GenreIconView(genre: genre.value)
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16),
                                     count: max(2, min(10, gridColumns))), spacing: 20) {
                ForEach(filteredGenres) { genre in
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
            GenreIconView(genre: genre.value)
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

    private func loadGenres() async {
        let client = appState.subsonicClient
        // Show cached data instantly
        if genres.isEmpty,
           let cached = await client.cachedResponse(for: .getGenres, ttl: 3600) {
            genres = (cached.genres?.genre ?? [])
                .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        }
        isLoading = genres.isEmpty
        error = nil
        defer { isLoading = false }
        do {
            genres = try await client.getGenres()
                .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
            await loadGenreArt(client: client)
        } catch {
            if genres.isEmpty {
                self.error = ErrorPresenter.userMessage(for: error)
            }
        }
    }

    private func loadGenreArt(client: SubsonicClient) async {
        for genre in genres.prefix(30) where genreArt[genre.value] == nil {
            if let albums = try? await client.getAlbumList(type: .byGenre, size: 1, genre: genre.value),
               let coverArt = albums.first?.coverArt {
                genreArt[genre.value] = coverArt
            }
        }
    }
}
