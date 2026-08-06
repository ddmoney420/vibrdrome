import PhotosUI
import SwiftData
import SwiftUI

private enum PlaylistViewMode: String {
    case songs, albums
}

struct PlaylistDetailView: View {
    let playlistId: String

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
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
    @State private var showRemoveOfflineConfirmation = false
    @State private var smartCriteria: NSPCriteria?
    @State private var isLoadingSmartRules = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingImage = false
    @State private var isCreatingShare = false
    @AppStorage("playlistDetailViewMode") private var viewModeRaw: String = PlaylistViewMode.songs.rawValue
    @Query private var downloadedSongs: [DownloadedSong]
    #if os(macOS)
    @State private var columnSettings = TrackTableColumnSettings(viewKey: "playlist")
    @State private var showExportConfig = false
    @Query private var allExports: [ExportedPlaylist]
    private var existingExport: ExportedPlaylist? {
        allExports.first { $0.playlistId == playlistId }
    }
    #endif

    private var viewMode: PlaylistViewMode { PlaylistViewMode(rawValue: viewModeRaw) ?? .songs }
    private var isSmartPlaylist: Bool { smartCriteria != nil }

    private var albumsInPlaylist: [Album] {
        guard let songs = playlist?.entry else { return [] }
        var seen = Set<String>()
        var albums: [Album] = []
        for song in songs {
            let albumId = song.albumId ?? song.album ?? song.id
            guard !seen.contains(albumId) else { continue }
            seen.insert(albumId)
            let count = songs.filter { ($0.albumId ?? $0.album ?? $0.id) == albumId }.count
            albums.append(Album(
                id: albumId,
                name: song.album ?? "Unknown Album",
                artist: song.albumArtist ?? song.artist,
                artistId: song.artistId,
                artists: nil, displayArtist: nil,
                coverArt: song.coverArt,
                songCount: count,
                duration: nil, playCount: nil,
                year: song.year,
                genre: song.genre,
                genres: nil,
                starred: nil, played: nil,
                created: nil,
                userRating: nil,
                song: nil,
                replayGain: nil,
                musicBrainzId: nil,
                recordLabels: nil,
                version: nil, releaseTypes: nil, moods: nil, sortName: nil,
                originalReleaseDate: nil, releaseDate: nil,
                isCompilation: nil, explicitStatus: nil, discTitles: nil
            ))
        }
        return albums
    }

