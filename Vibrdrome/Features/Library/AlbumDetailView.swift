import SwiftUI

struct AlbumDetailView: View {
    let albumId: String

    @Environment(AppState.self) private var appState
    @State private var album: Album?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isStarred = false
    @State private var similarAlbums: [Album] = []

    var body: some View {
        ScrollView {
            if let album {
                VStack(spacing: 0) {
                    // Header with album art
                    albumHeader(album)

                    // Action buttons
                    actionButtons(album)

                    // Song list with disc separators
                    let songs = album.song ?? []
                    let discs = Set(songs.compactMap(\.discNumber)).sorted()
                    let hasMultipleDiscs = discs.count > 1

                    LazyVStack(spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            // Disc separator
                            if hasMultipleDiscs, let disc = song.discNumber,
                               index == songs.firstIndex(where: { $0.discNumber == disc }) {
                                HStack {
                                    Image(systemName: "opticaldisc")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("Disc \(disc)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                            }

                            TrackRow(song: song, showTrackNumber: true)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    AudioEngine.shared.play(song: song, from: songs, at: index)
                                }
                                .accessibilityIdentifier("trackRow_\(index)")
                                .trackContextMenu(song: song, queue: songs, index: index)
                            Divider()
                                .padding(.leading, 56)
                        }
                    }

                    // Album info footer
                    albumFooter(album)

                    // Similar albums
                    similarAlbumsSection
                }
                #if os(iOS)
                .padding(.bottom, 80)
                #endif
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
        #if os(macOS)
        albumHeaderMacOS(album)
        #else
        albumHeaderIOS(album)
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private func albumHeaderMacOS(_ album: Album) -> some View {
        HStack(alignment: .top, spacing: 20) {
            AlbumArtView(coverArtId: album.coverArt, size: 200, cornerRadius: 12)
                .shadow(radius: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(album.name)
                    .font(.title2)
                    .bold()

                if let artist = album.artist {
                    Text(artist)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                albumMetadataRow(album)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    #else
    @ViewBuilder
    private func albumHeaderIOS(_ album: Album) -> some View {
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

            albumMetadataRow(album)
        }
        .padding(.horizontal, 20)
    }
    #endif

    @ViewBuilder
    private func albumMetadataRow(_ album: Album) -> some View {
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

    @ViewBuilder
    private func actionButtons(_ album: Album) -> some View {
        VStack(spacing: 12) {
            playShuffleRow(album)
            secondaryActionsRow(album)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func playShuffleRow(_ album: Album) -> some View {
        HStack(spacing: 12) {
            Button {
                if let songs = album.song, let first = songs.first {
                    AudioEngine.shared.play(song: first, from: songs, at: 0)
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(album.song?.isEmpty ?? true)

            Button {
                if var songs = album.song, !songs.isEmpty {
                    songs.shuffle()
                    AudioEngine.shared.play(song: songs[0], from: songs, at: 0)
                }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(album.song?.isEmpty ?? true)
        }
    }

    @ViewBuilder
    private func secondaryActionsRow(_ album: Album) -> some View {
        HStack(spacing: 24) {
            Button {
                if let songs = album.song {
                    DownloadManager.shared.downloadAlbum(
                        songs: songs,
                        client: appState.subsonicClient
                    )
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
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
                    .font(.title3)
                    .foregroundStyle(isStarred ? .pink : .secondary)
            }
        }
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

    @ViewBuilder
    private var similarAlbumsSection: some View {
        if !similarAlbums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Similar Albums")
                    .font(.title3)
                    .bold()
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(similarAlbums) { similar in
                            NavigationLink {
                                AlbumDetailView(albumId: similar.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    AlbumArtView(coverArtId: similar.coverArt,
                                                 size: Theme.albumCardSize, cornerRadius: 10)
                                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                                    Text(similar.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(similar.artist ?? "")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: Theme.albumCardSize)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
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
            // Load similar albums from first song
            if let firstSong = album?.song?.first {
                let similar = try await appState.subsonicClient.getSimilarSongs(id: firstSong.id, count: 20)
                let albumIds = Set(similar.compactMap(\.albumId)).subtracting([albumId])
                var albums: [Album] = []
                var seen = Set<String>()
                for song in similar {
                    if let aid = song.albumId, !seen.contains(aid), aid != albumId {
                        seen.insert(aid)
                        if let a = try? await appState.subsonicClient.getAlbum(id: aid) {
                            albums.append(a)
                            if albums.count >= 6 { break }
                        }
                    }
                }
                similarAlbums = albums
            }
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }
}
