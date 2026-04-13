import SwiftUI

struct ArtistsView: View {
    @Environment(AppState.self) private var appState
    @State private var indexes: [ArtistIndex] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var sortReversed = false
    @AppStorage("artistsViewStyle") private var showAsList = true

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
        Group {
            if showAsList {
                artistList
            } else {
                artistGrid
            }
        }
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
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAsList.toggle()
                    }
                } label: {
                    Image(systemName: showAsList ? "square.grid.2x2" : "list.bullet")
                }
                .accessibilityLabel(showAsList ? "Grid View" : "List View")
                .accessibilityIdentifier("artistsViewToggle")
            }
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

    // MARK: - List view

    private var artistList: some View {
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
    }

    // MARK: - Grid view (circular bubbles)

    private var artistGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                ForEach(filteredIndexes, id: \.id) { index in
                    Section {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 16)
                        ], spacing: 20) {
                            ForEach(index.artists) { artist in
                                NavigationLink {
                                    ArtistDetailView(artistId: artist.id)
                                } label: {
                                    artistGridCard(artist)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("artistCard_\(artist.id)")
                            }
                        }
                        .padding(.horizontal, 16)
                    } header: {
                        Text(index.name)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(.bar)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func artistGridCard(_ artist: Artist) -> some View {
        VStack(spacing: 8) {
            AlbumArtView(
                coverArtId: artist.coverArt,
                size: Theme.artistBubbleSize,
                cornerRadius: Theme.artistBubbleSize / 2
            )
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(artist.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let count = artist.albumCount {
                Text(verbatim: "\(count) album\(count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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
