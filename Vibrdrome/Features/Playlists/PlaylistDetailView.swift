import SwiftData
import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: String

    @Environment(AppState.self) private var appState
    @State private var playlist: Playlist?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showEditSheet = false
    @State private var isDownloading = false
    @State private var searchText = ""
    @Query private var downloadedSongs: [DownloadedSong]

    private var filteredSongs: [Song] {
        guard let songs = playlist?.entry else { return [] }
        if searchText.isEmpty { return songs }
        return songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if let playlist {
                // Header section
                Section {
                    VStack(spacing: 12) {
                        AlbumArtView(coverArtId: playlist.coverArt, size: 160, cornerRadius: 12)
                            .shadow(radius: 6)

                        Text(playlist.name)
                            .font(.title3)
                            .bold()

                        HStack(spacing: 8) {
                            Text(verbatim: "\(playlist.songCount ?? 0) songs")
                            if let duration = playlist.duration {
                                Text("·")
                                Text(formatDuration(duration))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        // Action buttons
                        HStack(spacing: 16) {
                            Button {
                                if let songs = playlist.entry, let first = songs.first {
                                    AudioEngine.shared.play(song: first, from: songs, at: 0)
                                }
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("playlistPlayButton")
                            .disabled(playlist.entry?.isEmpty ?? true)

                            Button {
                                if var songs = playlist.entry, !songs.isEmpty {
                                    songs.shuffle()
                                    AudioEngine.shared.play(song: songs[0], from: songs, at: 0)
                                }
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("playlistShuffleButton")
                            .disabled(playlist.entry?.isEmpty ?? true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 12)
                }

                // Songs
                Section {
                    ForEach(Array(filteredSongs.enumerated()), id: \.element.id) { index, song in
                        TrackRow(song: song, showTrackNumber: false)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                AudioEngine.shared.play(song: song, from: filteredSongs, at: index)
                            }
                            .trackContextMenu(song: song, queue: filteredSongs, index: index)
                    }
                    .onDelete { offsets in
                        removeFromPlaylist(at: offsets, songs: playlist.entry ?? [])
                    }
                }
            }
        }
        .listStyle(.plain)
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle(playlist?.name ?? "Playlist")
        .searchable(text: $searchText, prompt: "Search in Playlist")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if playlist != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label("Edit Playlist", systemImage: "pencil")
                        }

                        Button {
                            if let songs = playlist?.entry, !songs.isEmpty {
                                for song in songs {
                                    AudioEngine.shared.addToQueue(song)
                                }
                            }
                        } label: {
                            Label("Add All to Queue", systemImage: "text.append")
                        }

                        if let playlist {
                            let shareText = "🎶 \(playlist.name) — \(playlist.songCount ?? 0) songs"
                            ShareLink(item: shareText) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }

                        Divider()

                        if let playlist, let songs = playlist.entry, !songs.isEmpty {
                            let isFullyDownloaded = DownloadManager.shared.isPlaylistDownloaded(playlistId: playlistId)
                            if isFullyDownloaded {
                                Button(role: .destructive) {
                                    DownloadManager.shared.removeOfflinePlaylist(playlistId: playlistId)
                                } label: {
                                    Label("Remove Offline", systemImage: "icloud.slash")
                                }
                            } else {
                                Button {
                                    isDownloading = true
                                    DownloadManager.shared.downloadPlaylist(
                                        playlist: playlist,
                                        songs: songs,
                                        client: appState.subsonicClient
                                    )
                                } label: {
                                    Label("Download Playlist", systemImage: "arrow.down.circle")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let playlist {
                PlaylistEditorView(
                    mode: .edit(playlistId: playlist.id, currentName: playlist.name)
                ) {
                    await loadPlaylist()
                }
                .environment(appState)
            }
        }
        .overlay {
            if isLoading && playlist == nil {
                ProgressView()
            } else if let error, playlist == nil {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadPlaylist() } }
                        .buttonStyle(.bordered)
                }
            }
        }
        .task { await loadPlaylist() }
        .refreshable { await loadPlaylist() }
    }

    private func loadPlaylist() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            playlist = try await appState.subsonicClient.getPlaylist(id: playlistId)
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func removeFromPlaylist(at offsets: IndexSet, songs: [Song]) {
        let indexes = offsets.sorted()
        Task {
            do {
                try await appState.subsonicClient.updatePlaylist(
                    id: playlistId,
                    songIndexesToRemove: indexes
                )
            } catch {
                self.error = ErrorPresenter.userMessage(for: error)
            }
            await loadPlaylist()
        }
    }
}
