import SwiftUI

/// Value used to push a Library-home category by value, keeping the stack fully value-based so
/// value-based cells inside the pushed view (e.g. AlbumsView's album cells) resolve and render
/// on top instead of behind the intermediate list.
private enum LibraryHomePanel: Hashable {
    case playlists, artists, albums, songs, genres, downloaded
}

/// Apple Music-style Library tab — a single entry point to Playlists, Artists,
/// Albums, Songs, Genres, and Downloaded, with a Recently Added carousel below.
struct LibraryHomeView: View {
    @Environment(AppState.self) private var appState
    @State private var recentlyAdded: [Album] = []
    @State private var isLoadingRecent = false

    var body: some View {
        List {
            Section {
                categoryRow("Playlists", systemImage: "music.note.list", panel: .playlists)
                categoryRow("Artists", systemImage: "music.mic", panel: .artists)
                categoryRow("Albums", systemImage: "square.stack", panel: .albums)
                categoryRow("Songs", systemImage: "music.note", panel: .songs)
                categoryRow("Genres", systemImage: "guitars", panel: .genres)
                categoryRow("Downloaded", systemImage: "arrow.down.circle", panel: .downloaded)
            }
            .listRowSeparator(.visible)

            if !recentlyAdded.isEmpty {
                Section("Recently Added") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(recentlyAdded.prefix(20)) { album in
                                NavigationLink(value: AlbumNavItem(id: album.id)) {
                                    recentlyAddedCard(album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: LibraryHomePanel.self) { panel in
            switch panel {
            case .playlists: PlaylistsView()
            case .artists: ArtistsView()
            case .albums: AlbumsView(listType: .alphabeticalByName, title: "Albums")
            case .songs: SongsView()
            case .genres: GenresView()
            case .downloaded: DownloadsView()
            }
        }
        .navigationTitle("Library")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .contentMargins(.bottom, 80)
        #endif
        .task { await loadRecentlyAdded() }
    }

    @ViewBuilder
    private func categoryRow(_ title: String, systemImage: String, panel: LibraryHomePanel) -> some View {
        NavigationLink(value: panel) {
            Label(title, systemImage: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .padding(.vertical, 6)
        }
        .accessibilityIdentifier("libraryHomeRow_\(title)")
    }

    @ViewBuilder
    private func recentlyAddedCard(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AlbumArtView(coverArtId: album.coverArt, size: 140, cornerRadius: 10)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            Text(album.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            if let artist = album.artist {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 140)
    }

    private func loadRecentlyAdded() async {
        guard recentlyAdded.isEmpty, !isLoadingRecent else { return }
        isLoadingRecent = true
        defer { isLoadingRecent = false }
        let client = appState.subsonicClient
        if let cached = await client.cachedResponse(for: .getAlbumList2(type: .newest, size: 20), ttl: 3600) {
            recentlyAdded = cached.albumList2?.album ?? []
        }
        if let result = try? await client.getAlbumList(type: .newest, size: 20) {
            recentlyAdded = result
        }
    }
}
