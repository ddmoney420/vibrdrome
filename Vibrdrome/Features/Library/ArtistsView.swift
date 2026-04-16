import SwiftUI
import SwiftData
import os.log

struct ArtistsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var indexes: [ArtistIndex] = []
    @State private var localFilteredArtists: [Artist]?
    @State private var filterTask: Task<Void, Never>?
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var sortReversed = false
    @AppStorage("artistsViewStyle") private var showAsList = true
    @State private var cachedFilteredIndexes: [(id: String, name: String, artists: [Artist])] = []

    enum ArtistSortOption: String, CaseIterable {
        case nameAZ, nameZA
        var label: String {
            switch self {
            case .nameAZ: "Name (A-Z)"
            case .nameZA: "Name (Z-A)"
            }
        }
    }

    private func computeFilteredIndexes() -> [(id: String, name: String, artists: [Artist])] {
        // When local filters are active, use flat filtered list (no index grouping)
        if let filtered = localFilteredArtists {
            let source: [Artist]
            if searchText.isEmpty {
                source = filtered
            } else {
                source = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            }
            let sorted = sortReversed ? source.reversed() : Array(source)
            guard !sorted.isEmpty else { return [] }
            return [("filtered", "Results", sorted)]
        }

        var raw: [(id: String, name: String, artists: [Artist])]
        if searchText.isEmpty {
            raw = indexes.map { (id: $0.id, name: $0.name, artists: $0.artist ?? []) }
        } else {
            raw = indexes.compactMap { index in
                let filtered = (index.artist ?? []).filter {
                    $0.name.localizedCaseInsensitiveContains(searchText)
                }
                guard !filtered.isEmpty else { return nil }
                return (id: index.id, name: index.name, artists: filtered)
            }
        }
        // Split combined sections like "X-Z" into individual letter sections
        raw = raw.flatMap { section -> [(id: String, name: String, artists: [Artist])] in
            guard section.name.contains("-"), section.name.count <= 3 else { return [section] }
            let grouped = Dictionary(grouping: section.artists) { artist -> String in
                let first = artist.name.prefix(1).uppercased()
                return first.rangeOfCharacter(from: .letters) != nil ? first : "#"
            }
            return grouped.keys.sorted().map { letter in
                (id: "\(section.id)_\(letter)", name: letter, artists: grouped[letter]!)
            }
        }
        // Rename "Unknown" to "#"
        raw = raw.map { section in
            if section.name.localizedCaseInsensitiveCompare("Unknown") == .orderedSame
                || section.name == "[Unknown]"
                || section.name.hasPrefix("[")
                || (section.name.count > 1 && section.name.rangeOfCharacter(from: .letters) == nil) {
                return (id: section.id, name: "#", artists: section.artists)
            }
            return section
        }
        if sortReversed {
            return raw.reversed().map { section in
                (id: section.id, name: section.name, artists: section.artists.reversed())
            }
        }
        return raw
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
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Artists")
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
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if appState.activeSidePanel == .artistFilters {
                            appState.activeSidePanel = nil
                        } else {
                            appState.activeSidePanel = .artistFilters
                        }
                    }
                } label: {
                    Image(systemName: appState.artistFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Artist Filters")
                .accessibilityIdentifier("artistFilterToggle")
            }
            #endif
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
        .task {
            await loadArtists()
            #if os(macOS)
            applyLocalFilters()
            #endif
            recomputeFilteredIndexes()
        }
        .onChange(of: searchText) { recomputeFilteredIndexes() }
        .onChange(of: sortReversed) { recomputeFilteredIndexes() }
        .refreshable { await loadArtists() }
        #if os(macOS)
        .onChange(of: appState.artistFilter.isFavorited) { debouncedApplyLocalFilters() }
        .onChange(of: appState.artistFilter.selectedGenres) { debouncedApplyLocalFilters() }
        #endif
    }

    // MARK: - List view

    private var artistList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(cachedFilteredIndexes, id: \.id) { index in
                    Section(header: Text(index.name).id(index.name)) {
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
            .contentMargins(.trailing, 28)
            .overlay(alignment: .trailing) {
                sectionIndex(proxy: proxy)
            }
        }
    }

    private func sectionIndex(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 1) {
            ForEach(cachedFilteredIndexes, id: \.id) { index in
                let label = sectionIndexLabel(index.name)
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { proxy.scrollTo(index.name, anchor: .top) }
                    }
            }
        }
        .padding(.trailing, 6)
        .accessibilityLabel("Section Index")
    }

    /// Section names are now pre-split, so just return as-is
    private func sectionIndexLabel(_ name: String) -> String {
        name
    }

    // MARK: - Grid view (circular bubbles)

    private var artistGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                ForEach(cachedFilteredIndexes, id: \.id) { index in
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
            GeometryReader { geo in
                AlbumArtView(
                    coverArtId: artist.coverArt,
                    size: geo.size.width,
                    cornerRadius: geo.size.width / 2
                )
            }
            .aspectRatio(1, contentMode: .fit)
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
            recomputeFilteredIndexes()
        } catch {
            if indexes.isEmpty {
                self.error = ErrorPresenter.userMessage(for: error)
            }
        }
    }

    private func recomputeFilteredIndexes() {
        cachedFilteredIndexes = computeFilteredIndexes()
    }

    #if os(macOS)
    private func debouncedApplyLocalFilters() {
        filterTask?.cancel()
        filterTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            applyLocalFilters()
        }
    }

    private func applyLocalFilters() {
        let filter = appState.artistFilter
        guard filter.isActive else {
            localFilteredArtists = nil
            recomputeFilteredIndexes()
            return
        }

        do {
            let allArtists: [Artist]
            if let cachedArtists = appState.libraryCache.artists {
                allArtists = cachedArtists
            } else {
                var descriptor = FetchDescriptor<CachedArtist>()
                descriptor.sortBy = [SortDescriptor(\.name)]
                allArtists = try modelContext.fetch(descriptor).map { $0.toArtist() }
            }

            // Pre-compute artist IDs that have albums matching selected genres
            var artistIdsWithMatchingGenres: Set<String>?
            if !filter.selectedGenres.isEmpty {
                let allAlbums: [Album]
                if let cachedAlbums = appState.libraryCache.albums {
                    allAlbums = cachedAlbums
                } else {
                    let albumDescriptor = FetchDescriptor<CachedAlbum>()
                    allAlbums = try modelContext.fetch(albumDescriptor).map { $0.toAlbum() }
                }
                var ids = Set<String>()
                for album in allAlbums {
                    if let genre = album.genre, filter.selectedGenres.contains(genre),
                       let artistId = album.artistId {
                        ids.insert(artistId)
                    }
                }
                artistIdsWithMatchingGenres = ids
            }

            let filtered = allArtists.filter { artist in
                // Favorited filter
                switch filter.isFavorited {
                case .yes: if artist.starred == nil { return false }
                case .no: if artist.starred != nil { return false }
                case .none: break
                }

                // Genre filter (via album lookup)
                if let matchIds = artistIdsWithMatchingGenres {
                    if !matchIds.contains(artist.id) { return false }
                }

                return true
            }

            localFilteredArtists = filtered
            recomputeFilteredIndexes()
        } catch {
            Logger(subsystem: "com.vibrdrome.app", category: "Artists")
                .error("Failed to apply local filters: \(error)")
            localFilteredArtists = nil
        }
    }
    #endif
}
