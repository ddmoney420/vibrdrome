#if os(macOS)
import SwiftData
import SwiftUI

struct MacHomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var showCustomize = false
    @State private var isRefreshing = false

    private var model: MacHomeViewModel { appState.homeViewModel }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                greetingRow
                    .padding(.horizontal, 32)

                ForEach(model.layoutConfig.visibleSections) { section in
                    sectionView(for: section)
                }
            }
            .padding(.vertical, 28)
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    Task {
                        await model.reload(
                            client: appState.subsonicClient,
                            container: PersistenceController.shared.container,
                            libraryCache: appState.libraryCache
                        )
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help("Refresh Home")
                .disabled(isRefreshing)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showCustomize = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Customize Home")
            }
        }
        .sheet(isPresented: $showCustomize) {
            MacHomeCustomizeView(config: Bindable(model).layoutConfig)
        }
        .onChange(of: appState.libraryCache.generation) { _, _ in
            Task {
                await model.reload(
                    client: appState.subsonicClient,
                    container: PersistenceController.shared.container,
                    libraryCache: appState.libraryCache
                )
            }
        }
    }

    // MARK: - Greeting + stats

    @ViewBuilder
    private var greetingRow: some View {
        HStack(alignment: .bottom) {
            Text(greetingText)
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            listeningStats
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    @ViewBuilder
    private var listeningStats: some View {
        let now = Date()
        let dayStart = Calendar.current.startOfDay(for: now)
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        HStack(spacing: 16) {
            statBadge(label: "Today", count: playCount(from: dayStart))
            statBadge(label: "This week", count: playCount(from: weekStart))
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func statBadge(label: String, count: Int) -> some View {
        if count > 0 {
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(count)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func playCount(from startDate: Date) -> Int {
        let context = modelContext
        let descriptor = FetchDescriptor<PlayHistory>(
            predicate: #Predicate<PlayHistory> { $0.playedAt >= startDate }
        )
        return (try? context.fetch(descriptor).count) ?? 0
    }

    // MARK: - Section dispatch

    @ViewBuilder
    private func sectionView(for section: MacHomeSection) -> some View {
        switch section {
        case .quickActions:
            quickActionsStrip
                .padding(.horizontal, 32)
        case .jumpBackIn:
            if !model.jumpBackInAlbums.isEmpty {
                jumpBackInSection
                    .padding(.horizontal, 32)
            }
        case .recentlyAdded:
            if !model.recentlyAddedAlbums.isEmpty {
                carousel(title: "Recently Added", systemImage: "sparkles",
                         albums: model.recentlyAddedAlbums,
                         seeAllSidebar: .recentlyAdded)
            }
        case .topArtists:
            if !model.topArtists.isEmpty { topArtistsSection }
        case .rediscover:
            if !model.starredSongs.isEmpty { rediscoverSection }
        default:
            carouselSectionView(for: section)
        }
    }

    @ViewBuilder
    private func carouselSectionView(for section: MacHomeSection) -> some View {
        switch section {
        case .mostPlayed:
            if !model.mostPlayedAlbums.isEmpty {
                carousel(title: "Most Played", systemImage: "star.fill",
                         albums: model.mostPlayedAlbums,
                         seeAllSidebar: .mostPlayed)
            }
        case .featuredGenre:
            if !model.featuredGenreAlbums.isEmpty {
                carousel(
                    title: "Featured: \(model.featuredGenreName)",
                    systemImage: "guitars.fill",
                    albums: model.featuredGenreAlbums,
                    seeAllRoute: model.featuredGenreName.isEmpty ? nil :
                        SidebarContentView.SidebarNavRoute.genre(model.featuredGenreName)
                )
            }
        case .randomPicks:
            if !model.randomPickAlbums.isEmpty {
                carousel(title: "Random Picks", systemImage: "dice.fill",
                         albums: model.randomPickAlbums)
            }
        case .favoriteAlbums:
            if !model.favoriteAlbums.isEmpty {
                carousel(title: "Favorite Albums", systemImage: "heart.fill",
                         albums: model.favoriteAlbums,
                         seeAllSidebar: .favorites)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Quick Actions

    private var quickActionsStrip: some View {
        HStack(spacing: 12) {
            actionPill(
                label: "Random Mix",
                icon: "dice.fill",
                color: .indigo,
                isLoading: model.isLoadingRandomMix
            ) {
                Task { await model.playRandomMix(appState: appState) }
            }
            actionPill(
                label: "Random Album",
                icon: "opticaldisc.fill",
                color: .orange,
                isLoading: model.isLoadingRandomAlbum
            ) {
                Task { await model.playRandomAlbum(appState: appState) }
            }
            if !model.starredSongs.isEmpty {
                actionPill(
                    label: "Shuffle Favorites",
                    icon: "heart.fill",
                    color: .pink,
                    isLoading: model.isLoadingShuffleFavorites
                ) {
                    Task { await model.shuffleFavorites(appState: appState) }
                }
            }
        }
    }

    @ViewBuilder
    private func actionPill(
        label: String,
        icon: String,
        color: Color,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Jump Back In

    private var jumpBackInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Jump Back In", systemImage: "arrow.uturn.backward.circle.fill")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Theme.albumCardSize, maximum: Theme.albumCardSize + 20),
                                   spacing: 16)],
                spacing: 16
            ) {
                ForEach(model.jumpBackInAlbums.prefix(12)) { album in
                    NavigationLink(value: SidebarContentView.SidebarNavRoute.album(album.id)) {
                        AlbumGridCard(album: album, cellWidth: Theme.albumCardSize)
                    }
                    .buttonStyle(.plain)
                    .albumGetInfoContextMenu(album: album)
                }
            }
        }
    }

    // albumCardSize + title + artist + spacing + vertical padding
    private var albumCarouselHeight: CGFloat { Theme.albumCardSize + 52 }

    // MARK: - Standard Carousel

    private func carousel(
        title: String,
        systemImage: String,
        albums: [Album],
        seeAllSidebar: SidebarContentView.SidebarItem? = nil,
        seeAllRoute: SidebarContentView.SidebarNavRoute? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: title, systemImage: systemImage)
                Spacer()
                if let sidebar = seeAllSidebar {
                    Button("See All") { appState.pendingSidebarSelection = sidebar }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                } else if let route = seeAllRoute {
                    NavigationLink(value: route) {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink(value: SidebarContentView.SidebarNavRoute.album(album.id)) {
                            AlbumGridCard(album: album, cellWidth: Theme.albumCardSize)
                        }
                        .buttonStyle(.plain)
                        .albumGetInfoContextMenu(album: album)
                    }
                }
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .padding(.vertical, 4)
            }
            .frame(height: albumCarouselHeight)
        }
    }

    // MARK: - Top Artists

    // artistBubbleSize + name + play count + spacing + vertical padding
    private var artistCarouselHeight: CGFloat { Theme.artistBubbleSize + 44 }

    private var topArtistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: "Your Top Artists", systemImage: "music.mic")
                Spacer()
                Button("See All") { appState.pendingSidebarSelection = .artists }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(model.topArtists, id: \.name) { artist in
                        artistBubble(artist)
                    }
                }
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .padding(.vertical, 4)
            }
            .frame(height: artistCarouselHeight)
        }
    }

    @ViewBuilder
    private func artistBubble(_ artist: (id: String?, name: String, count: Int, coverArtId: String?)) -> some View {
        let content = VStack(spacing: 8) {
            if let coverArtId = artist.coverArtId {
                AlbumArtView(coverArtId: coverArtId, size: Theme.artistBubbleSize,
                             cornerRadius: Theme.artistBubbleSize / 2)
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: Theme.artistBubbleSize, height: Theme.artistBubbleSize)
                    .overlay {
                        Text(String(artist.name.prefix(1)).uppercased())
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }
            }
            Text(artist.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(width: Theme.artistBubbleSize)
            Text("\(artist.count) plays")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        if let artistId = artist.id {
            NavigationLink(value: SidebarContentView.SidebarNavRoute.artist(artistId)) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    // MARK: - Rediscover

    private var rediscoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: "Rediscover", systemImage: "heart.fill")
                Spacer()
                Button("See All") { appState.pendingSidebarSelection = .favorites }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(Array(model.starredSongs.enumerated()), id: \.element.id) { index, song in
                        Group {
                            if let albumId = song.albumId {
                                NavigationLink(value: SidebarContentView.SidebarNavRoute.album(albumId)) {
                                    AlbumGridCard(album: song.asAlbum, cellWidth: Theme.albumCardSize)
                                }
                                .buttonStyle(.plain)
                            } else {
                                AlbumGridCard(album: song.asAlbum, cellWidth: Theme.albumCardSize)
                            }
                        }
                        .trackContextMenu(song: song, queue: model.starredSongs, index: index)
                        .onTapGesture {
                            if song.albumId == nil {
                                AudioEngine.shared.play(song: song, from: model.starredSongs, at: index)
                            }
                        }
                    }
                }
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .padding(.vertical, 4)
            }
            .frame(height: albumCarouselHeight)
        }
    }

    // MARK: - Shared

    private func sectionHeader(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title2)
            .fontWeight(.semibold)
    }
}
#endif
