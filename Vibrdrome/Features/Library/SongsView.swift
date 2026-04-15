import NukeUI
import SwiftUI
import SwiftData
import os.log

struct SongsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var songs: [Song] = []
    @State private var localFilteredSongs: [Song]?
    @State private var isLoading = true
    @State private var hasMore = false
    @State private var searchText = ""
    @State private var searchResults: [Song] = []
    @State private var isSearching = false
    @State private var availableGenres: [String] = []
    @State private var filterYear: Int?
    @State private var filterGenre: String?
    @State private var filterArtist: String?
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private var showAlbumArtInLists: Bool = true
    @AppStorage("songsViewStyle") private var showAsList = true
    @AppStorage(UserDefaultsKeys.gridColumnsPerRow) private var gridColumns = 2
    @State private var sortBy: SongSortOption = .title

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

    private var displayedSongs: [Song] {
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
        Group {
            if showAsList {
                songList
            } else {
                songGrid
            }
        }
        .navigationTitle(songs.isEmpty ? "Songs" : "Songs (\(songs.count))")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search songs")
        #else
        .searchable(text: $searchText, prompt: "Search songs")
        #endif
        .onChange(of: searchText) { _, query in
            guard query.count >= 2 else {
                searchResults = []
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
                                    Text(genre)
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
        .task {
            await loadSongs()
            await loadGenres()
            #if os(macOS)
            applyLocalFilters()
            #endif
        }
        #if os(macOS)
        .onChange(of: appState.songFilter.isFavorited) { applyLocalFilters() }
        .onChange(of: appState.songFilter.isRated) { applyLocalFilters() }
        .onChange(of: appState.songFilter.isRecentlyPlayed) { applyLocalFilters() }
        .onChange(of: appState.songFilter.selectedArtistIds) { applyLocalFilters() }
        .onChange(of: appState.songFilter.selectedGenres) { applyLocalFilters() }
        .onChange(of: appState.songFilter.year) { applyLocalFilters() }
        #endif
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
        VStack(alignment: .leading, spacing: 2) {
            Button {
                appState.pendingNavigation = .song(id: song.id)
            } label: {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                if let artist = song.artist {
                    Button {
                        if let artistId = song.artistId {
                            appState.pendingNavigation = .artist(id: artistId)
                        }
                    } label: {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(song.artistId == nil)
                }
                if let album = song.album {
                    Button {
                        if let albumId = song.albumId {
                            appState.pendingNavigation = .album(id: albumId)
                        }
                    } label: {
                        Text("· \(album)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(song.albumId == nil)
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

    // MARK: - List view

    private var songList: some View {
        List {
            if hasActiveFilters {
                activeFilterChips
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if !displayedSongs.isEmpty {
                playShuffleBar
                    .listRowSeparator(.hidden)
            }

            ForEach(Array(displayedSongs.enumerated()), id: \.element.id) { index, song in
                songRow(song)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        AudioEngine.shared.play(song: song, from: displayedSongs, at: index)
                    }
                    .accessibilityIdentifier("songRow_\(song.id)")
                    .trackContextMenu(song: song)
                    .onAppear {
                        if localFilteredSongs == nil && searchText.isEmpty && hasMore && !isLoading && song.id == songs.last?.id {
                            Task { await loadMore() }
                        }
                    }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
    }

    // MARK: - Grid view

    private var songGrid: some View {
        ScrollView {
            VStack(spacing: 12) {
                if hasActiveFilters {
                    activeFilterChips
                        .padding(.horizontal, 16)
                }

                if !displayedSongs.isEmpty {
                    playShuffleBar
                        .padding(.horizontal, 16)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16),
                                         count: max(2, min(4, gridColumns))), spacing: 20) {
                    ForEach(Array(displayedSongs.enumerated()), id: \.element.id) { index, song in
                        songCard(song)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                AudioEngine.shared.play(song: song, from: displayedSongs, at: index)
                            }
                            .accessibilityIdentifier("songCard_\(song.id)")
                            .trackContextMenu(song: song)
                            .onAppear {
                                if localFilteredSongs == nil && searchText.isEmpty && hasMore && !isLoading && song.id == songs.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                    }
                }
                .padding(16)

                if isLoading {
                    ProgressView().padding()
                }
            }
        }
    }

    private var playShuffleBar: some View {
        HStack(spacing: 12) {
            Button {
                let songs = displayedSongs
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
                let shuffled = displayedSongs.shuffled()
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
            AlbumArtView(coverArtId: song.coverArt, size: 160, cornerRadius: 10)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Button {
                appState.pendingNavigation = .song(id: song.id)
            } label: {
                Text(song.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            if let artist = song.artist {
                Button {
                    if let artistId = song.artistId {
                        appState.pendingNavigation = .artist(id: artistId)
                    }
                } label: {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(song.artistId == nil)
            }
        }
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
        isLoading = true
        songs = []
        defer { isLoading = false }
        do {
            let result = try await appState.subsonicClient.search(
                query: "", artistCount: 0, albumCount: 0, songCount: pageSize
            )
            songs = result.song ?? []
            hasMore = (result.song?.count ?? 0) >= pageSize
        } catch {}
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appState.subsonicClient.search(
                query: "", artistCount: 0, albumCount: 0,
                songCount: pageSize, songOffset: songs.count
            )
            let newSongs = result.song ?? []
            songs.append(contentsOf: newSongs)
            hasMore = newSongs.count >= pageSize
        } catch {}
    }

    #if os(macOS)
    private func applyLocalFilters() {
        let filter = appState.songFilter
        guard filter.isActive else {
            localFilteredSongs = nil
            return
        }

        do {
            var descriptor = FetchDescriptor<CachedSong>()
            descriptor.sortBy = [SortDescriptor(\.title)]
            let allSongs = try modelContext.fetch(descriptor)

            // Pre-compute recently played cutoff if needed
            let recentCutoff: Date? = filter.isRecentlyPlayed
                ? Calendar.current.date(byAdding: .day, value: -30, to: Date())
                : nil

            let filtered = allSongs.filter { song in
                // Favorited filter
                switch filter.isFavorited {
                case .yes: if !song.isStarred { return false }
                case .no: if song.isStarred { return false }
                case .none: break
                }

                // Rated filter
                switch filter.isRated {
                case .yes: if song.rating == 0 { return false }
                case .no: if song.rating != 0 { return false }
                case .none: break
                }

                // Recently played filter
                if let cutoff = recentCutoff {
                    guard let lastPlayed = song.lastPlayed, lastPlayed > cutoff else {
                        return false
                    }
                }

                // Artist filter
                if !filter.selectedArtistIds.isEmpty {
                    guard let artistId = song.artistId, filter.selectedArtistIds.contains(artistId) else {
                        return false
                    }
                }

                // Genre filter
                if !filter.selectedGenres.isEmpty {
                    guard let genre = song.genre, filter.selectedGenres.contains(genre) else {
                        return false
                    }
                }

                // Year filter
                if let yearFilter = filter.year {
                    guard song.year == yearFilter else { return false }
                }

                return true
            }

            localFilteredSongs = filtered.map { $0.toSong() }
        } catch {
            Logger(subsystem: "com.vibrdrome.app", category: "Songs")
                .error("Failed to apply local filters: \(error)")
            localFilteredSongs = nil
        }
    }
    #endif
}
