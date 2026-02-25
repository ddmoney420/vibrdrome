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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Quick access pills
                    quickAccessBar
                        .padding(.top, 4)

                    // Recently Added — hero row
                    if !recentAlbums.isEmpty {
                        albumSection("Recently Added", albums: recentAlbums) {
                            AlbumsView(listType: .newest, title: "Recently Added")
                        }
                    }

                    // Most Played
                    if !frequentAlbums.isEmpty {
                        albumSection("Most Played", albums: frequentAlbums) {
                            AlbumsView(listType: .frequent, title: "Most Played")
                        }
                    }

                    // Rediscover — starred songs shuffled
                    if !starredSongs.isEmpty {
                        rediscoverSection
                    }

                    // Random picks
                    if !randomAlbums.isEmpty {
                        albumSection("Random Picks", albums: randomAlbums) {
                            AlbumsView(listType: .random, title: "Random")
                        }
                    }

                    // More section
                    moreSection
                }
                #if os(iOS)
                .padding(.bottom, 80)
                #endif
            }
            .navigationTitle("Library")
            .task {
                guard !isLoaded else { return }
                await loadSections()
                isLoaded = true
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
            quickAccessPill("Artists", icon: "music.mic", color: .purple) { ArtistsView() }
            quickAccessPill("Albums", icon: "square.stack.fill", color: .blue) { AlbumsView(listType: .alphabeticalByName, title: "Albums") }
            quickAccessPill("Favorites", icon: "heart.fill", color: .pink) { FavoritesView() }
            quickAccessPill("Genres", icon: "guitars.fill", color: .orange) { GenresView() }
            quickAccessPill("Downloads", icon: "arrow.down.circle.fill", color: .teal) { DownloadsView() }
            quickAccessPill("Bookmarks", icon: "bookmark.fill", color: .brown) { BookmarksView() }
            quickAccessPill("Folders", icon: "folder.fill", color: .green) { FolderBrowserView() }
        }
        .padding(.horizontal, 16)
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

    // MARK: - More Section

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More")
                .font(.title3)
                .bold()
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                moreRow("Recently Played", icon: "play.circle.fill", color: .cyan) {
                    AlbumsView(listType: .recent, title: "Recently Played")
                }
                Divider().padding(.leading, 52)
                randomMixRow
            }
            .padding(.horizontal, 16)
        }
    }

    private func moreRow<D: View>(
        _ title: String, icon: String, color: Color,
        @ViewBuilder destination: @escaping () -> D
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
                    .frame(width: 28)

                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Random Mix

    private var randomMixRow: some View {
        Button {
            guard !isLoadingRandomMix else { return }
            Task { await playRandomMix() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dice.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.indigo)
                    .frame(width: 28)

                Text("Random Mix")
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                if isLoadingRandomMix {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(isLoadingRandomMix)
    }

    private func playRandomMix() async {
        isLoadingRandomMix = true
        defer { isLoadingRandomMix = false }
        do {
            let songs = try await appState.subsonicClient.getRandomSongs(size: 50)
            guard let first = songs.first else { return }
            AudioEngine.shared.play(song: first, from: songs)
        } catch {}
    }

    // MARK: - Data Loading

    private func loadSections() async {
        async let recent = appState.subsonicClient.getAlbumList(type: .newest, size: 10)
        async let frequent = appState.subsonicClient.getAlbumList(type: .frequent, size: 10)
        async let random = appState.subsonicClient.getAlbumList(type: .random, size: 10)
        async let starred = appState.subsonicClient.getStarred()

        recentAlbums = (try? await recent) ?? []
        frequentAlbums = (try? await frequent) ?? []
        randomAlbums = (try? await random) ?? []

        // Shuffle starred songs and take a subset for "Rediscover"
        if let result = try? await starred, var songs = result.song, !songs.isEmpty {
            songs.shuffle()
            starredSongs = Array(songs.prefix(15))
        }
    }
}
