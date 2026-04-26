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
    @State private var isLoading = true
    @State private var error: String?
    @State private var hasMore = true
    @State private var searchText = ""
    @State private var searchIsActive = false
    @State private var activeListType: AlbumListType?
    @State private var clientSideSort: AlbumSortOption?
    @State private var getInfoTarget: GetInfoTarget?
    @AppStorage("albumsViewStyle") private var showAsList = false
    @AppStorage(UserDefaultsKeys.gridColumnsPerRow) private var gridColumns = 2
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.modelContext) private var modelContext
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

    private var filteredAlbums: [Album] {
        // When searching, use server results (search3 searches the entire library,
        // not just the paginated pages already loaded client-side).
        var result = searchText.isEmpty ? albums : searchResults
        if !searchText.isEmpty, let activeGenre = effectiveGenre {
            result = result.filter {
                $0.genre?.caseInsensitiveCompare(activeGenre) == .orderedSame
            }
        }
        switch activeFilter {
        case .all:
            break
        case .favorites:
            result = result.filter { favoritedAlbumIds.contains($0.id) }
        case .downloaded:
            let downloaded = downloadedAlbumNames
            result = result.filter { downloaded.contains($0.name.lowercased()) }
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
        .task {
            await loadAlbums()
            if availableGenres.isEmpty {
                availableGenres = (try? await appState.subsonicClient.getGenres()
                    .map(\.value).sorted()) ?? []
            }
            await loadFavoritedAlbumIds()
        }
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
    }

    private func loadFavoritedAlbumIds() async {
        guard favoritedAlbumIds.isEmpty else { return }
        if let starred = try? await appState.subsonicClient.getStarred(),
           let albums = starred.album {
            favoritedAlbumIds = Set(albums.map(\.id))
        }
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
        let cols = Theme.effectiveGridColumns(base: gridColumns, verticalSizeClass: verticalSizeClass)
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: cols)
    }

    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridItems, spacing: 20) {
                ForEach(filteredAlbums) { album in
                    NavigationLink {
                        AlbumDetailView(albumId: album.id)
                    } label: {
                        AlbumGridCard(album: album)
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

    private func paginateIfNeeded(_ album: Album) {
        if album.id == albums.last?.id && hasMore {
            Task { await loadMore() }
        }
    }

    private func loadAlbums() async {
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
                type: effectiveListType, size: pageSize, offset: albums.count, genre: effectiveGenre,
                fromYear: fromYear, toYear: toYear)
            albums.append(contentsOf: result)
            hasMore = result.count >= pageSize
        } catch {
            hasMore = false
        }
    }
}
