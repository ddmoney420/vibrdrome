import NukeUI
import SwiftUI
import SwiftData
import os.log

struct SongsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var songs: [Song] = []
    @State private var titleSongCount: Int?
    @State private var localFilteredSongs: [Song]?
    @State private var filterTask: Task<Void, Never>?
    @State private var isLoading = true
    @State private var hasMore = false
    @State private var searchText = ""
    @State private var searchIsActive = false
    @State private var searchResults: [Song] = []
    @State private var isSearching = false
    @State private var availableGenres: [String] = []
    @State private var filterYear: Int?
    @State private var filterGenre: String?
    @State private var filterArtist: String?
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private var showAlbumArtInLists: Bool = true
    @AppStorage("songsViewStyle") private var showAsList = true
    @State private var sortBy: SongSortOption = .title
    #if os(macOS)
    @State private var columnSettings = TrackTableColumnSettings(viewKey: "songs")
    #endif
    @State private var cachedDisplayedSongs: [Song] = []
    @State private var scrollLoadTask: Task<Void, Never>?
    @State private var pendingPageTarget: Int = 0

    private let pageSize = 500

    enum SongSortOption: String, CaseIterable {
        case title, artist, album, year, recentlyAdded, duration
        var label: String {
            switch self {
            case .title: "Title"
            case .artist: "Artist"
            case .album: "Album"
            case .year: "Year"
            case .recentlyAdded: "Recently Added"
            case .duration: "Duration"
            }
        }
    }

    private var availableYears: [Int] {
        Array(Set(songs.compactMap(\.year))).sorted(by: >)
    }

    private var availableArtists: [String] {
        Array(Set(songs.compactMap(\.artist))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var hasActiveFilters: Bool {
        filterYear != nil || filterGenre != nil || filterArtist != nil
    }

    private func computeDisplayedSongs() -> [Song] {
        var base: [Song]
        #if os(macOS)
        base = localFilteredSongs ?? (searchText.count >= 2 ? searchResults : songs)
        #else
        base = searchText.count >= 2 ? searchResults : songs
        #endif
        if let filterYear {
            base = base.filter { $0.year == filterYear }
        }
        if let filterGenre {
            base = base.filter { $0.genre?.localizedCaseInsensitiveCompare(filterGenre) == .orderedSame }
        }
        if let filterArtist {
            base = base.filter { $0.artist?.localizedCaseInsensitiveCompare(filterArtist) == .orderedSame }
        }
        switch sortBy {
        case .title: return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist: return base.sorted { ($0.artist ?? "").localizedCaseInsensitiveCompare($1.artist ?? "") == .orderedAscending }
        case .album: return base.sorted { lhs, rhs in
            let cmp = (lhs.album ?? "").localizedCaseInsensitiveCompare(rhs.album ?? "")
            if cmp != .orderedSame { return cmp == .orderedAscending }
            if (lhs.discNumber ?? 0) != (rhs.discNumber ?? 0) {
                return (lhs.discNumber ?? 0) < (rhs.discNumber ?? 0)
            }
            return (lhs.track ?? 0) < (rhs.track ?? 0)
        }
        case .year: return base.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .recentlyAdded: return base.sorted { ($0.created ?? "") > ($1.created ?? "") }
        case .duration: return base.sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
        }
    }

    var body: some View {
        decoratedView
    }

    private var decoratedView: some View {
        toolbarView
        .task { await initialLoad() }
        .onChange(of: sortBy) { recomputeDisplayedSongs() }
        .onChange(of: filterYear) { recomputeDisplayedSongs() }
        .onChange(of: filterGenre) { recomputeDisplayedSongs() }
        .onChange(of: filterArtist) { recomputeDisplayedSongs() }
        .onChange(of: appState.libraryCache.generation) { _, _ in
            refreshTitleSongCount()
        }
        #if os(macOS)
        .onChange(of: appState.libraryCache.generation) { _, _ in
            if appState.songFilter.isActive { debouncedApplyLocalFilters() }
        }
        .onChange(of: appState.songFilter.isFavorited) { debouncedApplyLocalFilters() }
        .onChange(of: appState.songFilter.isRated) { debouncedApplyLocalFilters() }
        .onChange(of: appState.songFilter.isRecentlyPlayed) { debouncedApplyLocalFilters() }
        .onChange(of: appState.songFilter.selectedArtistIds) { debouncedApplyLocalFilters() }
        .onChange(of: appState.songFilter.selectedGenres) { debouncedApplyLocalFilters() }
        .onChange(of: appState.songFilter.year) { debouncedApplyLocalFilters() }
        .onChange(of: appState.songFilter.ruleSet) { debouncedApplyLocalFilters() }
        .onAppear { appState.activeFilterWindowContext = .song }
        #endif
    }

    private var toolbarView: some View {
        contentView
        .navigationTitle(navigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search songs")
        #else
        .searchable(text: $searchText, isPresented: $searchIsActive, prompt: "Search songs")
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchBar)) { _ in
            searchIsActive = false
            DispatchQueue.main.async { searchIsActive = true }
        }
        .onChange(of: searchText) { _, query in
            guard query.count >= 2 else {
                searchResults = []
                recomputeDisplayedSongs()
                return
            }
            isSearching = true
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, searchText == query else { return }
                do {
                    let result = try await appState.subsonicClient.search(
                        query: query, artistCount: 0, albumCount: 0, songCount: 50)
                    searchResults = result.song ?? []
                    recomputeDisplayedSongs()
                } catch {}
                isSearching = false
            }
        }
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if appState.activeSidePanel == .songFilters {
                            appState.activeSidePanel = nil
                        } else {
                            appState.activeSidePanel = .songFilters
                        }
                    }
                } label: {
                    Image(systemName: appState.songFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Song Filters")
                .accessibilityIdentifier("songFilterToggle")
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
                .accessibilityIdentifier("songsViewToggle")
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Section("Year") {
                        Button {
                            filterYear = nil
                        } label: {
                            HStack {
                                Text("Any Year")
                                if filterYear == nil { Image(systemName: "checkmark") }
                            }
                        }
                        ForEach(availableYears, id: \.self) { year in
                            Button {
                                filterYear = year
                            } label: {
                                HStack {
                                    Text(verbatim: "\(year)")
                                    if filterYear == year { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                    Section("Genre") {
                        Button {
                            filterGenre = nil
                        } label: {
                            HStack {
                                Text("Any Genre")
                                if filterGenre == nil { Image(systemName: "checkmark") }
                            }
                        }
                        ForEach(availableGenres, id: \.self) { genre in
                            Button {
                                filterGenre = genre
                            } label: {
                                HStack {
                                    Text(genre.cleanedGenreDisplay)
                                    if filterGenre == genre { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                    Section("Artist") {
                        Button {
                            filterArtist = nil
                        } label: {
                            HStack {
                                Text("Any Artist")
                                if filterArtist == nil { Image(systemName: "checkmark") }
                            }
                        }
                        ForEach(availableArtists, id: \.self) { artist in
                            Button {
                                filterArtist = artist
                            } label: {
                                HStack {
                                    Text(artist)
                                    if filterArtist == artist { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: hasActiveFilters
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter Songs")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(SongSortOption.allCases, id: \.self) { option in
                        Button {
                            sortBy = option
                        } label: {
                            HStack {
                                Text(option.label)
                                if sortBy == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        Task { await loadSongs() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
    }

    private var contentView: some View {
        Group {
            if showAsList {
                songList
            } else {
                songGrid
            }
        }
    }

    // MARK: - Active Filter Chips

    private var activeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let filterYear {
                    filterChip(label: "\(filterYear)") { self.filterYear = nil }
                }
                if let filterGenre {
                    filterChip(label: filterGenre) { self.filterGenre = nil }
                }
                if let filterArtist {
                    filterChip(label: filterArtist) { self.filterArtist = nil }
                }
                if hasActiveFilters {
                    Button {
                        filterYear = nil
                        filterGenre = nil
                        filterArtist = nil
                    } label: {
                        Text("Clear all")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func filterChip(label: String, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .lineLimit(1)
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func songRow(_ song: Song) -> some View {
        HStack(spacing: 12) {
            if showAlbumArtInLists {
                AlbumArtView(coverArtId: song.coverArt, size: 40, cornerRadius: 4)
            }
            songRowTitleBlock(song)
            Spacer()
            songRowMetaBlock(song)
        }
    }

    @ViewBuilder
    private func songRowTitleBlock(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(song.title)
                .font(.body)
                .lineLimit(1)

            HStack(spacing: 4) {
                if let artist = song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let album = song.album {
                    Text("· \(album)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func songRowMetaBlock(_ song: Song) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let duration = song.duration {
                Text(formatDuration(TimeInterval(duration)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                if let suffix = song.suffix {
                    Text(suffix.uppercased())
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                if let bitRate = song.bitRate {
                    Text("\(bitRate)k")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var navigationTitle: String {
        titleSongCount.map { "Songs (\($0))" } ?? "Songs"
    }

    // MARK: - List view

    private var songList: some View {
        #if os(macOS)
        MacTrackTableView(songs: cachedDisplayedSongs, settings: columnSettings)
        #else
        List {
            if hasActiveFilters {
                activeFilterChips
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if !cachedDisplayedSongs.isEmpty {
                playShuffleBar
                    .listRowSeparator(.hidden)
            }

            ForEach(0..<totalItemCount, id: \.self) { index in
                Group {
                    if index < cachedDisplayedSongs.count {
                        let song = cachedDisplayedSongs[index]
                        songRow(song)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                AudioEngine.shared.play(song: song, from: cachedDisplayedSongs, at: index)
                            }
                            .accessibilityIdentifier("songRow_\(song.id)")
                            .trackContextMenu(song: song)
                    } else {
                        songListPlaceholder
                    }
                }
                .onAppear { triggerLoadIfNeeded(at: index) }
            }
        }
        #endif
    }

    // MARK: - Grid view

    private var songGrid: some View {
        ScrollView {
            VStack(spacing: 12) {
                if hasActiveFilters {
                    activeFilterChips
                        .padding(.horizontal, 16)
                }

                if !cachedDisplayedSongs.isEmpty {
                    playShuffleBar
                        .padding(.horizontal, 16)
                }

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
                ], spacing: 20) {
                    ForEach(0..<totalItemCount, id: \.self) { index in
                        Group {
                            if index < cachedDisplayedSongs.count {
                                let song = cachedDisplayedSongs[index]
                                songCard(song)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        AudioEngine.shared.play(song: song, from: cachedDisplayedSongs, at: index)
                                    }
                                    .accessibilityIdentifier("songCard_\(song.id)")
                                    .trackContextMenu(song: song)
                            } else {
                                songGridPlaceholder
                            }
                        }
                        .onAppear { triggerLoadIfNeeded(at: index) }
                    }
                }
                .padding(16)
            }
        }
    }

    private var playShuffleBar: some View {
        HStack(spacing: 12) {
            Button {
                let songs = cachedDisplayedSongs
                AudioEngine.shared.play(song: songs[0], from: songs, at: 0)
            } label: {
                Label("Play All", systemImage: "play.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .accessibilityIdentifier("songsPlayAllButton")

            Button {
                let shuffled = cachedDisplayedSongs.shuffled()
                AudioEngine.shared.play(song: shuffled[0], from: shuffled, at: 0)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .accessibilityIdentifier("songsShuffleButton")
        }
    }

    private func songCard(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                AlbumArtView(coverArtId: song.coverArt, size: geo.size.width, cornerRadius: 10)
            }
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(song.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            if let artist = song.artist {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func initialLoad() async {
        await loadSongs()
        await loadGenres()
        refreshTitleSongCount()
        #if os(macOS)
        applyLocalFilters()
        #endif
        recomputeDisplayedSongs()
    }

    private func loadGenres() async {
        guard availableGenres.isEmpty else { return }
        do {
            let result = try await appState.subsonicClient.getGenres()
            availableGenres = result
                .map(\.value)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } catch {}
    }

    private func loadSongs() async {
        scrollLoadTask?.cancel()
        pendingPageTarget = 0
        isLoading = true
        songs = []
        defer { isLoading = false }
        do {
            let result = try await appState.subsonicClient.search(
                query: "", artistCount: 0, albumCount: 0, songCount: pageSize
            )
            songs = result.song ?? []
            hasMore = (result.song?.count ?? 0) >= pageSize
            refreshTitleSongCount()
            recomputeDisplayedSongs()
        } catch {}
    }

    private func loadPages() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        // Accumulate into local array to avoid multiple @State updates triggering re-renders
        var accumulated = songs
        var stillHasMore = hasMore
        while accumulated.count < pendingPageTarget, stillHasMore, !Task.isCancelled {
            do {
                let result = try await appState.subsonicClient.search(
                    query: "", artistCount: 0, albumCount: 0,
                    songCount: pageSize, songOffset: accumulated.count
                )
                let newSongs = result.song ?? []
                accumulated.append(contentsOf: newSongs)
                stillHasMore = newSongs.count >= pageSize
            } catch {
                stillHasMore = false
                break
            }
        }
        // Single state update instead of one per page
        songs = accumulated
        hasMore = stillHasMore
        isLoading = false
        recomputeDisplayedSongs()
        refreshTitleSongCount()
        if songs.count < pendingPageTarget, hasMore {
            scrollLoadTask?.cancel()
            scrollLoadTask = Task { await loadPages() }
        }
    }

    private func refreshTitleSongCount() {
        if let cachedSongs = appState.libraryCache.songs, !cachedSongs.isEmpty {
            titleSongCount = cachedSongs.count
            return
        }

        let descriptor = FetchDescriptor<CachedSong>()
        if let cachedCount = try? modelContext.fetchCount(descriptor), cachedCount > 0 {
            titleSongCount = cachedCount
            return
        }

        titleSongCount = songs.isEmpty ? nil : songs.count
    }

    private var songListPlaceholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                    .frame(width: 140, height: 14)
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                    .frame(width: 100, height: 12)
            }
            Spacer()
        }
    }

    private var songGridPlaceholder: some View {
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
        guard localFilteredSongs == nil, searchText.isEmpty else { return cachedDisplayedSongs.count }
        guard hasMore, let totalCount = appState.libraryCache.songs?.count else { return cachedDisplayedSongs.count }
        return max(songs.count, totalCount)
    }

    private func triggerLoadIfNeeded(at index: Int) {
        guard localFilteredSongs == nil, searchText.isEmpty, hasMore else { return }
        if index >= songs.count {
            // Scrolled into placeholder territory — always update target, debounce the load
            pendingPageTarget = max(pendingPageTarget, songs.count + (index - songs.count) + pageSize)
            scrollLoadTask?.cancel()
            scrollLoadTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await loadPages()
            }
        } else if !isLoading {
            // Near end of loaded items — prefetch immediately
            let prefetchThreshold = max(songs.count - 10, 0)
            if index >= prefetchThreshold {
                pendingPageTarget = max(pendingPageTarget, songs.count + pageSize)
                Task { await loadPages() }
            }
        }
    }

    private func recomputeDisplayedSongs() {
        cachedDisplayedSongs = computeDisplayedSongs()
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
        let filter = appState.songFilter
        guard filter.isActive else {
            localFilteredSongs = nil
            appState.songFilter.matchCount = nil
            recomputeDisplayedSongs()
            return
        }

        do {
            let allSongs: [Song]
            if let cachedSongs = appState.libraryCache.songs {
                allSongs = cachedSongs
            } else {
                var descriptor = FetchDescriptor<CachedSong>()
                descriptor.sortBy = [SortDescriptor(\.title)]
                allSongs = try modelContext.fetch(descriptor).map { $0.toSong() }
            }

            let recentSongIds = recentlyPlayedSongIds(for: filter)
            localFilteredSongs = allSongs.filter { songMatchesFilter($0, filter: filter, recentIds: recentSongIds) }
            appState.songFilter.matchCount = localFilteredSongs?.count
            recomputeDisplayedSongs()
        } catch {
            Logger(subsystem: "com.vibrdrome.app", category: "Songs")
                .error("Failed to apply local filters: \(error)")
            localFilteredSongs = nil
        }
    }

    private func recentlyPlayedSongIds(for filter: LibraryFilter) -> Set<String>? {
        guard filter.isRecentlyPlayed else { return nil }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<CachedSong>(
            predicate: #Predicate { $0.lastPlayed != nil && $0.lastPlayed! > cutoff }
        )
        let recentSongs = (try? modelContext.fetch(descriptor)) ?? []
        return Set(recentSongs.map(\.id))
    }

    private func songMatchesFilter(
        _ song: Song, filter: LibraryFilter, recentIds: Set<String>?
    ) -> Bool {
        guard filter.isFavorited.matches(song.starred != nil) else { return false }
        guard filter.isRated.matches((song.userRating ?? 0) != 0) else { return false }
        if let recentIds, !recentIds.contains(song.id) { return false }
        if !filter.selectedArtistIds.isEmpty {
            guard let artistId = song.artistId, filter.selectedArtistIds.contains(artistId) else {
                return false
            }
        }
        if !filter.selectedGenres.isEmpty {
            guard let genre = song.genre, filter.selectedGenres.contains(genre) else {
                return false
            }
        }
        if let yearFilter = filter.year {
            guard song.year == yearFilter else { return false }
        }
        if !filter.ruleSet.isEmpty {
            let meta = FilterRuleSet.SongMeta(
                title: song.title,
                artist: song.artist,
                albumTitle: song.album,
                genre: song.genre,
                suffix: song.suffix,
                contentType: song.contentType,
                year: song.year,
                duration: song.duration,
                bitRate: song.bitRate,
                playCount: 0,
                rating: song.userRating ?? 0,
                trackNumber: song.track,
                discNumber: song.discNumber,
                isFavorited: song.starred != nil,
                isDownloaded: false
            )
            guard filter.ruleSet.matches(song: meta) else { return false }
        }
        return true
    }
    #endif
}
