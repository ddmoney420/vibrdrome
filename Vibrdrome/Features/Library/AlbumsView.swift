import SwiftUI
import SwiftData
import os.log

struct AlbumsView: View {
    let listType: AlbumListType
    var title: String = "Albums"
    var genre: String?
    var fromYear: Int?
    var toYear: Int?

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var albums: [Album] = []
    @State private var localFilteredAlbums: [Album]?
    @State private var isLoading = true
    @State private var error: String?
    @State private var hasMore = true
    @State private var searchText = ""
    @State private var activeListType: AlbumListType?
    @State private var clientSideSort: AlbumSortOption?
    @AppStorage("albumsViewStyle") private var showAsList = false
    @AppStorage(UserDefaultsKeys.gridColumnsPerRow) private var gridColumns = 2
    private let pageSize = 40

    enum AlbumSortOption: String, CaseIterable {
        case name, artist, year, recentlyAdded
        var label: String {
            switch self {
            case .name: "Name"
            case .artist: "Artist"
            case .year: "Year"
            case .recentlyAdded: "Recently Added"
            }
        }
        var albumListType: AlbumListType {
            switch self {
            case .name: .alphabeticalByName
            case .artist: .alphabeticalByArtist
            case .year: .byYear
            case .recentlyAdded: .newest
            }
        }
    }

    private var effectiveListType: AlbumListType {
        activeListType ?? listType
    }

    private var filteredAlbums: [Album] {
        let source = localFilteredAlbums ?? albums
        var result = source
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.artist ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        // Client-side sort for year (API doesn't support sort by year without range)
        if clientSideSort == .year {
            result.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        }
        return result
    }

