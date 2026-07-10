import SwiftData
import SwiftUI

private let recentSearchesKey = "recentSearches"
private let maxRecentSearches = 10

struct SearchView: View {
    @Environment(AppState.self) var appState
    @Environment(\.modelContext) var modelContext
    @State private var query = ""
    @State private var results: SearchResult3?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var recentSearches: [String] = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private var showAlbumArtInLists: Bool = true

    // MARK: - Filter State (internal for SearchView+Filters extension)
    @State var selectedYear: Int?
    @State var selectedFormat: String?
    @State var showYearPicker = false
    @State var showFormatPicker = false
    @State var selectedScope: SearchScope = .all
    @State private var searchIsActive = false

    let formatOptions = ["FLAC", "MP3", "AAC", "OGG", "OPUS", "WAV"]

    /// Search result type filter (#85 Slice 2). `.all` keeps the 3-section layout; a specific scope
    /// narrows both the fetched result counts and the displayed sections.
    enum SearchScope: String, CaseIterable, Identifiable {
        case all, artists, albums, songs
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .artists: return "Artists"
            case .albums: return "Albums"
            case .songs: return "Songs"
            }
        }
    }

    var hasActiveFilters: Bool {
        selectedYear != nil || selectedFormat != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // #85 Slice 2: type scope + refiners pinned above the scrolling results, and shown as
            // soon as search is active so filters are available up front (not gated on results).
            if searchIsActive || results != nil || hasActiveFilters {
                scopePicker
                filterBar
            }
            ScrollView {
                if let results {
                    resultsContent(applyFilters(to: results))
                } else if let searchError, !query.isEmpty {
                    errorContent(searchError)
                } else if query.isEmpty {
                    emptyContent
                }
            }
            #if os(iOS)
            .padding(.bottom, 80)
            #endif
        }
        .navigationTitle("Search")
        .searchable(text: $query, isPresented: $searchIsActive, prompt: "Artists, albums, songs...")
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                searchIsActive = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchBar)) { _ in
            searchIsActive = false
            DispatchQueue.main.async { searchIsActive = true }
        }
        .onSubmit(of: .search) {
            saveRecentSearch(query)
        }
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()

            guard newValue.count >= 2 else {
                results = nil
                return
            }

            searchTask = Task {
                await performSearch(newValue)
            }
        }
        .onChange(of: selectedScope) { _, _ in
            // #85 Slice 2: re-run the search with type-tailored fetch counts when the scope changes.
            guard query.count >= 2 else { return }
            searchTask?.cancel()
            searchTask = Task {
                await performSearch(query)
            }
        }
        .overlay {
            if isSearching {
                ProgressView()
            }
        }
    }

    // MARK: - Results

    private func resultsContent(_ results: SearchResult3) -> some View {
        let artists = results.artist ?? []
        let albums = results.album ?? []
        let songs = results.song ?? []

        return VStack(spacing: 24) {
            if artists.isEmpty && albums.isEmpty && songs.isEmpty {
                ContentUnavailableView.search(text: query)
            }

            if showsScope(.artists), !artists.isEmpty { artistsSection(artists) }
            if showsScope(.albums), !albums.isEmpty { albumsSection(albums) }
            if showsScope(.songs), !songs.isEmpty { songsSection(songs) }
        }
        .padding(.top, 8)
    }

    /// #85 Slice 2: which sections to display for the current scope (`.all` shows every section).
    private func showsScope(_ scope: SearchScope) -> Bool {
        selectedScope == .all || selectedScope == scope
    }

    @ViewBuilder
    private func artistsSection(_ artists: [Artist]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Artists (\(artists.count))")
                .font(.title3).bold()
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(artists) { artist in
                        NavigationLink {
                            ArtistDetailView(artistId: artist.id)
                        } label: {
                            artistBubble(artist)
                        }
                        .buttonStyle(.plain)
                        .artistGetInfoContextMenu(artist: artist)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func albumsSection(_ albums: [Album]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Albums (\(albums.count))")
                .font(.title3).bold()
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(albumId: album.id)
                        } label: {
                            albumTile(album)
                        }
                        .buttonStyle(.plain)
                        .albumGetInfoContextMenu(album: album)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func songsSection(_ songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Songs (\(songs.count))")
                .font(.title3).bold()
                .padding(.horizontal, 16)

            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    songRow(song: song, songs: songs, index: index)
                    if index < songs.count - 1 {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Artist Bubble

    private func artistBubble(_ artist: Artist) -> some View {
        VStack(spacing: 8) {
            AlbumArtView(coverArtId: artist.coverArt, size: Theme.artistBubbleSize, cornerRadius: Theme.artistBubbleSize / 2)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            Text(artist.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: Theme.artistBubbleSize + 8)
    }

    // MARK: - Album Tile

    private func albumTile(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AlbumArtView(coverArtId: album.coverArt, size: Theme.searchAlbumTileSize, cornerRadius: 10)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(album.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(album.artist ?? "")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: Theme.searchAlbumTileSize)
    }

    // MARK: - Song Row (with album art)

    private func songRow(song: Song, songs: [Song], index: Int) -> some View {
        HStack(spacing: 12) {
            if showAlbumArtInLists {
                AlbumArtView(coverArtId: song.coverArt, size: 48, cornerRadius: 8)
            }
            songRowTitleBlock(song)

            Spacer()

            if song.starred != nil {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
                    .accessibilityLabel("Favorited")
            }

            if let duration = song.duration {
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            #if os(iOS)
            Haptics.light()
            #endif
            AudioEngine.shared.play(song: song, from: songs, at: index)
        }
        .trackContextMenu(song: song, queue: songs, index: index)
    }

    @ViewBuilder
    private func songRowTitleBlock(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(song.title)
                .font(.body)
                .lineLimit(1)

            HStack(spacing: 4) {
                if let artist = song.displayArtist {
                    Text(artist)
                }
                if let album = song.album {
                    Text("·")
                    Text(album)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    // MARK: - Empty & Error States

    @ViewBuilder
    private var emptyContent: some View {
        if recentSearches.isEmpty {
            ContentUnavailableView {
                Label("Search", systemImage: "magnifyingglass")
            } description: {
                Text("Search for artists, albums, and songs")
            }
            .padding(.top, 100)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recent")
                        .font(.headline)
                    Spacer()
                    Button("Clear") {
                        withAnimation { clearRecentSearches() }
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                    .accessibilityIdentifier("clearRecentButton")
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                ForEach(recentSearches, id: \.self) { recent in
                    Button {
                        query = recent
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text(recent)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func errorContent(_ error: String) -> some View {
        ContentUnavailableView {
            Label("Search Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Retry") {
                let q = query
                let counts = scopeCounts()
                searchTask?.cancel()
                searchTask = Task {
                    isSearching = true
                    defer { isSearching = false }
                    do {
                        let searchResults = try await appState.subsonicClient.search(
                            query: q, artistCount: counts.artist,
                            albumCount: counts.album, songCount: counts.song)
                        guard !Task.isCancelled else { return }
                        self.searchError = nil
                        results = rankedResults(searchResults, query: q)
                    } catch {
                        guard !Task.isCancelled else { return }
                        self.searchError = ErrorPresenter.userMessage(for: error)
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 100)
    }

    // MARK: - Search Logic

    /// #85 Slice 2: bias the search3 result counts toward the selected type so a scope tailors the
    /// fetch (more of that type) rather than just hiding sections.
    private func scopeCounts() -> (artist: Int, album: Int, song: Int) {
        switch selectedScope {
        case .all: return (20, 20, 40)
        case .artists: return (60, 0, 0)
        case .albums: return (0, 60, 0)
        case .songs: return (0, 0, 80)
        }
    }

    private func performSearch(_ query: String) async {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let counts = scopeCounts()

        // Show local results instantly while waiting for network
        let localResults = searchLocally(query: query)
        if let localResults, resultCount(localResults) > 0, results == nil {
            results = rankedResults(localResults, query: query)
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let variants = fuzzyVariants(of: query)

            // If we have fuzzy variants, search them first (more specific)
            // then merge with the original query results
            var searchResults: SearchResult3
            if !variants.isEmpty {
                // Search the dotted/specific variant first
                searchResults = try await appState.subsonicClient.search(
                    query: variants[0], artistCount: counts.artist,
                    albumCount: counts.album, songCount: counts.song)
                guard !Task.isCancelled else { return }

                // Try remaining variants if still few results
                for variant in variants.dropFirst() {
                    guard !Task.isCancelled else { return }
                    if resultCount(searchResults) >= 3 { break }
                    let extra = try await appState.subsonicClient.search(
                        query: variant, artistCount: counts.artist,
                        albumCount: counts.album, songCount: counts.song)
                    searchResults = mergeResults(searchResults, extra)
                }

                // Merge with original query results (adds broader matches)
                let original = try await appState.subsonicClient.search(
                    query: query, artistCount: counts.artist,
                    albumCount: counts.album, songCount: counts.song)
                guard !Task.isCancelled else { return }
                searchResults = mergeResults(searchResults, original)
            } else {
                searchResults = try await appState.subsonicClient.search(
                    query: query, artistCount: counts.artist,
                    albumCount: counts.album, songCount: counts.song)
                guard !Task.isCancelled else { return }
            }

            searchError = nil
            let ranked = rankedResults(searchResults, query: query)
            results = ranked
            // #85 Slice 3: augment thin results with typo-tolerant local Artist/Album matches.
            let fuzzed = await fuzzyAugmented(ranked, query: query)
            guard !Task.isCancelled else { return }
            results = fuzzed
        } catch {
            guard !Task.isCancelled else { return }
            // Offline fallback: search cached library locally, then augment with fuzzy (#85 Slice 3)
            // — which can surface typo matches even when the substring search found nothing.
            let offlineResults = searchLocally(query: query)
                ?? searchDownloadsLocally(query: query).map {
                    SearchResult3(artist: nil, album: nil, song: $0)
                }
            let base = offlineResults.map { rankedResults($0, query: query) }
                ?? SearchResult3(artist: nil, album: nil, song: nil)
            let fuzzed = await fuzzyAugmented(base, query: query)
            guard !Task.isCancelled else { return }
            if resultCount(fuzzed) > 0 {
                searchError = nil
                results = fuzzed
            } else {
                searchError = ErrorPresenter.userMessage(for: error)
                results = nil
            }
        }
    }

    private func searchLocally(query: String) -> SearchResult3? {
        let q = query

        // Search cached songs using predicate
        var songDescriptor = FetchDescriptor<CachedSong>(
            predicate: #Predicate<CachedSong> {
                $0.title.localizedStandardContains(q)
                || ($0.artist?.localizedStandardContains(q) ?? false)
                || ($0.albumName?.localizedStandardContains(q) ?? false)
            }
        )
        songDescriptor.fetchLimit = 40
        let matchedSongs = ((try? modelContext.fetch(songDescriptor)) ?? []).map { $0.toSong() }

        // Search cached albums using predicate
        var albumDescriptor = FetchDescriptor<CachedAlbum>(
            predicate: #Predicate<CachedAlbum> {
                $0.name.localizedStandardContains(q)
                || ($0.artistName?.localizedStandardContains(q) ?? false)
            }
        )
        albumDescriptor.fetchLimit = 20
        let matchedAlbums = ((try? modelContext.fetch(albumDescriptor)) ?? []).map { $0.toAlbum() }

        // Search cached artists using predicate
        var artistDescriptor = FetchDescriptor<CachedArtist>(
            predicate: #Predicate<CachedArtist> {
                $0.name.localizedStandardContains(q)
            }
        )
        artistDescriptor.fetchLimit = 20
        let matchedArtists = ((try? modelContext.fetch(artistDescriptor)) ?? []).map { $0.toArtist() }

        guard !matchedSongs.isEmpty || !matchedAlbums.isEmpty || !matchedArtists.isEmpty else {
            return nil
        }

        return SearchResult3(
            artist: matchedArtists.isEmpty ? nil : Array(matchedArtists),
            album: matchedAlbums.isEmpty ? nil : Array(matchedAlbums),
            song: matchedSongs.isEmpty ? nil : Array(matchedSongs)
        )
    }

    private func searchDownloadsLocally(query: String) -> [Song]? {
        let lowered = query.lowercased()
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.isComplete == true }
        )
        guard let downloads = try? modelContext.fetch(descriptor) else { return nil }
        let matched = downloads.filter {
            $0.songTitle.localizedCaseInsensitiveContains(lowered)
                || ($0.artistName?.localizedCaseInsensitiveContains(lowered) ?? false)
                || ($0.albumName?.localizedCaseInsensitiveContains(lowered) ?? false)
        }
        guard !matched.isEmpty else { return nil }
        return matched.map { $0.toSong() }
    }

    private func saveRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        var recents = recentSearches
        recents.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recents.insert(trimmed, at: 0)
        if recents.count > maxRecentSearches { recents = Array(recents.prefix(maxRecentSearches)) }
        recentSearches = recents
        UserDefaults.standard.set(recents, forKey: recentSearchesKey)
    }

    private func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: recentSearchesKey)
    }

    private func resultCount(_ r: SearchResult3) -> Int {
        (r.artist?.count ?? 0) + (r.album?.count ?? 0) + (r.song?.count ?? 0)
    }

    // MARK: - Fuzzy Search Helpers

    /// Generate fuzzy search variants for acronym-style queries
    /// Returns multiple variants to try (e.g. "REM" → ["R.E.M.", "R.E.M", "R E M"])
    private func fuzzyVariants(of query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var variants = [String]()

        // If query is all letters with no spaces/dots (likely an acronym), try dotted versions
        let lettersOnly = trimmed.filter(\.isLetter)
        if lettersOnly.count == trimmed.count && trimmed.count >= 2 && trimmed.count <= 6 {
            let upper = trimmed.uppercased()
            // R.E.M.
            variants.append(upper.map { String($0) }.joined(separator: ".") + ".")
            // R.E.M (no trailing dot)
            variants.append(upper.map { String($0) }.joined(separator: "."))
        }

        // If query contains dots/punctuation, try without them
        let stripped = trimmed.filter { $0.isLetter || $0.isNumber }
        if stripped != trimmed && stripped.count >= 2 {
            variants.append(stripped)
        }

        return variants.filter { $0 != trimmed }
    }

    /// Merge two search results, deduplicating by ID
    private func mergeResults(_ a: SearchResult3, _ b: SearchResult3) -> SearchResult3 {
        let artists = dedup((a.artist ?? []) + (b.artist ?? []))
        let albums = dedupAlbums((a.album ?? []) + (b.album ?? []))
        let songs = dedupSongs((a.song ?? []) + (b.song ?? []))
        return SearchResult3(
            artist: artists.isEmpty ? nil : artists,
            album: albums.isEmpty ? nil : albums,
            song: songs.isEmpty ? nil : songs
        )
    }

    private func dedup(_ artists: [Artist]) -> [Artist] {
        var seen = Set<String>()
        return artists.filter { seen.insert($0.id).inserted }
    }

    private func dedupAlbums(_ albums: [Album]) -> [Album] {
        var seen = Set<String>()
        return albums.filter { seen.insert($0.id).inserted }
    }

    private func dedupSongs(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return songs.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Relevance ranking (#85 Slice 1)

private extension SearchView {
    /// Relevance-rank the already-fetched result sections. Order: exact > starts-with >
    /// word-boundary/token prefix > loose contains; small subtle boosts for starred + frequently
    /// played so text relevance still dominates. Stable on ties (preserves the server's order).
    /// Pure/synchronous — scoring ~80 items is sub-millisecond, so it runs inline rather than via a
    /// detached round-trip that would delay the instant local results.
    func rankedResults(_ results: SearchResult3, query: String) -> SearchResult3 {
        let q = Self.normalizeForRanking(query)
        guard !q.isEmpty else { return results }

        let artists = Self.stableRankSort(results.artist ?? []) {
            Self.relevanceScore(Self.normalizeForRanking($0.name), query: q,
                                starred: $0.starred != nil, plays: 0)
        }
        let albums = Self.stableRankSort(results.album ?? []) {
            Self.relevanceScore(Self.normalizeForRanking($0.name), query: q,
                                starred: $0.starred != nil, plays: $0.playCount ?? 0)
        }
        let songs = Self.stableRankSort(results.song ?? []) {
            Self.relevanceScore(Self.normalizeForRanking($0.title), query: q,
                                starred: $0.starred != nil, plays: Int($0.playCount ?? 0))
        }
        return SearchResult3(
            artist: artists.isEmpty ? nil : artists,
            album: albums.isEmpty ? nil : albums,
            song: songs.isEmpty ? nil : songs
        )
    }

    nonisolated static func normalizeForRanking(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Text tiers are 200 apart while the boosts total <= 65, so a tier can never be overtaken by
    /// boosts alone — relevance always wins; boosts only reorder items within the same tier.
    static func relevanceScore(_ text: String, query q: String, starred: Bool, plays: Int) -> Int {
        var s: Int
        if text == q {
            s = 1000
        } else if text.hasPrefix(q) {
            s = 600
        } else if tokenHasPrefix(text, q) {
            s = 400
        } else if text.contains(q) {
            s = 200
        } else {
            s = 0
        }
        if starred { s += 40 }
        s += min(max(plays, 0), 25)
        return s
    }

    /// True if any word (letter/number token) in `text` begins with `q` — the "word-boundary"
    /// match, e.g. query "beat" matches the "Beatles" token in "The Beatles".
    static func tokenHasPrefix(_ text: String, _ q: String) -> Bool {
        for token in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where token.hasPrefix(q) {
            return true
        }
        return false
    }

    /// Sort by score descending; ties keep original order (Swift's sort isn't guaranteed stable).
    static func stableRankSort<T>(_ items: [T], _ score: (T) -> Int) -> [T] {
        items.enumerated()
            .sorted { a, b in
                let sa = score(a.element), sb = score(b.element)
                return sa != sb ? sa > sb : a.offset < b.offset
            }
            .map(\.element)
    }
}

// MARK: - Fuzzy / typo-tolerant matching (#85 Slice 3, Artists + Albums only)

private extension SearchView {
    /// Run fuzzy only when a type's normal (exact/substring) results are sparse.
    static let fuzzyThinThreshold = 5

    /// Append typo-tolerant local-cache Artist/Album matches below the ranked real results, when the
    /// normal results are thin. Fuzzy hits rank BELOW real matches (appended after them) and are
    /// bounded (min length, thin-gate, scope, first-letter + length prefilter, off-main). Songs are
    /// intentionally excluded — full-library song fuzzy has higher perf/false-positive risk.
    func fuzzyAugmented(_ ranked: SearchResult3, query: String) async -> SearchResult3 {
        let q = Self.normalizeForRanking(query)
        guard q.count >= 4 else { return ranked }

        let doArtists = (selectedScope == .all || selectedScope == .artists)
            && (ranked.artist?.count ?? 0) < Self.fuzzyThinThreshold
        let doAlbums = (selectedScope == .all || selectedScope == .albums)
            && (ranked.album?.count ?? 0) < Self.fuzzyThinThreshold
        guard doArtists || doAlbums else { return ranked }

        let haveArtistIds = Set((ranked.artist ?? []).map(\.id))
        let haveAlbumIds = Set((ranked.album ?? []).map(\.id))
        let container = PersistenceController.shared.container

        let extra = await Task.detached(priority: .utility) { () -> (artists: [Artist], albums: [Album]) in
            let context = ModelContext(container)
            context.autosaveEnabled = false
            var fArtists: [Artist] = []
            var fAlbums: [Album] = []
            if doArtists {
                let cached = (try? context.fetch(FetchDescriptor<CachedArtist>())) ?? []
                fArtists = Self.fuzzyMatches(cached, query: q) { $0.name }
                    .filter { !haveArtistIds.contains($0.item.id) }
                    .prefix(8).map { $0.item.toArtist() }
            }
            if doAlbums {
                let cached = (try? context.fetch(FetchDescriptor<CachedAlbum>())) ?? []
                fAlbums = Self.fuzzyMatches(cached, query: q) { $0.name }
                    .filter { !haveAlbumIds.contains($0.item.id) }
                    .prefix(8).map { $0.item.toAlbum() }
            }
            return (fArtists, fAlbums)
        }.value

        guard !extra.artists.isEmpty || !extra.albums.isEmpty else { return ranked }
        return SearchResult3(
            artist: Self.mergeAppend(ranked.artist, extra.artists),
            album: Self.mergeAppend(ranked.album, extra.albums),
            song: ranked.song
        )
    }

    nonisolated static func mergeAppend<T>(_ base: [T]?, _ extra: [T]) -> [T]? {
        let combined = (base ?? []) + extra
        return combined.isEmpty ? nil : combined
    }

    /// Cached items whose name has a *token* within the length-scaled Damerau-Levenshtein threshold
    /// of `q`, sorted by best (smallest) distance. Cheap prefilter (shared first letter + comparable
    /// length) runs before the bounded edit-distance so most candidates are rejected instantly.
    nonisolated static func fuzzyMatches<T>(
        _ items: [T], query q: String, name: (T) -> String
    ) -> [(item: T, dist: Int)] {
        let threshold = q.count >= 7 ? 2 : 1
        guard let qFirst = q.first else { return [] }
        var out: [(T, Int)] = []
        for item in items {
            let normalized = normalizeForRanking(name(item))
            var best = Int.max
            for token in normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let t = String(token)
                // Cheap prefilter: share first letter, and comparable length.
                guard t.first == qFirst, abs(t.count - q.count) <= threshold else { continue }
                let d = boundedDamerauLevenshtein(t, q, max: threshold)
                if d <= threshold { best = Swift.min(best, d) }
            }
            if best <= threshold { out.append((item, best)) }
        }
        return out.sorted { $0.1 < $1.1 }
    }

    /// Damerau-Levenshtein (optimal string alignment, with adjacent transposition), bounded by
    /// `max` with early row-exit — returns `max + 1` as soon as no alignment can stay within budget.
    nonisolated static func boundedDamerauLevenshtein(_ a: String, _ b: String, max: Int) -> Int {
        let s = Array(a), t = Array(b)
        let n = s.count, m = t.count
        if abs(n - m) > max { return max + 1 }
        if n == 0 { return m }
        if m == 0 { return n }
        var prev2 = [Int](repeating: 0, count: m + 1)
        var prev = Array(0...m)
        var curr = [Int](repeating: 0, count: m + 1)
        for i in 1...n {
            curr[0] = i
            var rowMin = curr[0]
            for j in 1...m {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                var d = Swift.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    d = Swift.min(d, prev2[j - 2] + 1)
                }
                curr[j] = d
                rowMin = Swift.min(rowMin, d)
            }
            if rowMin > max { return max + 1 }
            swap(&prev2, &prev)
            swap(&prev, &curr)
        }
        return prev[m]
    }
}
