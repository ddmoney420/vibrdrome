import SwiftUI

struct ArtistsView: View {
    @Environment(AppState.self) private var appState
    @State private var indexes: [ArtistIndex] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            ForEach(indexes) { index in
                Section(header: Text(index.name)) {
                    ForEach(index.artist ?? []) { artist in
                        NavigationLink {
                            ArtistDetailView(artistId: artist.id)
                        } label: {
                            ArtistRow(artist: artist)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Artists")
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
