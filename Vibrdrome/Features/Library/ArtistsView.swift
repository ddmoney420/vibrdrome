import SwiftUI

struct ArtistsView: View {
    @Environment(AppState.self) private var appState
    @State private var indexes: [ArtistIndex] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""

    private var filteredIndexes: [(id: String, name: String, artists: [Artist])] {
        if searchText.isEmpty {
            return indexes.map { (id: $0.id, name: $0.name, artists: $0.artist ?? []) }
        }
        return indexes.compactMap { index in
            let filtered = (index.artist ?? []).filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
            guard !filtered.isEmpty else { return nil }
            return (id: index.id, name: index.name, artists: filtered)
        }
    }

    var body: some View {
        List {
            ForEach(filteredIndexes, id: \.id) { index in
                Section(header: Text(index.name)) {
                    ForEach(index.artists) { artist in
                        NavigationLink {
                            ArtistDetailView(artistId: artist.id)
                        } label: {
                            ArtistRow(artist: artist)
                        }
                        .accessibilityIdentifier("artistRow_\(artist.id)")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Artists")
        .searchable(text: $searchText, prompt: "Search Artists")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if isLoading && indexes.isEmpty {
                ProgressView("Loading artists...")
            } else if let error, indexes.isEmpty {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadArtists() } }
                        .buttonStyle(.bordered)
                }
            }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                Button { Task { await loadArtists() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        #endif
        .task { await loadArtists() }
        .refreshable { await loadArtists() }
    }

    private func loadArtists() async {
        let client = appState.subsonicClient
        // Show cached data instantly
        if indexes.isEmpty,
           let cached = await client.cachedResponse(for: .getArtists(), ttl: 1800) {
            indexes = cached.artists?.index ?? []
        }
        isLoading = indexes.isEmpty
        error = nil
        defer { isLoading = false }
        do {
            indexes = try await client.getArtists()
        } catch {
            if indexes.isEmpty {
                self.error = ErrorPresenter.userMessage(for: error)
            }
        }
    }
}
