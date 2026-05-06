import Nuke
import SwiftData
import SwiftUI
import os.log

// MARK: - AlbumsViewModel

/// Owns all data-fetching, filtering, and pagination state for AlbumsView.
/// AlbumsView is a pure rendering shell that reads from this model.
@Observable
@MainActor
final class AlbumsViewModel {
    // MARK: Enums (shared with view via typealiases)

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

    // MARK: Published state (read by view)

    var albums: [Album] = []
    var indexedAlbums: [(offset: Int, element: Album)] = []
    var prefetchRequests: [ImageRequest?] = []
    var blurRequests: [ImageRequest?] = []
    var isLoading = true
    var error: String?
    var hasMore = true
    var availableGenres: [String] = []
    var searchResults: [Album] = []
    var activeListType: AlbumListType?
    var clientSideSort: AlbumSortOption?
    var activeGenre: String?
    var favoritedAlbumIds: Set<String> = []
    var downloadedAlbumNames: Set<String> = []
    var localFilteredAlbums: [Album]?
    private(set) var cachedFilteredAlbums: [Album] = []
    var gridColumns: [GridItem] = []
    var gridCellWidth: CGFloat = 170
    private(set) var gridColumnCount: Int = 2

    // MARK: Configuration (set once at init)

    let listType: AlbumListType
    let genre: String?
    let fromYear: Int?
    let toYear: Int?
    private let pageSize = 120
    private let cacheKey: String

    // MARK: Private state

    private var pendingPageTarget = 0
    private var lastPrefetchIndex = -20
    private var filterTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var isLoadingPages = false

    /// Near-window prefetcher: decodes bitmaps for cells just off-screen at high priority.
    private let nearPrefetcher: ImagePrefetcher = {
        let p = ImagePrefetcher(destination: .memoryCache)
        p.priority = .high
        return p
    }()

    /// Far-window prefetcher: decodes bitmaps for the wider scroll-ahead window at normal priority.
    private let farPrefetcher: ImagePrefetcher = {
        let p = ImagePrefetcher(destination: .memoryCache)
        p.priority = .normal
        return p
    }()

    /// Full-library disk warmup: raw JPEGs into disk cache so memory-miss cells load fast.
    private let bulkPrefetcher: ImagePrefetcher = {
        let p = ImagePrefetcher(destination: .diskCache)
        p.priority = .veryLow
        return p
    }()

    /// Thumbnail prefetcher: persists 32px blur placeholders using the isolated blur pipeline.
    private let thumbPrefetcher: ImagePrefetcher = {
        let p = ImagePrefetcher(pipeline: VibrdromeApp.blurPipeline, destination: .diskCache)
        p.priority = .normal
        return p
    }()

    private let logger = Logger(subsystem: "com.vibrdrome.app", category: "Albums")

    // MARK: Init

    init(listType: AlbumListType, genre: String? = nil, fromYear: Int? = nil, toYear: Int? = nil) {
        self.listType = listType
        self.genre = genre
        self.fromYear = fromYear
        self.toYear = toYear
        self.cacheKey = "\(listType.rawValue)_\(genre ?? "")_\(fromYear ?? 0)_\(toYear ?? 0)"

        if let snapshot = AppState.shared.albumsViewSnapshots[cacheKey] {
            albums = snapshot.albums
            hasMore = snapshot.hasMore
            isLoading = false
            cachedFilteredAlbums = snapshot.albums
            indexedAlbums = Array(snapshot.albums.enumerated())
        }
    }

    // MARK: Derived

    var effectiveListType: AlbumListType {
        if activeGenre != nil && activeListType == nil { return .byGenre }
        return activeListType ?? listType
    }

    var effectiveGenre: String? { activeGenre ?? genre }

    // MARK: Lifecycle

    func onAppear(
        appState: AppState,
        modelContext: ModelContext,
        downloadedSongs: [DownloadedSong],
        filterRaw: String
    ) async {
        downloadedAlbumNames = Set(downloadedSongs.compactMap { $0.albumName?.lowercased() })
        if albums.isEmpty {
            seedFromDisk(appState: appState, modelContext: modelContext, filterRaw: filterRaw)
            await loadAlbums(appState: appState, filterRaw: filterRaw)
        }
        if availableGenres.isEmpty {
            availableGenres = (try? await appState.subsonicClient.getGenres()
                .map(\.value).sorted()) ?? []
        }
        await loadFavoritedAlbumIds(appState: appState)
        recomputeFilteredAlbums(filterRaw: filterRaw)
        rebuildPrefetchRequests(client: appState.subsonicClient)
    }