    private var filteredSongs: [Song] {
        guard let songs = playlist?.entry else { return [] }
        if searchText.isEmpty { return songs }
        return songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        content
        .navigationTitle(playlist?.name ?? "Playlist")
        .searchable(text: $searchText, prompt: "Search in Playlist")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if playlist != nil {
                ToolbarItem(placement: .automatic) {
                    Picker("View", selection: $viewModeRaw) {
                        Label("Songs", systemImage: "music.note.list").tag(PlaylistViewMode.songs.rawValue)
                        Label("Albums", systemImage: "square.grid.2x2").tag(PlaylistViewMode.albums.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("View mode")
                }
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
                    .opacity(viewMode == .songs ? 1 : 0)
                    .disabled(viewMode == .albums)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label(isSmartPlaylist ? "Edit Smart Playlist" : "Edit Playlist",
                                  systemImage: isSmartPlaylist ? "sparkles" : "pencil")
                        }

                        if appState.navidromeClient?.isAvailable == true {
                            PhotosPicker(
                                selection: $selectedPhotoItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Label("Change Image", systemImage: "photo.badge.arrow.down")
                            }
                            .disabled(isUploadingImage)
                            .onChange(of: selectedPhotoItem) { _, item in
                                guard let item else { return }
                                Task { await uploadPlaylistImage(from: item) }
                            }
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

                            Button {
                                guard !isCreatingShare else { return }
                                let songIds = playlist.entry?.map(\.id) ?? []
                                guard !songIds.isEmpty else { return }
                                isCreatingShare = true
                                Task {
                                    defer { isCreatingShare = false }
                                    do {
                                        let share = try await appState.subsonicClient.createShare(ids: songIds)
                                        #if os(macOS)
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(share.url, forType: .string)
                                        #else
                                        UIPasteboard.general.string = share.url
                                        #endif
                                    } catch {}
                                }
                            } label: {
                                Label(
                                    isCreatingShare ? "Creating Share…" : "Copy Navidrome Share Link",
                                    systemImage: "link"
                                )
                            }
                            .disabled(isCreatingShare)
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

                        #if os(macOS)
                        Divider()
                        if let existing = existingExport {
                            Button {
                                showExportConfig = true
                            } label: {
                                Label("Export Settings…", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                PlaylistExportManager.shared.removeExport(existing)
                            } label: {
                                Label("Remove Export", systemImage: "square.and.arrow.up.slash")
                            }
                        } else {
                            Button {
                                showExportConfig = true
                            } label: {
                                Label("Export Playlist…", systemImage: "square.and.arrow.up")
                            }
                        }
                        #endif
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        #if os(macOS)
        .sheet(isPresented: $showExportConfig) {
            PlaylistExportConfigView(
                playlistId: playlistId,
                playlistName: playlist?.name ?? playlistId,
                existingExport: existingExport
            )
        }
        #endif
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
                if isSmartPlaylist {
                    #if os(macOS)
                    SmartPlaylistEditorView(
                        mode: .edit(playlistId: playlist.id),
                        initialName: playlist.name,
                        initialRules: smartCriteria
                    ) {
                        await loadPlaylist()
                    }
                    .environment(appState)
                    #else
                    PlaylistEditorView(
                        mode: .smartPlaylist(
                            playlistId: playlist.id,
                            currentName: playlist.name,
                            existingRules: smartCriteria
                        )
                    ) {
                        await loadPlaylist()
                    }
                    .environment(appState)
                    #endif
                } else {
                    PlaylistEditorView(
                        mode: .edit(playlistId: playlist.id, currentName: playlist.name)
                    ) {
                        await loadPlaylist()
                    }
                    .environment(appState)
                }
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
        .task { await detectSmartPlaylist() }
        .refreshable { await loadPlaylist() }
    }

    // MARK: - Content containers

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        ScrollView {
            if let playlist {
                VStack(spacing: 0) {
                    playlistHeader(playlist)
                    if viewMode == .albums {
                        albumGrid
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                    } else {
                        MacTrackTableView(songs: filteredSongs, settings: columnSettings, embedsScrollView: false)
                    }
                }
            }
        }
        #else
        if viewMode == .albums, playlist != nil {
            albumGridList
        } else {
            List {
                if let playlist {
                    Section {
                        VStack(spacing: 12) {
                            AlbumArtView(coverArtId: playlist.coverArt, size: 160, cornerRadius: 12)
                                .shadow(radius: 6)

                            HStack(spacing: 6) {
                                Text(playlist.name)
                                    .font(.title3)
                                    .bold()
                                if isSmartPlaylist {
                                    Image(systemName: "sparkles")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 8) {
                                Text(verbatim: "\(playlist.songCount ?? 0) songs")
                                if let duration = playlist.duration {
                                    Text("·")
                                    Text(formatDuration(duration))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            playlistActionButtons(playlist)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 12)
                    }

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
                            let allSongs = playlist.entry ?? []
                            let filtered = filteredSongs
                            let originalIndices = offsets.compactMap { offset -> Int? in
                                guard offset < filtered.count else { return nil }
                                let songId = filtered[offset].id
                                return allSongs.firstIndex(where: { $0.id == songId })
                            }
                            removeFromPlaylist(at: IndexSet(originalIndices), songs: allSongs)
                        }
                    }

                    if isSelecting && !selectedSongs.isEmpty {
                        Section {
                            playlistBatchActionBar(songs: filteredSongs)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .contentMargins(.bottom, 80)
        }
        #endif
    }

    // MARK: - Album grid (iOS)

    #if os(iOS)
    private var albumGridList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let playlist {
                    VStack(spacing: 12) {
                        AlbumArtView(coverArtId: playlist.coverArt, size: 160, cornerRadius: 12)
                            .shadow(radius: 6)
                        HStack(spacing: 6) {
                            Text(playlist.name)
                                .font(.title3)
                                .bold()
                            if isSmartPlaylist {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            Text(verbatim: "\(playlist.songCount ?? 0) songs")
                            if let duration = playlist.duration {
                                Text("·")
                                Text(formatDuration(duration))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        playlistActionButtons(playlist)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                albumGrid
                    .padding(.horizontal, 16)
                    .padding(.bottom, 80)
            }
        }
    }
    #endif

    // MARK: - Album grid (shared)

    private var albumGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 16)],
            spacing: 20
        ) {
            ForEach(albumsInPlaylist) { album in
                NavigationLink {
                    AlbumDetailView(albumId: album.id)
                } label: {
                    AlbumGridCard(album: album, cellWidth: 150)
                }
                .buttonStyle(.plain)
            }
        }
    }

    #if os(macOS)
    @ViewBuilder
    private func playlistHeader(_ playlist: Playlist) -> some View {
        VStack(spacing: 12) {
            AlbumArtView(coverArtId: playlist.coverArt, size: 160, cornerRadius: 12)
                .shadow(radius: 6)

            HStack(spacing: 6) {
                Text(playlist.name)
                    .font(.title3)
                    .bold()
                if isSmartPlaylist {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Text(verbatim: "\(playlist.songCount ?? 0) songs")
                if let duration = playlist.duration {
                    Text("·")
                    Text(formatDuration(duration))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            playlistActionButtons(playlist)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    #endif

    @ViewBuilder
    private func playlistActionButtons(_ playlist: Playlist) -> some View {
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

    private func detectSmartPlaylist() async {
        guard let ndClient = appState.navidromeClient, ndClient.isAvailable else { return }
        isLoadingSmartRules = true
        defer { isLoadingSmartRules = false }
        guard let playlists = try? await ndClient.getPlaylists() else { return }
        if let match = playlists.first(where: { $0.id == playlistId }) {
            smartCriteria = match.rules
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

    // MARK: - Image Upload

    private func uploadPlaylistImage(from item: PhotosPickerItem) async {
        guard let client = appState.navidromeClient else { return }
        isUploadingImage = true
        defer {
            isUploadingImage = false
            selectedPhotoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            try await client.uploadImage(resourceType: "playlist", id: playlistId, imageData: data, mimeType: "image/jpeg")
            await loadPlaylist()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    // MARK: - M3U Export

    private func exportM3U() {
        guard let songs = playlist?.entry, !songs.isEmpty else { return }
        var m3u = "#EXTM3U\n"
        for song in songs {
            let duration = song.duration ?? 0
            let artist = song.displayArtist ?? "Unknown"
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
