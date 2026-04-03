import SwiftUI
import NukeUI

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var recentAlbums: [Album] = []
    @State private var frequentAlbums: [Album] = []
    @State private var randomAlbums: [Album] = []
    @State private var starredSongs: [Song] = []
    @State private var isLoaded = false
    @State private var isLoadingRandomMix = false
    @State private var isLoadingRandomAlbum = false
    @State private var layoutConfig = LibraryLayoutConfig.load()
    @State private var showCustomize = false
    @State private var musicFolders: [MusicFolder] = []
    @AppStorage(UserDefaultsKeys.activeMusicFolderId) private var activeFolderId: String = ""

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Library")
            .toolbar {
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
            }
            .sheet(isPresented: $showCustomize) {
                LibraryCustomizeView(config: $layoutConfig)
            }
            .task {
                guard !isLoaded else { return }
                await loadSections()
                isLoaded = true
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
        case .favorites:
            quickAccessPill("Favorites", icon: "heart.fill", color: .pink) { FavoritesView() }
        case .radio:
            quickAccessPill("Radio", icon: "antenna.radiowaves.left.and.right", color: .mint) { RadioView() }
        case .generations:
            quickAccessPill("Generations", icon: "calendar", color: .red) { GenerationsView() }
        case .playlists:
            quickAccessPill("Playlists", icon: "music.note.list", color: .purple) { PlaylistsView() }
        case .genres:
            quickAccessPill("Genres", icon: "guitars.fill", color: .orange) { GenresView() }
        case .downloads:
            quickAccessPill("Downloads", icon: "arrow.down.circle.fill", color: .teal) { DownloadsView() }
        case .artists:
            quickAccessPill("Artists", icon: "music.mic", color: .purple) { ArtistsView() }
        case .recentlyAdded:
            quickAccessPill("Recently Added", icon: "sparkles", color: .yellow) { AlbumsView(listType: .newest, title: "Recently Added") }
        case .albums:
            quickAccessPill("Albums", icon: "square.stack.fill", color: .blue) { AlbumsView(listType: .alphabeticalByName, title: "Albums") }
        case .recentlyPlayed:
            quickAccessPill("Recently Played", icon: "play.circle.fill", color: .cyan) { AlbumsView(listType: .recent, title: "Recently Played") }
        case .songs:
            quickAccessPill("Songs", icon: "music.note", color: .pink) { SongsView() }
        case .randomAlbum:
            randomAlbumPill
        case .folders:
            quickAccessPill("Folders", icon: "folder.fill", color: .green) { FolderBrowserView() }
        case .randomMix:
            randomMixPill
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
        async let starred = client.getStarred(musicFolderId: folder)

        recentAlbums = (try? await recent) ?? recentAlbums
        frequentAlbums = (try? await frequent) ?? frequentAlbums
        randomAlbums = (try? await random) ?? randomAlbums

        if let result = try? await starred, var songs = result.song, !songs.isEmpty {
            songs.shuffle()
            starredSongs = Array(songs.prefix(15))
        }
    }
}