    func onDisappear(appState: AppState) {
        saveSnapshot(appState: appState)
    }

    func onDownloadedSongsChanged(_ songs: [DownloadedSong], filterRaw: String) {
        downloadedAlbumNames = Set(songs.compactMap { $0.albumName?.lowercased() })
        let filter = AlbumFilter(rawValue: filterRaw) ?? .all
        if filter == .downloaded { recomputeFilteredAlbums(filterRaw: filterRaw) }
    }

    // MARK: Search

    func onSearchTextChanged(_ text: String, appState: AppState) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
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

    // MARK: Grid geometry

    func updateGridGeometry(containerWidth: CGFloat, minCellWidth: CGFloat) {
        guard containerWidth > 0 else { return }
        let spacing: CGFloat = 16
        let padding: CGFloat = 32
        let available = containerWidth - padding
        let columnCount = floor(max(1, (available + spacing) / (minCellWidth + spacing)))
        let cellWidth = (available - spacing * (columnCount - 1)) / columnCount
        guard abs(cellWidth - gridCellWidth) > 1 else { return }
        gridCellWidth = cellWidth
        gridColumnCount = Int(columnCount)
        gridColumns = [GridItem(.adaptive(minimum: minCellWidth), spacing: spacing)]
        // Rebuild with correct pixel size now that actual cell width is known.
        rebuildPrefetchRequests(client: AppState.shared.subsonicClient)
    }

    // MARK: Pagination

    func triggerLoadIfNeeded(at index: Int, appState: AppState, filterRaw: String) {
        guard localFilteredAlbums == nil, hasMore, !isLoadingPages else { return }
        let threshold = max(cachedFilteredAlbums.count - 30, 0)
        guard index >= threshold else { return }
        pendingPageTarget = max(pendingPageTarget, albums.count + pageSize)
        Task { await loadPages(appState: appState, filterRaw: filterRaw) }
    }

    /// Closure-friendly overload — uses AppState.shared so ForEach cells don't capture the environment object.
    func triggerLoadIfNeeded(at index: Int, filterRaw: String) {
        triggerLoadIfNeeded(at: index, appState: AppState.shared, filterRaw: filterRaw)
    }

    func prefetchImages(around index: Int) {
        guard index >= lastPrefetchIndex + 1 || index < lastPrefetchIndex else { return }
        lastPrefetchIndex = index

        // Near window: high-priority decoded bitmaps — must be ready before cells appear.
        let nearStart = max(0, index - 5)
        let nearEnd = min(index + 60, prefetchRequests.count)
        if nearStart < nearEnd {
            nearPrefetcher.startPrefetching(with: prefetchRequests[nearStart..<nearEnd].compactMap { $0 })
        }

        // Far window: normal-priority lookahead so fast-scrollers don't see grey.
        let farEnd = min(index + 150, prefetchRequests.count)
        if nearEnd < farEnd {
            farPrefetcher.startPrefetching(with: prefetchRequests[nearEnd..<farEnd].compactMap { $0 })
        }
    }

    /// Called from onScrollGeometryChange — computes which album index sits at the leading
    /// edge of the prefetch window (1.5 viewport-heights ahead of the bottom of the visible area).
    func prefetchImagesForScrollOffset(_ offsetY: CGFloat, viewportHeight: CGFloat) {
        guard gridColumnCount > 0, gridCellWidth > 0 else { return }
        // Row height: cell width (square art) + 20pt grid row spacing + 44pt for two label lines.
        let rowHeight = gridCellWidth + 20 + 44
        // Aim 1.5 screen-heights ahead of what's currently visible so images are decoded before arrival.
        let lookAheadY = offsetY + viewportHeight + viewportHeight * 1.5
        let leadingRow = Int(lookAheadY / rowHeight)
        let leadingIndex = leadingRow * gridColumnCount
        prefetchImages(around: min(leadingIndex, max(0, prefetchRequests.count - 1)))
    }

    // MARK: Sort / filter triggers

    func applySortOption(_ option: AlbumSortOption, appState: AppState, filterRaw: String) {
        if option == .year {
            clientSideSort = .year
            activeListType = nil
            recomputeFilteredAlbums(filterRaw: filterRaw)
        } else {
            clientSideSort = nil
            activeListType = option.albumListType
            albums = []
            hasMore = true
            Task { await loadAlbums(appState: appState, filterRaw: filterRaw) }
        }
    }

    func applyGenre(_ genre: String?, appState: AppState, filterRaw: String) {
        activeGenre = genre
        albums = []
        hasMore = true
        Task { await loadAlbums(appState: appState, filterRaw: filterRaw) }
    }

