import SwiftUI

struct FavoritesView: View {
    @Environment(AppState.self) private var appState
    @State private var starred: Starred2?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if let starred {
                // Starred Artists
                if let artists = starred.artist, !artists.isEmpty {
                    Section("Artists") {
                        ForEach(artists) { artist in
                            NavigationLink {
                                ArtistDetailView(artistId: artist.id)
                            } label: {
                                ArtistRow(artist: artist)
                            }
                            .accessibilityIdentifier("favArtistRow_\(artist.id)")
                        }
                    }
                }

                // Starred Albums
                if let albums = starred.album, !albums.isEmpty {
                    Section("Albums") {
                        ForEach(albums) { album in
                            NavigationLink {
                                AlbumDetailView(albumId: album.id)
                            } label: {
                                AlbumCard(album: album)
                            }
                            .accessibilityIdentifier("favAlbumRow_\(album.id)")
                        }
                    }
                }

                // Starred Songs
                if let songs = starred.song, !songs.isEmpty {
                    Section("Songs") {
                        HStack(spacing: 12) {
                            Button {
                                AudioEngine.shared.play(song: songs[0], from: songs, at: 0)
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.accentColor)
                            .accessibilityIdentifier("favPlayAllButton")

                            Button {
                                let shuffled = songs.shuffled()
                                AudioEngine.shared.play(song: shuffled[0], from: shuffled, at: 0)
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.accentColor)
                            .accessibilityIdentifier("favShuffleButton")
                        }
                        .listRowSeparator(.hidden)

                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            TrackRow(song: song, showTrackNumber: false)
                                .trackContextMenu(song: song, queue: songs, index: index)
                                .accessibilityIdentifier("favSongRow_\(song.id)")
                                .onTapGesture {
                                    AudioEngine.shared.play(song: song, from: songs, at: index)
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Favorites")
        .overlay {
            if isLoading && starred == nil {
                ProgressView("Loading favorites...")
            } else if let error, starred == nil {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadStarred() } }
                        .buttonStyle(.bordered)
                }
            } else if !isLoading && isEmpty {
                ContentUnavailableView {
                    Label("No Favorites", systemImage: "heart")
                } description: {
                    Text("Star songs, albums, and artists to see them here")
                }
            }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                Button { Task { await loadStarred() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        #endif
        .task { await loadStarred() }
        .refreshable { await loadStarred() }
    }

    private var isEmpty: Bool {
        guard let starred else { return true }
        return (starred.artist?.isEmpty ?? true) &&
               (starred.album?.isEmpty ?? true) &&
               (starred.song?.isEmpty ?? true)
    }

    private func loadStarred() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            starred = try await appState.subsonicClient.getStarred()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }
}
