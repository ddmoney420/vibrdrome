import SwiftUI

struct ArtistDetailView: View {
    let artistId: String

    @Environment(AppState.self) private var appState
    @State private var artist: Artist?
    @State private var topSongs: [Song] = []
    @State private var similarArtists: [Artist] = []
    @State private var biography: String?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showFullBio = false
    @State private var isStarred = false

    var body: some View {
        List {
            // Top Songs section
            if !topSongs.isEmpty {
                Section {
                    ForEach(Array(topSongs.enumerated()), id: \.element.id) { index, song in
                        TrackRow(song: song, showTrackNumber: false)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                AudioEngine.shared.play(song: song, from: topSongs, at: index)
                            }
                            .trackContextMenu(song: song, queue: topSongs, index: index)
                    }
                } header: {
                    Text("Top Tracks")
                }
            }

            // Biography section
            if let biography, !biography.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cleanBiography(biography))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(showFullBio ? nil : 4)

                        if biography.count > 200 {
                            Button {
                                withAnimation { showFullBio.toggle() }
                            } label: {
                                Text(showFullBio ? "Show Less" : "Read More")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                } header: {
                    Text("About")
                }
            }

            // Albums section
            if let albums = artist?.album, !albums.isEmpty {
                Section {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(albumId: album.id)
                        } label: {
                            AlbumCard(album: album)
                        }
                        .accessibilityIdentifier("artistAlbumRow_\(album.id)")
                        .albumGetInfoContextMenu(album: album)
                    }
                } header: {
                    Text("Albums (\(albums.count))")
                }
            }

            // Similar Artists section
            if !similarArtists.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(similarArtists) { similar in
                                NavigationLink {
                                    ArtistDetailView(artistId: similar.id)
                                } label: {
                                    VStack(spacing: 8) {
                                        AlbumArtView(
                                            coverArtId: similar.coverArt,
                                            size: 80,
                                            cornerRadius: 40
                                        )
                                        Text(similar.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(width: 88)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("similarArtist_\(similar.id)")
                                .artistGetInfoContextMenu(artist: similar)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Similar Artists")
                }
            }
        }
        .listStyle(.plain)
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle(artist?.name ?? "Artist")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .overlay {
            if isLoading && artist == nil {
                ProgressView()
            } else if let error, artist == nil {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadArtist() } }
                        .buttonStyle(.bordered)
                }
            } else if artist != nil && (artist?.album?.isEmpty ?? true) && topSongs.isEmpty {
                ContentUnavailableView {
                    Label("No Albums", systemImage: "square.stack")
                } description: {
                    Text("This artist has no albums")
                }
            }
        }
        .toolbar {
            if artist != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        toggleArtistStar()
                    } label: {
                        Image(systemName: isStarred ? "heart.fill" : "heart")
                            .foregroundStyle(isStarred ? Color.pink : Color.accentColor)
                    }
                    .accessibilityLabel(isStarred ? "Unfavorite Artist" : "Favorite Artist")
                    .accessibilityIdentifier("artistFavoriteButton")
                }
            }
            if let artist {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        AudioEngine.shared.startRadio(artistName: artist.name)
                    } label: {
                        Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .accessibilityIdentifier("startRadioButton")
                }
            }
        }
        .task { await loadArtist() }
        .refreshable { await loadArtist() }
    }

    private func loadArtist() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let loadedArtist = try await appState.subsonicClient.getArtist(id: artistId)
            artist = loadedArtist
            isStarred = loadedArtist.starred != nil
            // Load top songs and similar artists in parallel
            async let topSongsResult = appState.subsonicClient.getTopSongs(
                artist: loadedArtist.name, count: 10
            )
            async let artistInfoResult = appState.subsonicClient.getArtistInfo(id: artistId)
            topSongs = try await topSongsResult
            let info = try? await artistInfoResult
            similarArtists = info?.similarArtist ?? []
            biography = info?.biography
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    /// Strip HTML tags from biography text (Last.fm often returns HTML)
    private func cleanBiography(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggleArtistStar() {
        let wasStarred = isStarred
        isStarred.toggle()
        #if os(iOS)
        Haptics.light()
        #endif
        Task {
            do {
                if wasStarred {
                    try await OfflineActionQueue.shared.unstar(artistId: artistId)
                } else {
                    try await OfflineActionQueue.shared.star(artistId: artistId)
                }
            } catch {
                isStarred = wasStarred
            }
        }
    }
}