    func refresh(appState: AppState, filterRaw: String) async {
        albums = []
        hasMore = true
        await loadAlbums(appState: appState, filterRaw: filterRaw)
    }

    // MARK: macOS sidebar filter

    #if os(macOS)
    func debouncedApplyLocalFilters(
        appState: AppState,
        modelContext: ModelContext,
        filterRaw: String
    ) {
        filterTask?.cancel()
        filterTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await applyLocalFilters(appState: appState, modelContext: modelContext, filterRaw: filterRaw)
        }
    }

    func applyLocalFilters(
        appState: AppState,
        modelContext: ModelContext,
        filterRaw: String
    ) async {
        let filter = appState.albumFilter
        guard filter.isActive else {
            localFilteredAlbums = nil
            recomputeFilteredAlbums(filterRaw: filterRaw)
            return
        }

        let recentIds = recentlyPlayedIds(for: filter, modelContext: modelContext)
        let artistNames = selectedArtistNames(for: filter, appState: appState, modelContext: modelContext)
        let snapshot = FilterSnapshot(filter: filter)
        let allAlbums: [Album]
        if let cached = appState.libraryCache.albums {
            allAlbums = cached
        } else {
            do {
                var descriptor = FetchDescriptor<CachedAlbum>()
                descriptor.sortBy = [SortDescriptor(\.name)]
                allAlbums = try modelContext.fetch(descriptor).map { $0.toAlbum() }
            } catch {
                logger.error("Failed to fetch albums for filter: \(error)")
                localFilteredAlbums = nil
                return
            }
        }

        let filtered = await Task.detached(priority: .userInitiated) {
            allAlbums.filter {
                AlbumsViewModel.albumMatchesFilter(
                    $0, snapshot: snapshot, recentIds: recentIds, selectedArtistNames: artistNames)
            }
        }.value

        guard !Task.isCancelled else { return }
        localFilteredAlbums = filtered
        recomputeFilteredAlbums(filterRaw: filterRaw)
    }

    private func selectedArtistNames(
        for filter: LibraryFilter,
        appState: AppState,
        modelContext: ModelContext
    ) -> Set<String> {
        guard !filter.selectedArtistIds.isEmpty else { return [] }
        if let cached = appState.libraryCache.artists {
            return Set(cached.compactMap { filter.selectedArtistIds.contains($0.id) ? $0.name : nil })
        }
        let artists = (try? modelContext.fetch(FetchDescriptor<CachedArtist>())) ?? []
        return Set(artists.compactMap { filter.selectedArtistIds.contains($0.id) ? $0.name : nil })
    }

    private func recentlyPlayedIds(for filter: LibraryFilter, modelContext: ModelContext) -> Set<String>? {
        guard filter.isRecentlyPlayed else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<CachedSong>(
            predicate: #Predicate { $0.lastPlayed != nil && $0.lastPlayed! > cutoff }
        )
        return Set((try? modelContext.fetch(descriptor))?.compactMap(\.albumId) ?? [])
    }

    struct FilterSnapshot: Sendable {
        let isFavorited: TriState
        let isRated: TriState
        let selectedArtistIds: Set<String>
        let selectedGenres: Set<String>
        let selectedLabels: Set<String>
        let year: Int?

        @MainActor
        init(filter: LibraryFilter) {
            isFavorited = filter.isFavorited
            isRated = filter.isRated
            selectedArtistIds = filter.selectedArtistIds
            selectedGenres = filter.selectedGenres
            selectedLabels = filter.selectedLabels
            year = filter.year
        }
    }

    nonisolated static func albumMatchesFilter(
        _ album: Album,
        snapshot: FilterSnapshot,
        recentIds: Set<String>?,
        selectedArtistNames: Set<String>
    ) -> Bool {
        guard snapshot.isFavorited.matches(album.starred != nil) else { return false }
        guard snapshot.isRated.matches((album.userRating ?? 0) != 0) else { return false }
        if let recentIds, !recentIds.contains(album.id) { return false }
        if !snapshot.selectedArtistIds.isEmpty {
            let byId = album.artistId.map { snapshot.selectedArtistIds.contains($0) } ?? false
            let byName = album.artist.map { selectedArtistNames.contains($0) } ?? false
            guard byId || byName else { return false }
        }
        if !snapshot.selectedGenres.isEmpty {
            guard !Set(album.allGenres).isDisjoint(with: snapshot.selectedGenres) else { return false }
        }
        if !snapshot.selectedLabels.isEmpty {
            guard let label = album.label, snapshot.selectedLabels.contains(label) else { return false }
        }
        if let yearFilter = snapshot.year {
            guard album.year == yearFilter else { return false }
        }
        return true
    }
    #endif

    // MARK: Private helpers

    /// Instantly populate the grid from disk on cold launch so it's never empty while
    /// waiting for the network. Uses persisted album ID ordering + CachedAlbum rows.
    /// Skipped for .random (stale random is misleading).
    private func seedFromDisk(appState: AppState, modelContext: ModelContext, filterRaw: String) {
        guard effectiveListType != .random else { return }

        // Build an id→Album lookup from CachedAlbum (falls back to libraryCache if ready)
        let lookup: [String: Album]
        if let cached = appState.libraryCache.albums, !cached.isEmpty {
            lookup = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        } else {
            var descriptor = FetchDescriptor<CachedAlbum>()
            descriptor.propertiesToFetch = [\.id, \.name, \.artistName, \.artistId, \.coverArtId, \.year, \.genres, \.isStarred, \.userRating]
            guard let rows = try? modelContext.fetch(descriptor), !rows.isEmpty else { return }
            lookup = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.toAlbum()) })
        }
        guard !lookup.isEmpty else { return }

        let totalKnown = lookup.count

        // For alphabetical sort orders, derive ordering locally without a persisted list.
        if effectiveListType == .alphabeticalByName && genre == nil && fromYear == nil && toYear == nil {
            let seeded = lookup.values.sorted { $0.name < $1.name }
            applySeeded(seeded, filterRaw: filterRaw, client: appState.subsonicClient, fullLibraryCount: totalKnown)
            return
        }
        if effectiveListType == .alphabeticalByArtist && genre == nil && fromYear == nil && toYear == nil {
            let seeded = lookup.values.sorted { ($0.artist ?? "") < ($1.artist ?? "") }
            applySeeded(seeded, filterRaw: filterRaw, client: appState.subsonicClient, fullLibraryCount: totalKnown)
            return
        }

        // For server-ordered sorts, reconstruct ordering from persisted ID list.
        guard let ids = loadPersistedOrder() else { return }
        let seeded = ids.compactMap { lookup[$0] }
        guard !seeded.isEmpty else { return }
        // If the persisted ID list covers the full library, the scroll bar can reflect everything.
        applySeeded(seeded, filterRaw: filterRaw, client: appState.subsonicClient, fullLibraryCount: totalKnown)
    }

    private func applySeeded(_ seeded: [Album], filterRaw: String, client: SubsonicClient, fullLibraryCount: Int? = nil) {
        albums = seeded
        // If we seeded the entire known library, mark hasMore = false so the scroll bar
        // reflects the full length immediately. loadAlbums will correct this if the server
        // returns a full page (meaning there may be more).
        hasMore = fullLibraryCount.map { seeded.count < $0 } ?? true
        isLoading = false
        recomputeFilteredAlbums(filterRaw: filterRaw)
        rebuildPrefetchRequests(client: client)
    }

    private static let orderDefaultsPrefix = "albumOrder_"

    private func persistOrder() {
        let ids = albums.map(\.id)
        guard !ids.isEmpty else { return }
        UserDefaults.standard.set(ids, forKey: Self.orderDefaultsPrefix + cacheKey)
    }

    private func loadPersistedOrder() -> [String]? {
        UserDefaults.standard.array(forKey: Self.orderDefaultsPrefix + cacheKey) as? [String]
    }

    private func loadFavoritedAlbumIds(appState: AppState) async {
        guard favoritedAlbumIds.isEmpty else { return }
        if let starred = try? await appState.subsonicClient.getStarred(),
           let albums = starred.album {
            favoritedAlbumIds = Set(albums.map(\.id))
        }
    }

    func loadAlbums(appState: AppState, filterRaw: String) async {
        pendingPageTarget = 0
        let client = appState.subsonicClient
        let sortType = effectiveListType
        let endpoint = SubsonicEndpoint.getAlbumList2(
            type: sortType, size: pageSize, offset: 0,
            fromYear: fromYear, toYear: toYear, genre: effectiveGenre)
        if albums.isEmpty,
           let cached = await client.cachedResponse(for: endpoint, ttl: 600) {
            albums = cached.albumList2?.album ?? []
        }
        isLoading = albums.isEmpty
        error = nil
        defer { isLoading = false }
        do {
            let result = try await client.getAlbumList(
                type: sortType, size: pageSize, offset: 0,
                genre: effectiveGenre, fromYear: fromYear, toYear: toYear)
            albums = result
            hasMore = result.count >= pageSize
            recomputeFilteredAlbums(filterRaw: filterRaw)
            rebuildPrefetchRequests(client: client)
            saveSnapshot(appState: appState)
        } catch {
            if albums.isEmpty {
                self.error = ErrorPresenter.userMessage(for: error)
            }
        }
    }

    private func loadPages(appState: AppState, filterRaw: String) async {
        guard !isLoadingPages, hasMore else { return }
        isLoadingPages = true
        defer {
            isLoadingPages = false
            if albums.count < pendingPageTarget, hasMore {
                Task { await loadPages(appState: appState, filterRaw: filterRaw) }
            }
        }
        let client = appState.subsonicClient
        while albums.count < pendingPageTarget, hasMore, !Task.isCancelled {
            do {
                let result = try await client.getAlbumList(
                    type: effectiveListType, size: pageSize, offset: albums.count,
                    genre: effectiveGenre, fromYear: fromYear, toYear: toYear)
                let more = result.count >= pageSize
                albums.append(contentsOf: result)
                hasMore = more
                recomputeFilteredAlbums(filterRaw: filterRaw)
                rebuildPrefetchRequests(client: client)
            } catch {
                hasMore = false
                break
            }
        }
        saveSnapshot(appState: appState)
    }

    func recomputeFilteredAlbums(filterRaw: String) {
        let filter = AlbumFilter(rawValue: filterRaw) ?? .all
        let source = localFilteredAlbums ?? albums
        guard filter != .all || clientSideSort == .year else {
            if cachedFilteredAlbums.count != source.count ||
               zip(cachedFilteredAlbums, source).contains(where: { $0.id != $1.id }) {
                cachedFilteredAlbums = source
                indexedAlbums = Array(source.enumerated())
            }
            return
        }
        let computed = computeFiltered(source: source, filter: filter)
        if computed.count != cachedFilteredAlbums.count ||
           zip(computed, cachedFilteredAlbums).contains(where: { $0.id != $1.id }) {
            cachedFilteredAlbums = computed
            indexedAlbums = Array(computed.enumerated())
        }
    }

    private func computeFiltered(source: [Album], filter: AlbumFilter) -> [Album] {
        var result = source
        switch filter {
        case .all: break
        case .favorites: result = result.filter { favoritedAlbumIds.contains($0.id) }
        case .downloaded: result = result.filter { downloadedAlbumNames.contains($0.name.lowercased()) }
        }
        if clientSideSort == .year {
            result.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        }
        return result
    }

    func rebuildPrefetchRequests(client: SubsonicClient) {
        prefetchRequests = cachedFilteredAlbums.map { album in
            album.coverArt.map {
                makeGridImageRequest(
                    url: client.coverArtURL(id: $0, size: CoverArtSize.gridThumb),
                    cacheKey: client.coverArtCacheKey(id: $0, size: CoverArtSize.gridThumb)
                )
            }
        }
        blurRequests = cachedFilteredAlbums.map { album in
            album.coverArt.map {
                var req = ImageRequest(url: client.coverArtURL(id: $0, size: CoverArtSize.blur))
                req.userInfo[.imageIdKey] = client.coverArtCacheKey(id: $0, size: CoverArtSize.blur)
                return req
            }
        }
        // Warm full-res into disk cache so cells get a fast hit on first appearance.
        bulkPrefetcher.startPrefetching(with: prefetchRequests.compactMap { $0 })
        // Warm blur thumbnails into memory — they're ~1 KB each so the whole library fits easily.
        thumbPrefetcher.startPrefetching(with: blurRequests.compactMap { $0 })
    }

    private func makeGridImageRequest(url: URL, cacheKey: String? = nil) -> ImageRequest {
        #if os(macOS)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        #else
        let scale = UIScreen.main.scale
        #endif
        let side = gridCellWidth * scale
        let pixelSize = CGSize(width: side, height: side)
        var request = ImageRequest(
            url: url,
            processors: [ImageProcessors.Resize(size: pixelSize, contentMode: .aspectFill, crop: true)]
        )
        if let cacheKey { request.userInfo[.imageIdKey] = cacheKey }
        return request
    }

    private func saveSnapshot(appState: AppState) {
        appState.albumsViewSnapshots[cacheKey] = AppState.AlbumsViewSnapshot(
            albums: albums, hasMore: hasMore, scrollIndex: nil)
        let limit = 10
        if appState.albumsViewSnapshots.count > limit {
            let excess = appState.albumsViewSnapshots.count - limit
            appState.albumsViewSnapshots.keys.prefix(excess).forEach {
                appState.albumsViewSnapshots.removeValue(forKey: $0)
            }
        }
        persistOrder()
    }
}
