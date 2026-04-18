import SwiftData
import SwiftUI
import NukeUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @Binding var navPath: NavigationPath
    @State private var recentAlbums: [Album] = []
    @State private var frequentAlbums: [Album] = []
    @State private var randomAlbums: [Album] = []
    @State private var recentlyPlayedAlbums: [Album] = []
    @State private var starredSongs: [Song] = []
    @State private var topArtistNames: [(name: String, count: Int, coverArtId: String?)] = []
    @State private var isLoaded = false
    @State private var isLoadingRandomMix = false
    @State private var isLoadingRandomAlbum = false
    @State private var layoutConfig = LibraryLayoutConfig.load()
    @State private var showCustomize = false
    @State private var musicFolders: [MusicFolder] = []
    @State private var showCreatePlaylist = false
    @State private var showSmartPlaylist = false
    @AppStorage(UserDefaultsKeys.activeMusicFolderId) private var activeFolderId: String = ""
    @AppStorage(UserDefaultsKeys.settingsInNavBar) private var settingsInNavBar = false

    init(navPath: Binding<NavigationPath> = .constant(NavigationPath())) {
        _navPath = navPath
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(spacing: 28) {
                    // Quick access pills
                    if !layoutConfig.visiblePills.isEmpty {
                        quickAccessBar
                            .padding(.top, 4)
                    }

                    // Dynamic carousels
                    ForEach(layoutConfig.visibleCarousels) { carousel in
                        carouselView(for: carousel)
                    }
                }
                #if os(iOS)
                .padding(.bottom, 80)
                #endif
            }
            .refreshable {
                await fetchSections(client: appState.subsonicClient, skipCache: true)
            }
            .navigationTitle(activeServerName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showCreatePlaylist = true
                        } label: {
                            Label("New Playlist", systemImage: "music.note.list")
                        }
                        Button {
                            showSmartPlaylist = true
                        } label: {
                            Label("New Smart Playlist", systemImage: "sparkles")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create New")
                    .accessibilityIdentifier("createPlaylistButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if settingsInNavBar {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gear")
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("settingsNavBarButton")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    profileMenu
                }
                #else
                ToolbarItem(placement: .automatic) {
                    if musicFolders.count > 1 {
                        Menu {
                            Button {
                                activeFolderId = ""
                                Task { await reloadSections() }
                            } label: {
                                HStack {
                                    Text("All Libraries")
                                    if activeFolderId.isEmpty { Image(systemName: "checkmark") }
                                }
                            }
                            ForEach(musicFolders) { folder in
                                Button {
                                    activeFolderId = folder.id
                                    Task { await reloadSections() }
                                } label: {
                                    HStack {
                                        Text(folder.name ?? folder.id)
                                        if activeFolderId == folder.id { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "building.2")
                        }
                        .accessibilityLabel("Switch Library")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showCustomize = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Customize Library")
                }
                #endif
            }
            .sheet(isPresented: $showCustomize) {
                LibraryCustomizeView(config: $layoutConfig)
            }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistEditorView(mode: .create)
                    .environment(appState)
            }
            .sheet(isPresented: $showSmartPlaylist) {
                SmartPlaylistView()
                    .environment(appState)
            }
            .task {
                guard !isLoaded else { return }
                await loadSections()
                isLoaded = true
            }
            .navigationDestination(for: ArtistNavItem.self) { item in
                ArtistDetailView(artistId: item.id)
            }
            .navigationDestination(for: AlbumNavItem.self) { item in
                AlbumDetailView(albumId: item.id)
            }
            .navigationDestination(for: SongNavItem.self) { item in
                SongDetailView(songId: item.id)
            }
            .navigationDestination(for: GenreNavItem.self) { item in
                AlbumsView(listType: .byGenre, title: item.name.cleanedGenreDisplay, genre: item.name)
            }
            .navigationDestination(for: PlaylistNavItem.self) { item in
                PlaylistDetailView(playlistId: item.id)
            }
            .navigationDestination(for: OfflineNavItem.self) { _ in
                DownloadsView()
            }
        }
    }

    // MARK: - Dynamic Carousel

    @ViewBuilder
    private func carouselView(for carousel: LibraryCarousel) -> some View {
        switch carousel {
        case .recentlyAdded:
            if !recentAlbums.isEmpty {
                albumSection("Recently Added", albums: recentAlbums) {
                    AlbumsView(listType: .newest, title: "Recently Added")
                }
            }
        case .mostPlayed:
            if !frequentAlbums.isEmpty {
                albumSection("Most Played", albums: frequentAlbums) {
                    AlbumsView(listType: .frequent, title: "Most Played")
                }
            }
        case .rediscover:
            if !starredSongs.isEmpty {
                rediscoverSection
            }
        case .randomPicks:
            if !randomAlbums.isEmpty {
                albumSection("Random Picks", albums: randomAlbums) {
                    AlbumsView(listType: .random, title: "Random")
                }
            }
        case .recentlyPlayed:
            if !recentlyPlayedAlbums.isEmpty {
                albumSection("Recently Played", albums: recentlyPlayedAlbums) {
                    AlbumsView(listType: .recent, title: "Recently Played")
                }
            }
        case .topArtists:
            if !topArtistNames.isEmpty {
                topArtistsCarousel
            }
        }
    }

    // MARK: - Quick Access

    private var quickAccessColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 140), spacing: 10)]
        #else
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        #endif
    }

    private var quickAccessBar: some View {
        LazyVGrid(columns: quickAccessColumns, spacing: 10) {
            ForEach(layoutConfig.visiblePills) { pill in
                pillView(for: pill)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func pillView(for pill: LibraryPill) -> some View {
        switch pill {
        case .randomAlbum: randomAlbumPill
        case .randomMix: randomMixPill
        default: pillNavLink(for: pill)
        }
    }

    @ViewBuilder
    private func pillNavLink(for pill: LibraryPill) -> some View {
        quickAccessPill(pill) { pillDestination(for: pill) }
    }

    @ViewBuilder
    private func pillDestination(for pill: LibraryPill) -> some View {
        switch pill {
        case .favorites: FavoritesView()
        case .radio: RadioView()
        case .generations: GenerationsView()
        case .playlists: PlaylistsView()
        case .genres: GenresView()
        case .downloads: DownloadsView()
        case .artists: ArtistsView()
        case .recentlyAdded: AlbumsView(listType: .newest, title: "Recently Added")
        case .albums: AlbumsView(listType: .alphabeticalByName, title: "Albums")
        case .recentlyPlayed: AlbumsView(listType: .recent, title: "Recently Played")
        default: pillDestinationExtended(for: pill)
        }
    }

    @ViewBuilder
    private func pillDestinationExtended(for pill: LibraryPill) -> some View {
        switch pill {
        case .songs: SongsView()
        case .folders: FolderBrowserView()
        case .playHistory: PlayHistoryView()
        case .smartPlaylists: SmartPlaylistView()
        case .jukebox: JukeboxView()
        default: EmptyView()
        }
    }

    private var randomMixPill: some View {
        Button {
            guard !isLoadingRandomMix else { return }
            Task { await playRandomMix() }
        } label: {
            HStack(spacing: 8) {
                if isLoadingRandomMix {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "dice.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.indigo)
                }
                Text("Random Mix")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isLoadingRandomMix)
    }

    private var randomAlbumPill: some View {
        Button {
            guard !isLoadingRandomAlbum else { return }
            Task { await playRandomAlbum() }
        } label: {
            HStack(spacing: 8) {
                if isLoadingRandomAlbum {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                }
                Text("Random Album")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isLoadingRandomAlbum)
    }

    private func quickAccessPill<D: View>(
        _ pill: LibraryPill,
        @ViewBuilder destination: @escaping () -> D
    ) -> some View {
        quickAccessPill(pill.title, icon: pill.icon, color: pillColor(pill.color), destination: destination)
    }

    private func pillColor(_ name: String) -> Color {
        switch name {
        case "pink": .pink
        case "mint": .mint
        case "red": .red
        case "purple": .purple
        case "orange": .orange
        case "teal": .teal
        case "yellow": .yellow
        case "blue": .blue
        case "cyan": .cyan
        case "green": .green
        case "indigo": .indigo
        default: .primary
        }
    }

    private func quickAccessPill<D: View>(
        _ title: String, icon: String, color: Color,
        @ViewBuilder destination: @escaping () -> D
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Album Art Sections

    private func albumSection<D: View>(
        _ title: String,
        albums: [Album],
        @ViewBuilder destination: @escaping () -> D
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with "See All"
            HStack {
                Text(title)
                    .font(.title3)
                    .bold()
                Spacer()
                NavigationLink {
                    destination()
                } label: {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)

            // Horizontal scroll of album art
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(albumId: album.id)
                        } label: {
                            albumCard(album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func albumCard(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AlbumArtView(coverArtId: album.coverArt, size: Theme.albumCardSize, cornerRadius: 10)
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
        .frame(width: Theme.albumCardSize)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("albumCard")
    }

    // MARK: - Rediscover Section

    private var rediscoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rediscover")
                    .font(.title3)
                    .bold()
                Spacer()
                NavigationLink {
                    FavoritesView()
                } label: {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(starredSongs) { song in
                        songCard(song)
                            .onTapGesture {
                                AudioEngine.shared.play(song: song, from: starredSongs, at: starredSongs.firstIndex(where: { $0.id == song.id }) ?? 0)
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func songCard(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AlbumArtView(coverArtId: song.coverArt, size: Theme.songCardSize, cornerRadius: 10)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(song.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(song.artist ?? "")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: Theme.songCardSize)
    }

    /// Returns the active folder ID or nil for "All Libraries"
    private var folderId: String? {
        activeFolderId.isEmpty ? nil : activeFolderId
    }

    /// Display name for the active server, shown as the navigation title
    private var activeServerName: String {
        if let activeId = appState.activeServerId,
           let server = appState.servers.first(where: { $0.id == activeId }) {
            return server.name
        }
        // Fallback: extract from URL or use "Home"
        if !appState.serverURL.isEmpty, let host = URL(string: appState.serverURL)?.host {
            return host
        }
        return "Home"
    }

    // MARK: - Profile Menu

    private var profileMenu: some View {
        Menu {
            // Server section
            Section("Server") {
                ForEach(appState.servers) { server in
                    Button {
                        appState.switchToServer(id: server.id)
                        Task { await reloadSections() }
                    } label: {
                        HStack(spacing: 6) {
                            if appState.activeServerId == server.id {
                                Circle()
                                    .fill(appState.isConfigured ? .green : .red)
                                    .frame(width: 8, height: 8)
                                    .accessibilityLabel(
                                        appState.isConfigured ? "Connected" : "Disconnected"
                                    )
                            }
                            Text(server.name)
                            Spacer()
                            if appState.activeServerId == server.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            // Music folders section
            if musicFolders.count > 1 {
                Section("Music Folders") {
                    Button {
                        activeFolderId = ""
                        Task { await reloadSections() }
                    } label: {
                        HStack {
                            Text("All Folders")
                            if activeFolderId.isEmpty { Image(systemName: "checkmark") }
                        }
                    }
                    ForEach(musicFolders) { folder in
                        Button {
                            activeFolderId = folder.id
                            Task { await reloadSections() }
                        } label: {
                            HStack {
                                Text(folder.name ?? folder.id)
                                if activeFolderId == folder.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }

            // Downloads & Customize
            Section {
                NavigationLink {
                    DownloadsView()
                } label: {
                    Label("Downloaded", systemImage: "arrow.down.circle")
                }
                Button {
                    showCustomize = true
                } label: {
                    Label("Customize Library", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            Image(systemName: "person.circle")
        }
        .accessibilityLabel("Profile")
        .accessibilityValue(appState.isConfigured ? "Connected" : "Disconnected")
        .accessibilityIdentifier("profileMenuButton")
    }

    private func playRandomMix() async {
        isLoadingRandomMix = true
        defer { isLoadingRandomMix = false }
        do {
            let songs = try await appState.subsonicClient.getRandomSongs(size: 50, musicFolderId: folderId)
            guard let first = songs.first else { return }
            AudioEngine.shared.play(song: first, from: songs)
        } catch {}
    }

    private func playRandomAlbum() async {
        isLoadingRandomAlbum = true
        defer { isLoadingRandomAlbum = false }
        do {
            let albums = try await appState.subsonicClient.getAlbumList(type: .random, size: 1, musicFolderId: folderId)
            guard let album = albums.first else { return }
            let detail = try await appState.subsonicClient.getAlbum(id: album.id)
            guard let songs = detail.song, let first = songs.first else { return }
            AudioEngine.shared.play(song: first, from: songs)
        } catch {}
    }

    // MARK: - Data Loading

    private func loadSections() async {
        let client = appState.subsonicClient

        // Load music folders for the picker
        if let folders = try? await client.getMusicFolders(), folders.count > 1 {
            musicFolders = folders
        }

        await fetchSections(client: client)
    }

    private func reloadSections() async {
        await fetchSections(client: appState.subsonicClient, skipCache: true)
    }

    private func fetchSections(client: SubsonicClient, skipCache: Bool = false) async {
        let folder = folderId

        // Show cached data instantly (only for unfiltered/default)
        if folder == nil, !skipCache {
            if let cached = await client.cachedResponse(
                for: .getAlbumList2(type: .newest, size: 10, offset: 0), ttl: 300) {
                recentAlbums = cached.albumList2?.album ?? []
            }
            if let cached = await client.cachedResponse(
                for: .getAlbumList2(type: .frequent, size: 10, offset: 0), ttl: 900) {
                frequentAlbums = cached.albumList2?.album ?? []
            }
            if let cached = await client.cachedResponse(for: .getStarred2(), ttl: 300) {
                if var songs = cached.starred2?.song, !songs.isEmpty {
                    songs.shuffle()
                    starredSongs = Array(songs.prefix(15))
                }
            }
        }

        // Refresh from server
        async let recent = client.getAlbumList(type: .newest, size: 10, musicFolderId: folder)
        async let frequent = client.getAlbumList(type: .frequent, size: 10, musicFolderId: folder)
        async let random = client.getAlbumList(type: .random, size: 10, musicFolderId: folder)
        async let recentlyPlayed = client.getAlbumList(type: .recent, size: 10, musicFolderId: folder)
        async let starred = client.getStarred(musicFolderId: folder)

        recentAlbums = (try? await recent) ?? recentAlbums
        frequentAlbums = (try? await frequent) ?? frequentAlbums
        randomAlbums = (try? await random) ?? randomAlbums
        recentlyPlayedAlbums = (try? await recentlyPlayed) ?? recentlyPlayedAlbums

        if let result = try? await starred, var songs = result.song, !songs.isEmpty {
            songs.shuffle()
            starredSongs = Array(songs.prefix(15))
        }

        // Load top artists from local play history
        loadTopArtists()
    }

    private func loadTopArtists() {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<PlayHistory>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        guard let plays = try? context.fetch(descriptor) else { return }
        var counts: [String: Int] = [:]
        var latestArt: [String: String] = [:]
        for play in plays {
            let artist = play.artistName ?? "Unknown"
            counts[artist, default: 0] += 1
            if latestArt[artist] == nil, let art = play.coverArtId {
                latestArt[artist] = art
            }
        }
        topArtistNames = counts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { (name: $0.key, count: $0.value, coverArtId: latestArt[$0.key]) }
    }

    private var topArtistsCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Top Artists")
                .font(.title3)
                .bold()
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(topArtistNames, id: \.name) { artist in
                        VStack(spacing: 6) {
                            if let coverArtId = artist.coverArtId {
                                AlbumArtView(coverArtId: coverArtId, size: 80, cornerRadius: 40)
                            } else {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 80, height: 80)
                                    .overlay {
                                        Text(String(artist.name.prefix(1)).uppercased())
                                            .font(.title)
                                            .bold()
                                            .foregroundStyle(.secondary)
                                    }
                            }

                            Text(artist.name)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(width: 80)

                            Text("\(artist.count) plays")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
