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
    @State private var m3uFileURL: URL?
    @State private var showShareSheet = false
    @State private var selectedSongs = Set<String>()
    @State private var isSelecting = false
    @State private var showBatchAddToPlaylist = false
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
                                    AudioEngine.shared.playingFromContext = "Playlist: \(playlist.name)"
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
                                    AudioEngine.shared.playingFromContext = "Playlist: \(playlist.name)"
                                }
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("playlistShuffleButton")
                            .disabled(playlist.entry?.isEmpty ?? true)

                            Menu {
                                Button {
                                    if let songs = playlist.entry, !songs.isEmpty {
                                        AudioEngine.shared.addToQueueNext(songs)
                                    }
                                } label: {
                                    Label("Play Next", systemImage: "text.insert")
                                }
                                Button {
                                    if let songs = playlist.entry, !songs.isEmpty {
                                        AudioEngine.shared.addToQueue(songs)
                                    }
                                } label: {
                                    Label("Add to Queue", systemImage: "text.append")
                                }
                            } label: {
                                Label("More", systemImage: "ellipsis.circle")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("playlistMoreButton")
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
                                .padding(.trailing, 8)
                            }

                            TrackRow(song: song, showTrackNumber: false)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isSelecting {
                                        toggleSelection(song.id)
                                    } else {
                                        playFromPlaylist(song: song, songs: filteredSongs, index: index)
                                    }
                                }
                                .trackContextMenu(song: song, queue: filteredSongs, index: index)
                        }
                    }
                    .onDelete { offsets in
                        // Map filtered indices to original playlist indices
                        let allSongs = playlist.entry ?? []
                        let filtered = filteredSongs
                        let originalIndices = offsets.compactMap { offset -> Int? in
                            guard offset < filtered.count else { return nil }
                            let songId = filtered[offset].id
                            return allSongs.firstIndex(where: { $0.id == songId })
                        }
                        removeFromPlaylist(
                            at: IndexSet(originalIndices), songs: allSongs
                        )
                    }
                }

                // Batch action bar
                if isSelecting && !selectedSongs.isEmpty {
                    Section {
                        playlistBatchActionBar(songs: filteredSongs)
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
                ToolbarItem(placement: .automatic) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelecting.toggle()
                            if !isSelecting { selectedSongs.removeAll() }
                        }
                    } label: {
                        Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .accessibilityLabel(isSelecting ? "Done Selecting" : "Select Songs")
                    .accessibilityIdentifier("playlistSelectButton")
                }
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
                            let shareText = "🎶 \(playlist.name) — \(playlist.songCount ?? 0) songs\nvibrdrome://playlist/\(playlist.id)"
                            ShareLink(item: shareText) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }

                        Button {
                            exportM3U()
                        } label: {
                            Label("Export as M3U", systemImage: "doc.text")
                        }
                        .disabled(playlist?.entry?.isEmpty ?? true)

                        Button {
                            guard let playlist else { return }
                            let newPublic = !(playlist.isPublic ?? false)
                            Task {
                                do {
                                    try await appState.subsonicClient.updatePlaylist(
                                        id: playlist.id, isPublic: newPublic)
                                    await loadPlaylist()
                                } catch {
                                    self.error = ErrorPresenter.userMessage(for: error)
                                }
                            }
                        } label: {
                            if playlist?.isPublic == true {
                                Label("Make Private", systemImage: "lock")
                            } else {
                                Label("Make Public", systemImage: "globe")
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
        .sheet(isPresented: $showBatchAddToPlaylist) {
            AddToPlaylistView(songIds: Array(selectedSongs))
                .environment(appState)
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
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            if let m3uFileURL {
                PlaylistShareSheet(activityItems: [m3uFileURL])
            }
        }
        #endif
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

    private func toggleSelection(_ songId: String) {
        if selectedSongs.contains(songId) {
            selectedSongs.remove(songId)
        } else {
            selectedSongs.insert(songId)
        }
    }

    @ViewBuilder
    private func playlistBatchActionBar(songs: [Song]) -> some View {
        BatchActionBar(
            selectedSongIds: selectedSongs,
            songs: songs,
            onAddToPlaylist: { showBatchAddToPlaylist = true }
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func playFromPlaylist(song: Song, songs: [Song], index: Int) {
        AudioEngine.shared.play(song: song, from: songs, at: index)
        AudioEngine.shared.playingFromContext = "Playlist: \(playlist?.name ?? "")"
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

    // MARK: - M3U Export

    private func exportM3U() {
        guard let songs = playlist?.entry, !songs.isEmpty else { return }
        var m3u = "#EXTM3U\n"
        for song in songs {
            let duration = song.duration ?? 0
            let artist = song.artist ?? "Unknown"
            m3u += "#EXTINF:\(duration),\(artist) - \(song.title)\n"
            let url = appState.subsonicClient.streamURL(id: song.id)
            m3u += "\(url.absoluteString)\n"
        }
        let fileName = (playlist?.name ?? "playlist")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName).m3u")
        do {
            try m3u.write(to: tempURL, atomically: true, encoding: .utf8)
            m3uFileURL = tempURL
            showShareSheet = true
        } catch {
            self.error = "Failed to export M3U: \(error.localizedDescription)"
        }
    }
}

// MARK: - Share Sheet (iOS)

#if os(iOS)
import UIKit

private struct PlaylistShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
