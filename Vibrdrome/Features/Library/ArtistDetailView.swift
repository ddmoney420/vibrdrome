import SwiftUI

struct ArtistDetailView: View {
    let artistId: String

    @Environment(AppState.self) private var appState
    @State private var artist: Artist?
    @State private var topSongs: [Song] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showAllTopSongs = false

    var body: some View {
        List {
            // Top Songs section
            if !topSongs.isEmpty {
                Section {
                    let displayed = showAllTopSongs ? topSongs : Array(topSongs.prefix(5))
                    ForEach(Array(displayed.enumerated()), id: \.element.id) { index, song in
                        TrackRow(song: song, showTrackNumber: false)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                AudioEngine.shared.play(song: song, from: topSongs, at: index)
                            }
                            .trackContextMenu(song: song, queue: topSongs, index: index)
                    }

                    if topSongs.count > 5 {
                        Button {
                            withAnimation { showAllTopSongs.toggle() }
                        } label: {
                            Text(showAllTopSongs ? "Show Less" : "See All \(topSongs.count) Songs")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                } header: {
                    Text("Top Songs")
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
                    }
                } header: {
                    Text("Albums (\(albums.count))")
                }
            }
        }
        .listStyle(.plain)
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
            // Load top songs
            topSongs = try await appState.subsonicClient.getTopSongs(
                artist: loadedArtist.name, count: 20
            )
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }
}
