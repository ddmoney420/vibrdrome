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
        .task { await loadArtists() }
        .refreshable { await loadArtists() }
    }

    private func loadArtists() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            indexes = try await appState.subsonicClient.getArtists()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
