import SwiftData
import SwiftUI

struct ArtistsView: View {
    @Environment(AppState.self) private var appState
    @State private var indexes: [ArtistIndex] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var searchText = ""
    @State private var searchIsActive = false
    @State private var sortReversed = false
    @State private var favoritedArtistIds: Set<String> = []
    @AppStorage("artistsViewStyle") private var showAsList = true
    @AppStorage(UserDefaultsKeys.gridColumnsPerRow) private var gridColumns = 2
    @SceneStorage("artistsFilter") private var filterRaw: String = ArtistFilter.all.rawValue
    @Query(filter: #Predicate<DownloadedSong> { $0.isComplete == true })
    private var downloadedSongs: [DownloadedSong]

    enum ArtistFilter: String, CaseIterable, Identifiable {
        case all, favorites, downloaded
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All"
            case .favorites: "Favorites"
            case .downloaded: "Downloaded"
            }
        }
        var icon: String {
            switch self {
            case .all: "line.3.horizontal.decrease.circle"
            case .favorites: "heart.fill"
            case .downloaded: "arrow.down.circle.fill"
            }
        }
    }

    private var activeFilter: ArtistFilter {
        ArtistFilter(rawValue: filterRaw) ?? .all
    }

    private var downloadedArtistNames: Set<String> {
        Set(downloadedSongs.compactMap { $0.artistName?.lowercased() })
    }

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
        var raw: [(id: String, name: String, artists: [Artist])]
        let downloaded = downloadedArtistNames
        let favorited = favoritedArtistIds
        func passesFilter(_ artist: Artist) -> Bool {
            switch activeFilter {
            case .all: return true
            case .favorites: return favorited.contains(artist.id)
            case .downloaded: return downloaded.contains(artist.name.lowercased())
            }
        }
        if searchText.isEmpty {
            raw = indexes.compactMap { index in
                let artists = (index.artist ?? []).filter(passesFilter)
                guard !artists.isEmpty else { return nil }
                return (id: index.id, name: index.name, artists: artists)
            }
        } else {
            raw = indexes.compactMap { index in
                let filtered = (index.artist ?? []).filter {
                    $0.name.localizedCaseInsensitiveContains(searchText) && passesFilter($0)
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
        .navigationBarTitleDisplayMode(.large)
        #else
        .searchable(text: $searchText, isPresented: $searchIsActive, prompt: "Search Artists")
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchBar)) { _ in
            searchIsActive = false
            DispatchQueue.main.async { searchIsActive = true }
        }
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
                    Picker("Filter", selection: $filterRaw) {
                        ForEach(ArtistFilter.allCases) { option in
                            Label(option.label, systemImage: option.icon).tag(option.rawValue)
                        }
                    }
                    Divider()
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
                    Image(systemName: activeFilter == .all ? "arrow.up.arrow.down" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .task { await loadArtists() }
        .task { await loadFavorites() }
        .refreshable { await loadArtists() }
    }

    private func loadFavorites() async {
        guard favoritedArtistIds.isEmpty else { return }
        if let starred = try? await appState.subsonicClient.getStarred(),
           let artists = starred.artist {
            favoritedArtistIds = Set(artists.map(\.id))
        }
    }

    // MARK: - List view

    private var artistList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredIndexes, id: \.id) { index in
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
            ForEach(filteredIndexes, id: \.id) { index in
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
                ForEach(filteredIndexes, id: \.id) { index in
                    Section {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16),
                                                 count: max(2, min(10, gridColumns))), spacing: 20) {
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
                let artSize = min(geo.size.width, geo.size.height)
                AlbumArtView(
                    coverArtId: artist.coverArt,
                    size: artSize,
                    cornerRadius: artSize / 2
                )
                .frame(maxWidth: .infinity)
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
        } catch {
            if indexes.isEmpty {
                self.error = ErrorPresenter.userMessage(for: error)
            }
        }
    }
}
