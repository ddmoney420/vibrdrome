import Nuke
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
    @Environment(\.modelContext) private var modelContext
    #if os(macOS)
    // Stored references break the @Observable tracking chain: AlbumsView.body reads these
    // fields once at property-init time, so changes to other AppState properties (e.g.
    // activeSidePanel) don't invalidate the grid. AlbumFilterWatcher tracks sub-properties.
    private let albumFilter = AppState.shared.albumFilter
    private let libraryCache = AppState.shared.libraryCache
    #endif
    @State private var model: AlbumsViewModel
    @State private var searchText = ""
    @State private var searchIsActive = false
    @State private var getInfoTarget: GetInfoTarget?
    @AppStorage("albumsViewStyle") private var showAsList = false
    @AppStorage(UserDefaultsKeys.gridDensity) private var gridDensityRaw: String = GridDensity.comfortable.rawValue
    private var gridDensity: GridDensity { GridDensity(rawValue: gridDensityRaw) ?? .comfortable }
    @State private var showSaveCollection = false
    @State private var collectionName = ""
    @SceneStorage("albumsFilter") private var filterRaw: String = AlbumFilter.all.rawValue
    @Query(filter: #Predicate<DownloadedSong> { $0.isComplete == true })
    private var downloadedSongs: [DownloadedSong]

    // Expose model enums at this scope for toolbar/menu use
    typealias AlbumFilter = AlbumsViewModel.AlbumFilter
    typealias AlbumSortOption = AlbumsViewModel.AlbumSortOption

    private var activeFilter: AlbumFilter { AlbumFilter(rawValue: filterRaw) ?? .all }

    init(listType: AlbumListType, title: String = "Albums", genre: String? = nil, fromYear: Int? = nil, toYear: Int? = nil) {
        self.listType = listType
        self.title = title
        self.genre = genre
        self.fromYear = fromYear
        self.toYear = toYear
        _model = State(initialValue: AlbumsViewModel(
            listType: listType, genre: genre, fromYear: fromYear, toYear: toYear))
    }

    var body: some View {
        contentView
            .overlay { albumsOverlay }
            .onChange(of: searchText) { _, new in model.onSearchTextChanged(new, appState: appState) }
            .onReceive(NotificationCenter.default.publisher(for: .focusSearchBar)) { _ in
                searchIsActive = false
                DispatchQueue.main.async { searchIsActive = true }
            }
    }

    // MARK: - Content

    private var contentView: some View {
        Group {
            if showAsList { albumList } else { albumGrid }
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
        .toolbar { toolbarContent }
        .alert("Save Collection", isPresented: $showSaveCollection) {
            TextField("Name", text: $collectionName)
            Button("Save") { saveCollection() }
            Button("Cancel", role: .cancel) { }
        }
        .navigationDestination(for: AlbumNavItem.self) { item in
            AlbumDetailView(albumId: item.id)
        }
        .task {
            #if os(macOS)
            filterRaw = AlbumFilter.all.rawValue
            #endif
            await model.onAppear(appState: appState, modelContext: modelContext, downloadedSongs: downloadedSongs, filterRaw: filterRaw)
            #if os(macOS)
            await model.applyLocalFilters(appState: appState, modelContext: modelContext, filterRaw: filterRaw)
            #endif
        }
        .onChange(of: filterRaw) { model.recomputeFilteredAlbums(filterRaw: filterRaw) }
        .onChange(of: downloadedSongs) { model.onDownloadedSongsChanged(downloadedSongs, filterRaw: filterRaw) }
        .onDisappear { model.onDisappear(appState: appState) }
        .refreshable { await model.refresh(appState: appState, filterRaw: filterRaw) }
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
        .modifier(AlbumFilterWatcher(
            filter: albumFilter,
            cache: libraryCache,
            onChange: { debouncedFilter() }
        ))
        #endif
    }

    #if os(macOS)
    private func debouncedFilter() {
        model.debouncedApplyLocalFilters(appState: appState, modelContext: modelContext, filterRaw: filterRaw)
    }
    #endif

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            AlbumFilterToggleButton()
        }
        #endif
        ToolbarItem(placement: .automatic) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAsList.toggle() }
            } label: {
                Image(systemName: showAsList ? "square.grid.2x2" : "list.bullet")
            }
            .accessibilityLabel(showAsList ? "Grid View" : "List View")
            .accessibilityIdentifier("albumsViewToggle")
        }
        ToolbarItem(placement: .primaryAction) {
            sortMenu
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(AlbumSortOption.allCases, id: \.self) { option in
                Button {
                    model.applySortOption(option, appState: appState, filterRaw: filterRaw)
                } label: {
                    HStack {
                        Text(option.label)
                        if option == .year && model.clientSideSort == .year {
                            Image(systemName: "checkmark")
                        } else if option != .year && model.effectiveListType == option.albumListType && model.clientSideSort == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Menu {
                Button {
                    model.applyGenre(nil, appState: appState, filterRaw: filterRaw)
                } label: {
                    HStack {
                        Text("All Genres")
                        if model.effectiveGenre == nil && genre == nil { Image(systemName: "checkmark") }
                    }
                }
                Divider()
                ForEach(model.availableGenres, id: \.self) { g in
                    Button {
                        model.applyGenre(g, appState: appState, filterRaw: filterRaw)
                    } label: {
                        HStack {
                            Text(g.cleanedGenreDisplay)
                            if model.effectiveGenre == g { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Label(model.effectiveGenre?.cleanedGenreDisplay ?? "Genre", systemImage: "guitars")
            }
            Divider()
            #if os(iOS)
            Picker("Filter", selection: $filterRaw) {
                ForEach(AlbumFilter.allCases) { option in
                    Label(option.label, systemImage: option.icon).tag(option.rawValue)
                }
            }
            Divider()
            #endif
            Button {
                Task { await model.refresh(appState: appState, filterRaw: filterRaw) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Divider()
            Button {
                collectionName = model.effectiveGenre?.cleanedGenreDisplay ?? title
                showSaveCollection = true
            } label: {
                Label("Save as Collection", systemImage: "folder.badge.plus")
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private var albumsOverlay: some View {
        if model.isLoading && model.albums.isEmpty {
            ProgressView("Loading albums...")
        } else if let error = model.error, model.albums.isEmpty {
            ContentUnavailableView {
                Label("Error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await model.loadAlbums(appState: appState, filterRaw: filterRaw) } }
                    .buttonStyle(.bordered)
            }
        } else if !model.isLoading && model.albums.isEmpty {
            ContentUnavailableView {
                Label("No Albums", systemImage: "square.stack")
            } description: {
                Text("No albums found")
            }
        }
    }

    // MARK: - List view

    private var albumList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(model.indexedAlbums, id: \.element.id) { index, album in
                    NavigationLink(value: AlbumNavItem(id: album.id)) {
                        AlbumCard(album: album)
                    }
                    .accessibilityIdentifier("albumRow_\(album.id)")
                    .contextMenu {
                        #if os(iOS)
                        AlbumContextMenu(album: album, getInfoTarget: $getInfoTarget)
                        #else
                        AlbumContextMenu(album: album)
                        #endif
                    }
                    .onAppear { model.triggerLoadIfNeeded(at: index, filterRaw: filterRaw) }
                }
                if model.hasMore && model.localFilteredAlbums == nil && searchText.isEmpty {
                    listLoadMoreFooter
                }
            }
            .listStyle(.plain)
            .onAppear { restoreScroll(proxy: proxy) }
        }
    }

    private var listLoadMoreFooter: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, 8)
                .onAppear {
                    model.triggerLoadIfNeeded(
                        at: model.cachedFilteredAlbums.count - 1,
                        filterRaw: filterRaw)
                }
            Spacer()
        }
        .listRowSeparator(.hidden)
    }

    // MARK: - Grid view

    private var albumGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: model.gridColumns.isEmpty
                          ? [GridItem(.adaptive(minimum: gridDensity.minimumWidth), spacing: 16)]
                          : model.gridColumns,
                          spacing: 20) {
                    ForEach(model.indexedAlbums, id: \.element.id) { index, album in
                        NavigationLink(value: AlbumNavItem(id: album.id)) {
                            AlbumGridCard(album: album, cellWidth: model.gridCellWidth)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("albumCard_\(album.id)")
                        .contextMenu {
                            #if os(iOS)
                            AlbumContextMenu(album: album, getInfoTarget: $getInfoTarget)
                            #else
                            AlbumContextMenu(album: album)
                            #endif
                        }
                        .onAppear {
                            model.triggerLoadIfNeeded(at: index, filterRaw: filterRaw)
                        }
                    }
                }
                .padding(16)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: ContainerWidthKey.self, value: geo.size.width)
                    }
                }

                if model.hasMore && model.localFilteredAlbums == nil && searchText.isEmpty {
                    gridLoadMoreFooter
                }
            }
            .onScrollGeometryChange(for: CGSize.self,
                                    of: { CGSize(width: $0.contentOffset.y, height: $0.containerSize.height) },
                                    action: { _, new in
                                        model.prefetchImagesForScrollOffset(new.width, viewportHeight: new.height)
                                        model.triggerLoadIfNeededForScrollOffset(new.width, viewportHeight: new.height, filterRaw: filterRaw)
                                    })
            #if os(iOS)
            .scrollDismissesKeyboard(.immediately)
            .scrollBounceBehavior(.basedOnSize)
            #endif
            .onPreferenceChange(ContainerWidthKey.self) {
                model.updateGridGeometry(containerWidth: $0, minCellWidth: gridDensity.minimumWidth)
            }
            .onAppear { restoreScroll(proxy: proxy) }
        }
    }

    private var gridLoadMoreFooter: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, 24)
                .onAppear {
                    model.triggerLoadIfNeeded(
                        at: model.cachedFilteredAlbums.count - 1,
                        filterRaw: filterRaw)
                }
            Spacer()
        }
    }

    private struct ContainerWidthKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    // MARK: - Helpers

    private func restoreScroll(proxy: ScrollViewProxy) {
        // Snapshot-based scroll restore is not currently used; kept for future use.
    }

    private func saveCollection() {
        let count = (try? modelContext.fetchCount(FetchDescriptor<AlbumCollection>())) ?? 0
        let collection = AlbumCollection(
            name: collectionName,
            listType: model.effectiveListType,
            genre: model.effectiveGenre,
            fromYear: fromYear,
            toYear: toYear,
            order: count
        )
        modelContext.insert(collection)
        try? modelContext.save()
    }
}

