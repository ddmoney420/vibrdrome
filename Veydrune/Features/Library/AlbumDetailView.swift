import SwiftUI

struct AlbumDetailView: View {
    let albumId: String

    @Environment(AppState.self) private var appState
    @State private var album: Album?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isStarred = false

    var body: some View {
        ScrollView {
            if let album {
                VStack(spacing: 0) {
                    // Header with album art
                    albumHeader(album)

                    // Action buttons
                    actionButtons(album)

                    // Song list
                    let songs = album.song ?? []
                    LazyVStack(spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            TrackRow(song: song, showTrackNumber: true)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    AudioEngine.shared.play(song: song, from: songs, at: index)
                                }
                                .trackContextMenu(song: song, queue: songs, index: index)
                            Divider()
                                .padding(.leading, 56)
                        }
                    }

                    // Album info footer
                    albumFooter(album)
                }
            }
        }
        .navigationTitle(album?.name ?? "Album")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if isLoading && album == nil {
                ProgressView()
            } else if let error, album == nil {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadAlbum() } }
                        .buttonStyle(.bordered)
                }
            }
        }
        .task { await loadAlbum() }
    }

    @ViewBuilder
    private func albumHeader(_ album: Album) -> some View {
        VStack(spacing: 12) {
            AlbumArtView(coverArtId: album.coverArt, size: 240, cornerRadius: 12)
                .shadow(radius: 8)
                .padding(.top, 20)

            Text(album.name)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)

            if let artist = album.artist {
                Text(artist)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let year = album.year {
                    Text(verbatim: "\(year)")
                }
                if let genre = album.genre {
                    Text("·")
                    Text(genre)
                }
                if let count = album.songCount {
                    Text("·")
                    Text(verbatim: "\(count) songs")
                }
                if let duration = album.duration {
                    Text("·")
                    Text(formatDuration(duration))
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func actionButtons(_ album: Album) -> some View {
        HStack(spacing: 20) {
            Button {
                if let songs = album.song, let first = songs.first {
                    AudioEngine.shared.play(song: first, from: songs, at: 0)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(album.song?.isEmpty ?? true)

            Button {
                if var songs = album.song, !songs.isEmpty {
                    songs.shuffle()
                    AudioEngine.shared.play(song: songs[0], from: songs, at: 0)
                }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(.bordered)
            .disabled(album.song?.isEmpty ?? true)

            // Download album
            Button {
                if let songs = album.song {
                    DownloadManager.shared.downloadAlbum(
                        songs: songs,
                        client: appState.subsonicClient
                    )
                }
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .disabled(album.song?.isEmpty ?? true)

            Spacer()

            Button {
                let wasStarred = isStarred
                isStarred = !wasStarred
                Task {
                    do {
                        if wasStarred {
                            try await appState.subsonicClient.unstar(albumId: albumId)
                        } else {
                            try await appState.subsonicClient.star(albumId: albumId)
                        }
                    } catch {
                        isStarred = wasStarred
                    }
                }
            } label: {
                Image(systemName: isStarred ? "heart.fill" : "heart")
                    .foregroundStyle(isStarred ? .pink : .secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func albumFooter(_ album: Album) -> some View {
        if let duration = album.duration {
            VStack(spacing: 4) {
                Divider()
                Text(verbatim: "\(album.songCount ?? 0) songs, \(formatDuration(duration))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
            }
        }
    }

    private func loadAlbum() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            album = try await appState.subsonicClient.getAlbum(id: albumId)
            isStarred = album?.starred != nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
