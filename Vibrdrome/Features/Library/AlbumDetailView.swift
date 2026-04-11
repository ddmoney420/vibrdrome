import SwiftUI

struct AlbumDetailView: View {
    let albumId: String

    @Environment(AppState.self) private var appState
    @State private var album: Album?
    @State private var isLoading = true
    @State private var error: String?
    @State private var similarAlbums: [Album] = []
    @State private var selectedSongs = Set<String>()
    @State private var isSelecting = false
    @State private var showAddToPlaylist = false

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

                            HStack(spacing: 0) {
                                if isSelecting {
                                    Button {
                                        toggleSelection(song.id)
                                    } label: {
                                        Image(systemName: selectedSongs.contains(song.id)
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedSongs.contains(song.id)
                                                             ? Color.accentColor : .secondary)
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.leading, 16)
                                    .padding(.trailing, 4)
                                }

                                TrackRow(song: song, showTrackNumber: true)
                                    .padding(.horizontal, isSelecting ? 8 : 16)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isSelecting {
                                            toggleSelection(song.id)
                                        } else {
                                            AudioEngine.shared.play(song: song, from: songs, at: index)
                                        }
                                    }
                                    .accessibilityIdentifier("trackRow_\(index)")
                                    .trackContextMenu(song: song, queue: songs, index: index)
                            }
                            Divider()
                                .padding(.leading, isSelecting ? 72 : 56)
                        }
                    }

                    // Batch action bar
                    if isSelecting && !selectedSongs.isEmpty {
                        batchActionBar(songs: songs)
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
        .coordinateSpace(name: "albumScroll")
        .navigationTitle(album?.name ?? "Album")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelecting.toggle()
                        if !isSelecting { selectedSongs.removeAll() }
                    }
                } label: {
                    Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .accessibilityLabel(isSelecting ? "Done Selecting" : "Select Songs")
                .accessibilityIdentifier("albumSelectButton")
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistView(songIds: Array(selectedSongs))
                .environment(appState)
        }
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
                    if let artistId = album.artistId {
                        Button {
                            appState.pendingNavigation = .artist(id: artistId)
                        } label: {
                            Text(artist)
                                .font(.body)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(artist)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
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
        GeometryReader { geo in
            let minY = geo.frame(in: .named("albumScroll")).minY
            let height: CGFloat = 320
            let parallaxOffset = minY > 0 ? -minY / 2 : 0
            let scale = minY > 0 ? 1 + minY / 500 : 1
            let opacity = minY < -100 ? max(0, 1 + (minY + 100) / 150) : 1.0

            ZStack {
                AlbumArtView(coverArtId: album.coverArt, size: height, cornerRadius: 0)
                    .frame(width: geo.size.width, height: height)
                    .clipped()
                    .scaleEffect(scale)
                    .offset(y: parallaxOffset)
                    .opacity(opacity)

                // Gradient fade at bottom
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color(.systemBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                }
            }
            .frame(width: geo.size.width, height: height)
        }
        .frame(height: 320)

        // Album info below art
        VStack(spacing: 6) {
            Text(album.name)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)

            if let artist = album.artist {
                if let artistId = album.artistId {
                    Button {
                        appState.pendingNavigation = .artist(id: artistId)
                    } label: {
                        Text(artist)
                            .font(.body)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(artist)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            albumMetadataRow(album)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
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
            if albumHasLossless(album) {
                Text("·")
                Image(systemName: "waveform")
                Text("Lossless")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func albumHasLossless(_ album: Album) -> Bool {
        let losslessFormats: Set<String> = ["flac", "alac", "wav", "aiff"]
        return album.song?.contains { song in
            guard let suffix = song.suffix else { return false }
            return losslessFormats.contains(suffix.lowercased())
        } ?? false
    }

    @ViewBuilder
    private func actionButtons(_ album: Album) -> some View {
        #if os(iOS)
        circularActionButtons(album)
        #else
        macOSActionButtons(album)
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private func circularActionButtons(_ album: Album) -> some View {
        HStack(spacing: 16) {
            // Shuffle
            Button {
                if var songs = album.song, !songs.isEmpty {
                    Haptics.medium()
                    songs.shuffle()
                    AudioEngine.shared.play(song: songs[0], from: songs, at: 0)
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .modifier(GlassEffectCircleModifier())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("albumShuffleButton")

            // Play pill
            Button {
                if let songs = album.song, let first = songs.first {
                    Haptics.medium()
                    AudioEngine.shared.play(song: first, from: songs, at: 0)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Play")
                        .fontWeight(.semibold)
                }
                .font(.body)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("albumPlayButton")

            // Download
            Button {
                if let songs = album.song {
                    Haptics.light()
                    DownloadManager.shared.downloadAlbum(songs: songs, client: appState.subsonicClient)
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .modifier(GlassEffectCircleModifier())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("albumDownloadButton")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    #endif

    #if os(macOS)
    @ViewBuilder
    private func macOSActionButtons(_ album: Album) -> some View {
        HStack(spacing: 12) {
            Button {
                if let songs = album.song, let first = songs.first {
                    AudioEngine.shared.play(song: first, from: songs, at: 0)
                }
            } label: {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
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
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(album.song?.isEmpty ?? true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    #endif

    @ViewBuilder
    private func albumFooter(_ album: Album) -> some View {
        if let duration = album.duration {
            VStack(spacing: 4) {
                Divider()
                Text(verbatim: "\(album.songCount ?? 0) songs, \(formatDuration(duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func toggleSelection(_ songId: String) {
        if selectedSongs.contains(songId) {
            selectedSongs.remove(songId)
        } else {
            selectedSongs.insert(songId)
        }
    }

    @ViewBuilder
    private func batchActionBar(songs: [Song]) -> some View {
        BatchActionBar(
            selectedSongIds: selectedSongs,
            songs: songs,
            onAddToPlaylist: { showAddToPlaylist = true }
        )
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func loadAlbum() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            album = try await appState.subsonicClient.getAlbum(id: albumId)
            // Load similar albums from first song
            if let firstSong = album?.song?.first {
                let similar = try await appState.subsonicClient.getSimilarSongs(id: firstSong.id, count: 20)
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
