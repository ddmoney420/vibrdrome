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
                        }
                    }
                }

                // Starred Songs
                if let songs = starred.song, !songs.isEmpty {
                    Section("Songs") {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            TrackRow(song: song, showTrackNumber: false)
                                .trackContextMenu(song: song, queue: songs, index: index)
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
            self.error = error.localizedDescription
        }
    }
}
