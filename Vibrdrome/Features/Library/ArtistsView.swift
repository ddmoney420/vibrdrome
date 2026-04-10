import SwiftUI

struct ArtistsView: View {
    @Environment(AppState.self) private var appState
    @State private var indexes: [ArtistIndex] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var sortReversed = false

    enum ArtistSortOption: String, CaseIterable {
        case nameAZ, nameZA
        var label: String {
            switch self {
            case .nameAZ: "Name (A-Z)"
            case .nameZA: "Name (Z-A)"
            }
        }
    }

    private var filteredIndexes: [(id: String, name: String, artists: [Artist])] {
        let base: [(id: String, name: String, artists: [Artist])]
        if searchText.isEmpty {
            base = indexes.map { (id: $0.id, name: $0.name, artists: $0.artist ?? []) }
        } else {
            base = indexes.compactMap { index in
                let filtered = (index.artist ?? []).filter {
                    $0.name.localizedCaseInsensitiveContains(searchText)
                }
                guard !filtered.isEmpty else { return nil }
                return (id: index.id, name: index.name, artists: filtered)
            }
        }
        if sortReversed {
            return base.reversed().map { section in
                (id: section.id, name: section.name, artists: section.artists.reversed())
            }
        }
        return base
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
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Artists")
        #else
        .searchable(text: $searchText, prompt: "Search Artists")
        #endif
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        sortReversed = false
                    } label: {
                        HStack {
                            Text("Name (A-Z)")
                            if !sortReversed {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button {
                        sortReversed = true
                    } label: {
                        HStack {
                            Text("Name (Z-A)")
                            if sortReversed {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    Button {
                        Task { await loadArtists() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
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
