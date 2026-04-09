import SwiftUI

struct GenresView: View {
    @Environment(AppState.self) private var appState
    @State private var genres: [Genre] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var genreArt: [String: String] = [:] // genre → coverArtId
    @State private var searchText = ""

    private var filteredGenres: [Genre] {
        if searchText.isEmpty { return genres }
        return genres.filter {
            $0.value.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(filteredGenres) { genre in
            NavigationLink {
                AlbumsView(listType: .byGenre, title: genre.value, genre: genre.value)
            } label: {
                HStack(spacing: 12) {
                    AlbumArtView(
                        coverArtId: genreArt[genre.value],
                        size: 48,
                        cornerRadius: 8
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(genre.value)
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
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle("Genres")
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Genres")
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
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                Button { Task { await loadGenres() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        #endif
        .task { await loadGenres() }
        .refreshable { await loadGenres() }
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