// MARK: - AlbumContextMenu

private struct AlbumContextMenu: View {
    let album: Album
    @Environment(AppState.self) private var appState

    #if os(iOS)
    @Binding var getInfoTarget: GetInfoTarget?
    init(album: Album, getInfoTarget: Binding<GetInfoTarget?>) {
        self.album = album
        self._getInfoTarget = getInfoTarget
    }
    #else
    @Environment(\.openWindow) private var openWindow
    init(album: Album) {
        self.album = album
    }
    #endif

    var body: some View {
        Button {
            fetch { songs in
                if let first = songs.first { AudioEngine.shared.play(song: first, from: songs, at: 0) }
            }
        } label: { Label("Play", systemImage: "play.fill") }

        Button {
            fetch { songs in
                var shuffled = songs; shuffled.shuffle()
                if let first = shuffled.first { AudioEngine.shared.play(song: first, from: shuffled, at: 0) }
            }
        } label: { Label("Shuffle", systemImage: "shuffle") }

        Button {
            fetch { AudioEngine.shared.addToQueueNext($0) }
        } label: { Label("Play Next", systemImage: "text.insert") }

        Button {
            fetch { AudioEngine.shared.addToQueue($0) }
        } label: { Label("Add to Queue", systemImage: "text.append") }

        Button {
            fetch { DownloadManager.shared.downloadAlbum(songs: $0, client: appState.subsonicClient) }
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

    private func fetch(action: @escaping ([Song]) -> Void) {
        let client = appState.subsonicClient
        let albumId = album.id
        Task {
            do {
                let detail = try await client.getAlbum(id: albumId)
                if let songs = detail.song, !songs.isEmpty { action(songs) }
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "Albums")
                    .error("Album action failed: \(error)")
            }
        }
    }
}

// MARK: - AlbumFilterWatcher

/// Watches LibraryFilter and LibraryDataCache directly so AlbumsView.body does not
/// access AppState properties — preventing activeSidePanel changes from re-rendering the grid.
#if os(macOS)
private struct AlbumFilterWatcher: ViewModifier {
    let filter: LibraryFilter
    let cache: LibraryDataCache
    let onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: filter.isFavorited) { onChange() }
            .onChange(of: filter.isRated) { onChange() }
            .onChange(of: filter.isRecentlyPlayed) { onChange() }
            .onChange(of: filter.selectedArtistIds) { onChange() }
            .onChange(of: filter.selectedGenres) { onChange() }
            .onChange(of: filter.selectedLabels) { onChange() }
            .onChange(of: filter.year) { onChange() }
            .onChange(of: cache.generation) { _, _ in onChange() }
    }
}
#endif

// MARK: - AlbumFilterToggleButton

#if os(macOS)
private struct AlbumFilterToggleButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            if appState.activeSidePanel == .albumFilters {
                appState.activeSidePanel = nil
            } else {
                appState.activeSidePanel = .albumFilters
            }
        } label: {
            Image(systemName: appState.albumFilter.isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Album Filters")
        .accessibilityIdentifier("albumFilterToggle")
    }
}
#endif
