import SwiftData
import SwiftUI

struct PlaylistDetailView: View {
    let playlistId: String

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var playlist: Playlist?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showEditSheet = false
    @State private var isDownloading = false
    @State private var smartPlaylistRules: NSPCriteria?
    @State private var isSmartPlaylist = false
    @State private var isLoadingSmartRules = false
    @State private var didDetectSmartPlaylist = false
    @State private var searchText = ""
    @State private var m3uFileURL: URL?
    @State private var showShareSheet = false
    @State private var selectedSongs = Set<String>()
    @State private var isSelecting = false
    @State private var showBatchAddToPlaylist = false
    @State private var showRemoveOfflineConfirmation = false
    /// Active view mode for smart playlists: songs list or album grid.
    @State private var smartViewMode: SmartPlaylistViewMode = .songs
    @Query private var downloadedSongs: [DownloadedSong]
    #if os(macOS)
    @State private var columnSettings = TrackTableColumnSettings(viewKey: "playlist")
    #endif

    enum SmartPlaylistViewMode: String, CaseIterable {
        case songs = "Songs"
        case albums = "Albums"
    }

    private var filteredSongs: [Song] {
        guard let songs = playlist?.entry else { return [] }
        if searchText.isEmpty { return songs }
        return songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Songs grouped by album for the Albums view. Preserves playlist order within each album.
    private var songsByAlbum: [(albumName: String, albumId: String?, songs: [Song])] {
        var seen: [String: Int] = [:]
        var groups: [(albumName: String, albumId: String?, songs: [Song])] = []
        for song in filteredSongs {
            let key = song.album ?? "Unknown Album"
            if let idx = seen[key] {
                groups[idx].songs.append(song)
            } else {
                seen[key] = groups.count
                groups.append((albumName: key, albumId: song.albumId, songs: [song]))
            }
        }
        return groups
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
                            if isSmartPlaylist {
                                Label("Smart Playlist", systemImage: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(verbatim: "\(playlist.songCount ?? 0) songs")
                            if let duration = playlist.duration {
                                Text("·")
                                Text(formatDuration(duration))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if isSmartPlaylist {
                            Picker("View", selection: $smartViewMode) {
                                ForEach(SmartPlaylistViewMode.allCases, id: \.self) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 200)
                        }

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

                // Songs or Albums view
                if isSmartPlaylist && smartViewMode == .albums {
                    smartAlbumsSection
                } else {
                    Section {
                        #if os(macOS)
                        MacTrackTableView(songs: filteredSongs, settings: columnSettings)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        #else
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
                        .onDelete(perform: isSmartPlaylist ? nil : { offsets in
                            let allSongs = playlist.entry ?? []
                            let filtered = filteredSongs
                            let originalIndices = offsets.compactMap { offset -> Int? in
                                guard offset < filtered.count else { return nil }
                                let songId = filtered[offset].id
                                return allSongs.firstIndex(where: { $0.id == songId })
                            }
                            removeFromPlaylist(at: IndexSet(originalIndices), songs: allSongs)
                        })
                        #endif
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
                            openEditSheet()
                        } label: {
                            if isLoadingSmartRules {
                                Label("Loading…", systemImage: "arrow.clockwise")
                            } else {
                                Label(isSmartPlaylist ? "Edit Smart Playlist" : "Edit Playlist",
                                      systemImage: isSmartPlaylist ? "sparkles" : "pencil")
                            }
                        }
                        .disabled(isLoadingSmartRules)

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
                                Button {
                                    isDownloading = true
                                    DownloadManager.shared.refreshOfflinePlaylist(
                                        playlist: playlist,
                                        songs: songs,
                                        client: appState.subsonicClient
                                    )
                                } label: {
                                    Label("Refresh Download", systemImage: "arrow.triangle.2.circlepath")
                                }
                                Button(role: .destructive) {
                                    showRemoveOfflineConfirmation = true
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
        .alert("Remove Offline Playlist?", isPresented: $showRemoveOfflineConfirmation) {
            Button("Remove", role: .destructive) {
                DownloadManager.shared.removeOfflinePlaylist(playlistId: playlistId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Songs from this download will be deleted unless they're also part of another offline playlist.")
        }
        .sheet(isPresented: $showEditSheet) {
            if let playlist {
                PlaylistEditorView(
                    mode: isSmartPlaylist
                        ? .smartPlaylist(playlistId: playlist.id,
                                         currentName: playlist.name,
                                         existingRules: smartPlaylistRules)
                        : .edit(playlistId: playlist.id, currentName: playlist.name)
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

    @ViewBuilder
    private var smartAlbumsSection: some View {
        ForEach(songsByAlbum, id: \.albumName) { group in
            Section {
                ForEach(Array(group.songs.enumerated()), id: \.element.id) { index, song in
                    TrackRow(song: song, showTrackNumber: true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playFromPlaylist(song: song, songs: group.songs, index: index)
                        }
                        .trackContextMenu(song: song, queue: group.songs, index: index)
                }
            } header: {
                HStack(spacing: 10) {
                    AlbumArtView(coverArtId: group.songs.first?.coverArt, size: 40, cornerRadius: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.albumName)
                            .font(.subheadline)
                            .bold()
                        if let artist = group.songs.first?.albumArtist ?? group.songs.first?.artist {
                            Text(artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(group.songs.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func openEditSheet() {
        if isLoadingSmartRules {
            // Detection still in flight — wait for it
            return
        }
        showEditSheet = true
    }

    /// Detect smart playlist status eagerly when the playlist loads. Runs once per view lifetime.
    private func detectSmartPlaylist() async {
        guard let ndClient = appState.navidromeClient, ndClient.isAvailable else {
            didDetectSmartPlaylist = true
            return
        }
        isLoadingSmartRules = true
        defer { isLoadingSmartRules = false; didDetectSmartPlaylist = true }
        do {
            let playlists = try await ndClient.getPlaylists()
            if let match = playlists.first(where: { $0.id == playlistId }) {
                isSmartPlaylist = match.rules != nil
                smartPlaylistRules = match.rules
            }
        } catch {
            // Detection failed — treat as regular playlist
        }
    }

    private func loadPlaylist() async {
        // Show cached playlist data instantly while fetching fresh
        if playlist == nil {
            playlist = loadCachedPlaylist()
        }
        isLoading = playlist == nil
        error = nil
        defer { isLoading = false }
        do {
            playlist = try await appState.subsonicClient.getPlaylist(id: playlistId)
        } catch {
            if playlist == nil {
                self.error = ErrorPresenter.userMessage(for: error)
            }
        }
        // Run smart playlist detection once (not on every refresh)
        if playlist != nil && !didDetectSmartPlaylist {
            await detectSmartPlaylist()
        }
    }

    private func loadCachedPlaylist() -> Playlist? {
        let pid = playlistId
        var descriptor = FetchDescriptor<CachedPlaylist>(
            predicate: #Predicate { $0.id == pid }
        )
        descriptor.fetchLimit = 1
        guard let cached = try? modelContext.fetch(descriptor).first else { return nil }

        // Resolve entries to songs in a single fetch + dictionary lookup.
        // Previously this did one modelContext.fetch per entry — a 1000-song playlist
        // issued 1000 queries on the main thread.
        let sortedEntries = cached.entries.sorted { $0.order < $1.order }
        let entrySongIds = sortedEntries.map(\.songId)
        let idSet = Set(entrySongIds)
        let songsDesc = FetchDescriptor<CachedSong>(
            predicate: #Predicate<CachedSong> { idSet.contains($0.id) }
        )
        let cachedSongs = (try? modelContext.fetch(songsDesc)) ?? []
        let songMap = Dictionary(uniqueKeysWithValues: cachedSongs.map { ($0.id, $0) })
        let songs: [Song] = sortedEntries.compactMap { entry in
            songMap[entry.songId]?.toSong()
        }

        return Playlist(
            id: cached.id,
            name: cached.name,
            songCount: cached.songCount,
            duration: cached.duration,
            created: nil,
            changed: nil,
            coverArt: cached.coverArtId,
            owner: cached.owner,
            isPublic: cached.isPublic,
            entry: songs.isEmpty ? nil : songs
        )
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
