import SwiftData
import SwiftUI
import os.log

struct AlbumsView: View {
    let listType: AlbumListType
    var title: String = "Albums"
    var genre: String?
    var fromYear: Int?
    var toYear: Int?

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var albums: [Album] = []
    @State private var localFilteredAlbums: [Album]?
    @State private var filterTask: Task<Void, Never>?
    @State private var isLoading = true
    @State private var error: String?
    @State private var hasMore = true
    @State private var searchText = ""
    @State private var searchIsActive = false
    @State private var activeListType: AlbumListType?
    @State private var clientSideSort: AlbumSortOption?
    @State private var getInfoTarget: GetInfoTarget?
    @AppStorage("albumsViewStyle") private var showAsList = false
    @State private var showSaveCollection = false
    @State private var collectionName = ""
    @State private var availableGenres: [String] = []
    @State private var activeGenre: String?
    @State private var searchResults: [Album] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var favoritedAlbumIds: Set<String> = []
    @SceneStorage("albumsFilter") private var filterRaw: String = AlbumFilter.all.rawValue
    @Query(filter: #Predicate<DownloadedSong> { $0.isComplete == true })
    private var downloadedSongs: [DownloadedSong]
    @State private var cachedFilteredAlbums: [Album] = []
    @State private var scrollLoadTask: Task<Void, Never>?
    @State private var pendingPageTarget: Int = 0
    @State private var visibleIndices: Set<Int> = []
    @State private var restoredScrollIndex: Int?
    private let pageSize = 40

    enum AlbumFilter: String, CaseIterable, Identifiable {
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

    private var activeFilter: AlbumFilter {
        AlbumFilter(rawValue: filterRaw) ?? .all
    }

    private var downloadedAlbumNames: Set<String> {
        Set(downloadedSongs.compactMap { $0.albumName?.lowercased() })
    }

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
        if activeGenre != nil && activeListType == nil { return .byGenre }
        return activeListType ?? listType
    }

    private var effectiveGenre: String? {
        activeGenre ?? genre
    }

    private var cacheKey: String {
        "\(listType.rawValue)_\(genre ?? "")_\(fromYear ?? 0)_\(toYear ?? 0)"
    }

    init(listType: AlbumListType, title: String = "Albums", genre: String? = nil, fromYear: Int? = nil, toYear: Int? = nil) {
        self.listType = listType
        self.title = title
        self.genre = genre
        self.fromYear = fromYear
        self.toYear = toYear

        let key = "\(listType.rawValue)_\(genre ?? "")_\(fromYear ?? 0)_\(toYear ?? 0)"
        if let snapshot = AppState.shared.albumsViewSnapshots[key] {
            _albums = State(initialValue: snapshot.albums)
            _hasMore = State(initialValue: snapshot.hasMore)
            _isLoading = State(initialValue: false)
            _cachedFilteredAlbums = State(initialValue: snapshot.albums)
            _restoredScrollIndex = State(initialValue: snapshot.scrollIndex)
        }
    }

    private func computeFilteredAlbums() -> [Album] {
        let source = localFilteredAlbums ?? albums
        var result = source
        switch activeFilter {
        case .all:
            break
        case .favorites:
            result = result.filter { favoritedAlbumIds.contains($0.id) }
        case .downloaded:
            result = result.filter { downloadedAlbumNames.contains($0.name.lowercased()) }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.artist ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
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
        .navigationBarTitleDisplayMode(.large)
        #else
        .searchable(text: $searchText, isPresented: $searchIsActive, prompt: "Search in Albums")
        #endif
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else {
                searchResults = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let results = try? await appState.subsonicClient.search(
                    query: trimmed, artistCount: 0, albumCount: 50, songCount: 0)
                guard !Task.isCancelled else { return }
                searchResults = results?.album ?? []
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchBar)) { _ in
            searchIsActive = false
            DispatchQueue.main.async { searchIsActive = true }
        }
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
                    Menu {
                        Button {
                            activeGenre = nil
                            albums = []
                            hasMore = true
                            Task { await loadAlbums() }
                        } label: {
                            HStack {
                                Text("All Genres")
                                if activeGenre == nil && genre == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        Divider()
                        ForEach(availableGenres, id: \.self) { g in
                            Button {
                                activeGenre = g
                                albums = []
                                hasMore = true
                                Task { await loadAlbums() }
                            } label: {
                                HStack {
                                    Text(g.cleanedGenreDisplay)
                                    if effectiveGenre == g {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(effectiveGenre?.cleanedGenreDisplay ?? "Genre", systemImage: "guitars")
                    }
                    Divider()
                    Picker("Filter", selection: $filterRaw) {
                        ForEach(AlbumFilter.allCases) { option in
                            Label(option.label, systemImage: option.icon).tag(option.rawValue)
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
                    Divider()
                    Button {
                        let name = effectiveGenre?.cleanedGenreDisplay ?? title
                        collectionName = name
                        showSaveCollection = true
                    } label: {
                        Label("Save as Collection", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .alert("Save Collection", isPresented: $showSaveCollection) {
            TextField("Name", text: $collectionName)
            Button("Save") {
                let count = (try? modelContext.fetchCount(FetchDescriptor<AlbumCollection>())) ?? 0
                let collection = AlbumCollection(
                    name: collectionName,
                    listType: effectiveListType,
                    genre: effectiveGenre,
                    fromYear: fromYear,
                    toYear: toYear,
                    order: count
                )
                modelContext.insert(collection)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) { }
        }
        .navigationDestination(for: AlbumNavItem.self) { item in
            AlbumDetailView(albumId: item.id)
        }
        .task {
            if albums.isEmpty {
                await loadAlbums()
            }
            if availableGenres.isEmpty {
                availableGenres = (try? await appState.subsonicClient.getGenres()
                    .map(\.value).sorted()) ?? []
            }
            await loadFavoritedAlbumIds()
            #if os(macOS)
            applyLocalFilters()
            #endif
            recomputeFilteredAlbums()
        }
        .onChange(of: searchText) { recomputeFilteredAlbums() }
        .onChange(of: filterRaw) { recomputeFilteredAlbums() }
        .onChange(of: clientSideSort) { recomputeFilteredAlbums() }
        .onDisappear { saveSnapshot() }
        .refreshable {
            albums = []
            hasMore = true
            await loadAlbums()
        }
        #if os(iOS)
        .sheet(item: $getInfoTarget) { target in
            NavigationStack {
                GetInfoView(target: target)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { getInfoTarget = nil }
                        }
                    }
            }
            .environment(appState)
        }
        #endif
        #if os(macOS)
        .onChange(of: appState.albumFilter.isFavorited) { debouncedApplyLocalFilters() }
        .onChange(of: appState.albumFilter.isRated) { debouncedApplyLocalFilters() }
        .onChange(of: appState.albumFilter.isRecentlyPlayed) { debouncedApplyLocalFilters() }
        .onChange(of: appState.albumFilter.selectedArtistIds) { debouncedApplyLocalFilters() }
        .onChange(of: appState.albumFilter.selectedGenres) { debouncedApplyLocalFilters() }
        .onChange(of: appState.albumFilter.selectedLabels) { debouncedApplyLocalFilters() }
        .onChange(of: appState.albumFilter.year) { debouncedApplyLocalFilters() }
        #endif
    }

    private func loadFavoritedAlbumIds() async {
        guard favoritedAlbumIds.isEmpty else { return }
        if let starred = try? await appState.subsonicClient.getStarred(),
           let albums = starred.album {
            favoritedAlbumIds = Set(albums.map(\.id))
        }

    // MARK: - List view

    private var albumList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(0..<totalItemCount, id: \.self) { index in
                    Group {
                        if index < cachedFilteredAlbums.count {
                            let album = cachedFilteredAlbums[index]
                            NavigationLink(value: AlbumNavItem(id: album.id)) {
                                AlbumCard(album: album)
                            }
                            .accessibilityIdentifier("albumRow_\(album.id)")
                            .contextMenu { rowContextMenu(for: album) }
                        } else {
                            albumListPlaceholder
                        }
                    }
                    .id(index)
                    .onAppear {
                        visibleIndices.insert(index)
                        triggerLoadIfNeeded(at: index)
                    }
                    .onDisappear { visibleIndices.remove(index) }
                }
            }
            .listStyle(.plain)
            .onAppear { restoreScroll(proxy: proxy) }
        }
    }

    // MARK: - Grid view

    private var albumGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)
                ], spacing: 20) {
                    ForEach(0..<totalItemCount, id: \.self) { index in
                        Group {
                            if index < cachedFilteredAlbums.count {
                                let album = cachedFilteredAlbums[index]
                                NavigationLink(value: AlbumNavItem(id: album.id)) {
                                    albumGridCard(album)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("albumCard_\(album.id)")
                                .contextMenu { rowContextMenu(for: album) }
                            } else {
                                albumGridPlaceholder
                            }
                        }
                        .id(index)
                        .onAppear {
                            visibleIndices.insert(index)
                            triggerLoadIfNeeded(at: index)
                        }
                        .onDisappear { visibleIndices.remove(index) }
                    }
                }
                .padding(16)
            }
            .onAppear { restoreScroll(proxy: proxy) }
        }
    }

    private func albumGridCard(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                AlbumArtView(coverArtId: album.coverArt, size: geo.size.width, cornerRadius: 10)
            }
            .aspectRatio(1, contentMode: .fit)
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

            Divider()

            Button {
                #if os(macOS)
                openWindow(id: "get-info", value: GetInfoTarget(type: .album, id: album.id))
                #else
                getInfoTarget = GetInfoTarget(type: .album, id: album.id)
                #endif
            } label: { Label("Get Info", systemImage: "doc.text.magnifyingglass") }
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

    private var albumListPlaceholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                    .frame(width: 120, height: 14)
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                    .frame(width: 80, height: 12)
            }
            Spacer()
        }
    }

    private var albumGridPlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .aspectRatio(1, contentMode: .fit)
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)
                .frame(height: 14)
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)
                .frame(width: 80, height: 12)
        }
    }

    private var totalItemCount: Int {
        guard localFilteredAlbums == nil, searchText.isEmpty else { return cachedFilteredAlbums.count }
        guard hasMore, let totalCount = appState.libraryCache.albums?.count else { return cachedFilteredAlbums.count }
        return max(cachedFilteredAlbums.count, totalCount)
    }

    private func triggerLoadIfNeeded(at index: Int) {
        guard localFilteredAlbums == nil, hasMore else { return }
        if index >= cachedFilteredAlbums.count {
            // Scrolled into placeholder territory — always update target, debounce the load
            pendingPageTarget = max(pendingPageTarget, albums.count + (index - cachedFilteredAlbums.count) + pageSize)
            scrollLoadTask?.cancel()
            scrollLoadTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await loadPages()
            }
        } else if !isLoading {
            // Near end of loaded items — prefetch immediately
            let prefetchThreshold = max(cachedFilteredAlbums.count - 30, 0)
            if index >= prefetchThreshold {
                pendingPageTarget = max(pendingPageTarget, albums.count + pageSize)
                Task { await loadPages() }
            }
        }
    }

    private func loadAlbums() async {
        scrollLoadTask?.cancel()
        pendingPageTarget = 0
        let client = appState.subsonicClient
        let sortType = effectiveListType
        let endpoint = SubsonicEndpoint.getAlbumList2(
            type: sortType, size: pageSize, offset: 0,
            fromYear: fromYear, toYear: toYear, genre: effectiveGenre)
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
                type: sortType, size: pageSize, offset: 0, genre: effectiveGenre,
                fromYear: fromYear, toYear: toYear)
            albums = result
            hasMore = result.count >= pageSize
            recomputeFilteredAlbums()
            saveSnapshot()
        } catch {
            if albums.isEmpty {
                self.error = ErrorPresenter.userMessage(for: error)
            }
        }
    }

    private func loadPages() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer {
            isLoading = false
            // If target moved while loading, schedule another batch
            if albums.count < pendingPageTarget, hasMore {
                scrollLoadTask?.cancel()
                scrollLoadTask = Task { await loadPages() }
            }
        }
        while albums.count < pendingPageTarget, hasMore, !Task.isCancelled {
            do {
                let result = try await appState.subsonicClient.getAlbumList(
                    type: effectiveListType, size: pageSize, offset: albums.count, genre: effectiveGenre,
                    fromYear: fromYear, toYear: toYear)
                albums.append(contentsOf: result)
                hasMore = result.count >= pageSize
            } catch {
                hasMore = false
                break
            }
        }
        recomputeFilteredAlbums()
        saveSnapshot()
    }

    private func recomputeFilteredAlbums() {
        cachedFilteredAlbums = computeFilteredAlbums()
    }

    private func saveSnapshot() {
        appState.albumsViewSnapshots[cacheKey] = AppState.AlbumsViewSnapshot(
            albums: albums, hasMore: hasMore, scrollIndex: visibleIndices.min()
        )
    }

    private func restoreScroll(proxy: ScrollViewProxy) {
        if let target = restoredScrollIndex, target > 0, target < cachedFilteredAlbums.count {
            proxy.scrollTo(target, anchor: .top)
            restoredScrollIndex = nil
        }
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
        let filter = appState.albumFilter
        guard filter.isActive else {
            localFilteredAlbums = nil
            recomputeFilteredAlbums()
            return
        }

        do {
            let recentlyPlayedAlbumIds = recentlyPlayedIds(for: filter)
            let selectedArtistNames = selectedArtistNames(for: filter)
            let allAlbums: [Album]
            if let cachedAlbums = appState.libraryCache.albums {
                allAlbums = cachedAlbums
            } else {
                var descriptor = FetchDescriptor<CachedAlbum>()
                descriptor.sortBy = [SortDescriptor(\.name)]
                allAlbums = try modelContext.fetch(descriptor).map { $0.toAlbum() }
            }

            localFilteredAlbums = allAlbums.filter {
                albumMatchesFilter(
                    $0,
                    filter: filter,
                    recentIds: recentlyPlayedAlbumIds,
                    selectedArtistNames: selectedArtistNames
                )
            }
            recomputeFilteredAlbums()
        } catch {
            Logger(subsystem: "com.vibrdrome.app", category: "Albums")
                .error("Failed to apply local filters: \(error)")
            localFilteredAlbums = nil
        }
    }

    private func selectedArtistNames(for filter: LibraryFilter) -> Set<String> {
        guard !filter.selectedArtistIds.isEmpty else { return [] }
        let descriptor = FetchDescriptor<CachedArtist>()
        let cachedArtists = (try? modelContext.fetch(descriptor)) ?? []
        return Set(cachedArtists.compactMap { artist in
            filter.selectedArtistIds.contains(artist.id) ? artist.name : nil
        })
    }

    private func recentlyPlayedIds(for filter: LibraryFilter) -> Set<String>? {
        guard filter.isRecentlyPlayed else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let songDescriptor = FetchDescriptor<CachedSong>(
            predicate: #Predicate { $0.lastPlayed != nil && $0.lastPlayed! > cutoff }
        )
        let recentSongs = (try? modelContext.fetch(songDescriptor)) ?? []
        return Set(recentSongs.compactMap(\.albumId))
    }

    private func albumMatchesFilter(
        _ album: Album,
        filter: LibraryFilter,
        recentIds: Set<String>?,
        selectedArtistNames: Set<String>
    ) -> Bool {
        guard filter.isFavorited.matches(album.starred != nil) else { return false }
        guard filter.isRated.matches((album.userRating ?? 0) != 0) else { return false }
        if let recentIds, !recentIds.contains(album.id) { return false }
        if !filter.selectedArtistIds.isEmpty {
            let matchesById = album.artistId.map { filter.selectedArtistIds.contains($0) } ?? false
            let matchesByName = album.artist.map { selectedArtistNames.contains($0) } ?? false
            guard matchesById || matchesByName else {
                return false
            }
        }
        if !filter.selectedGenres.isEmpty {
            guard let genre = album.genre, filter.selectedGenres.contains(genre) else {
                return false
            }
        }
        if !filter.selectedLabels.isEmpty {
            guard let albumLabel = album.label, filter.selectedLabels.contains(albumLabel) else {
                return false
            }
        }
        if let yearFilter = filter.year {
            guard album.year == yearFilter else { return false }
        }
        return true
    }
    #endif
}