    var body: some View {
        Group {
            if showAsList {
                albumList
            } else {
                albumGrid
            }
        }
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle(title)
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search in Albums")
        #else
        .searchable(text: $searchText, prompt: "Search in Albums")
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if isLoading && albums.isEmpty {
                ProgressView("Loading albums...")
            } else if let error, albums.isEmpty {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadAlbums() } }
                        .buttonStyle(.bordered)
                }
            } else if !isLoading && albums.isEmpty {
                ContentUnavailableView {
                    Label("No Albums", systemImage: "square.stack")
                } description: {
                    Text("No albums found")
                }
            }
        }
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if appState.activeSidePanel == .albumFilters {
                            appState.activeSidePanel = nil
                        } else {
                            appState.activeSidePanel = .albumFilters
                        }
                    }
                } label: {
                    Image(systemName: appState.albumFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Album Filters")
                .accessibilityIdentifier("albumFilterToggle")
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
                .accessibilityIdentifier("albumsViewToggle")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(AlbumSortOption.allCases, id: \.self) { option in
                        Button {
                            if option == .year {
                                clientSideSort = .year
                                activeListType = nil
                            } else {
                                clientSideSort = nil
                                activeListType = option.albumListType
                                albums = []
                                hasMore = true
                                Task { await loadAlbums() }
                            }
                        } label: {
                            HStack {
                                Text(option.label)
                                if option == .year && clientSideSort == .year {
                                    Image(systemName: "checkmark")
                                } else if option != .year && effectiveListType == option.albumListType && clientSideSort == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        albums = []
                        hasMore = true
                        Task { await loadAlbums() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .task {
            await loadAlbums()
            #if os(macOS)
            applyLocalFilters()
            #endif
        }
        .refreshable {
            albums = []
            hasMore = true
            await loadAlbums()
        }
        #if os(macOS)
        .onChange(of: appState.albumFilter.isFavorited) { applyLocalFilters() }
        .onChange(of: appState.albumFilter.isRated) { applyLocalFilters() }
        .onChange(of: appState.albumFilter.isRecentlyPlayed) { applyLocalFilters() }
        .onChange(of: appState.albumFilter.selectedArtistIds) { applyLocalFilters() }
        .onChange(of: appState.albumFilter.selectedGenres) { applyLocalFilters() }
        .onChange(of: appState.albumFilter.selectedLabels) { applyLocalFilters() }
        .onChange(of: appState.albumFilter.year) { applyLocalFilters() }
        #endif
    }

    // MARK: - List view

    private var albumList: some View {
        List {
            ForEach(filteredAlbums) { album in
                NavigationLink {
                    AlbumDetailView(albumId: album.id)
                } label: {
                    AlbumCard(album: album)
                }
                .accessibilityIdentifier("albumRow_\(album.id)")
                .contextMenu { rowContextMenu(for: album) }
                .onAppear { paginateIfNeeded(album) }
            }

            if isLoading && !albums.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Grid view

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: max(2, min(4, gridColumns)))
    }

    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridItems, spacing: 20) {
                ForEach(filteredAlbums) { album in
                    NavigationLink {
                        AlbumDetailView(albumId: album.id)
                    } label: {
                        albumGridCard(album)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("albumCard_\(album.id)")
                    .contextMenu { rowContextMenu(for: album) }
                    .onAppear { paginateIfNeeded(album) }
                }
            }
            .padding(16)

            if isLoading && !albums.isEmpty {
                ProgressView()
                    .padding()
            }
        }
    }

    private func albumGridCard(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AlbumArtView(coverArtId: album.coverArt, size: Theme.albumCardSize, cornerRadius: 10)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(album.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            if let artist = album.artist {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func rowContextMenu(for album: Album) -> some View {
        Group {
            Button {
                albumAction(album) { songs in
                    if let first = songs.first { AudioEngine.shared.play(song: first, from: songs, at: 0) }
                }
            } label: { Label("Play", systemImage: "play.fill") }

            Button {
                albumAction(album) { songs in
                    var shuffled = songs; shuffled.shuffle()
                    if let first = shuffled.first { AudioEngine.shared.play(song: first, from: shuffled, at: 0) }
                }
            } label: { Label("Shuffle", systemImage: "shuffle") }

            Button {
                albumAction(album) { songs in AudioEngine.shared.addToQueueNext(songs) }
            } label: { Label("Play Next", systemImage: "text.insert") }

            Button {
                albumAction(album) { songs in AudioEngine.shared.addToQueue(songs) }
            } label: { Label("Add to Queue", systemImage: "text.append") }

            Button {
                albumAction(album) { songs in
                    DownloadManager.shared.downloadAlbum(songs: songs, client: appState.subsonicClient)
                }
            } label: { Label("Download", systemImage: "arrow.down.circle") }
        }
    }

    private func albumAction(_ album: Album, action: @escaping ([Song]) -> Void) {
        Task {
            do {
                let detail = try await appState.subsonicClient.getAlbum(id: album.id)
                if let songs = detail.song, !songs.isEmpty { action(songs) }
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "Albums")
                    .error("Album action failed: \(error)")
            }
        }
    }

    private func paginateIfNeeded(_ album: Album) {
        guard localFilteredAlbums == nil else { return }
        if album.id == albums.last?.id && hasMore {
            Task { await loadMore() }
        }
    }

    private func loadAlbums() async {
        let client = appState.subsonicClient
        let sortType = effectiveListType
        let endpoint = SubsonicEndpoint.getAlbumList2(
            type: sortType, size: pageSize, offset: 0,
            fromYear: fromYear, toYear: toYear, genre: genre)
        // Show cached first page instantly
        if albums.isEmpty,
           let cached = await client.cachedResponse(for: endpoint, ttl: 600) {
            albums = cached.albumList2?.album ?? []
        }
        isLoading = albums.isEmpty
        error = nil
        defer { isLoading = false }
        do {
            let result = try await client.getAlbumList(
                type: sortType, size: pageSize, offset: 0, genre: genre,
                fromYear: fromYear, toYear: toYear)
            albums = result
            hasMore = result.count >= pageSize
        } catch {
            if albums.isEmpty {
                self.error = ErrorPresenter.userMessage(for: error)
            }
        }
    }

    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appState.subsonicClient.getAlbumList(
                type: effectiveListType, size: pageSize, offset: albums.count, genre: genre,
                fromYear: fromYear, toYear: toYear)
            albums.append(contentsOf: result)
            hasMore = result.count >= pageSize
        } catch {
            hasMore = false
        }
    }

    #if os(macOS)
    private func applyLocalFilters() {
        let filter = appState.albumFilter
        guard filter.isActive else {
            localFilteredAlbums = nil
            return
        }

        do {
            var descriptor = FetchDescriptor<CachedAlbum>()
            descriptor.sortBy = [SortDescriptor(\.name)]
            let allAlbums = try modelContext.fetch(descriptor)

            // Pre-compute recently played album IDs if needed
            var recentlyPlayedAlbumIds: Set<String>?
            if filter.isRecentlyPlayed {
                let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                let songDescriptor = FetchDescriptor<CachedSong>(
                    predicate: #Predicate { $0.lastPlayed != nil && $0.lastPlayed! > cutoff }
                )
                let recentSongs = (try? modelContext.fetch(songDescriptor)) ?? []
                recentlyPlayedAlbumIds = Set(recentSongs.compactMap(\.albumId))
            }

            let filtered = allAlbums.filter { album in
                // Favorited filter
                switch filter.isFavorited {
                case .yes: if !album.isStarred { return false }
                case .no: if album.isStarred { return false }
                case .none: break
                }

                // Rated filter
                switch filter.isRated {
                case .yes: if album.userRating == 0 { return false }
                case .no: if album.userRating != 0 { return false }
                case .none: break
                }

                // Recently played filter
                if let recentIds = recentlyPlayedAlbumIds {
                    if !recentIds.contains(album.id) { return false }
                }

                // Artist filter
                if !filter.selectedArtistIds.isEmpty {
                    guard let artistId = album.artistId, filter.selectedArtistIds.contains(artistId) else {
                        return false
                    }
                }

                // Genre filter
                if !filter.selectedGenres.isEmpty {
                    guard let genre = album.genre, filter.selectedGenres.contains(genre) else {
                        return false
                    }
                }

                // Label filter
                if !filter.selectedLabels.isEmpty {
                    guard let albumLabel = album.label, filter.selectedLabels.contains(albumLabel) else {
                        return false
                    }
                }

                // Year filter
                if let yearFilter = filter.year {
                    guard album.year == yearFilter else { return false }
                }

                return true
            }

            localFilteredAlbums = filtered.map { $0.toAlbum() }
        } catch {
            Logger(subsystem: "com.vibrdrome.app", category: "Albums")
                .error("Failed to apply local filters: \(error)")
            localFilteredAlbums = nil
        }
    }
    #endif
}
