import SwiftData
import SwiftUI

struct DownloadsView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \DownloadedSong.downloadedAt, order: .reverse)
    private var downloads: [DownloadedSong]
    @Query(sort: \OfflinePlaylist.cachedAt, order: .reverse)
    private var offlinePlaylists: [OfflinePlaylist]
    @State private var showDeleteConfirmation = false

    private var activeDownloads: [DownloadedSong] {
        downloads.filter { !$0.isComplete }
    }

    private var completedDownloads: [DownloadedSong] {
        downloads.filter { $0.isComplete }
    }

    /// Completed downloads grouped by album, preserving the most-recent-first order
    /// of the underlying query (the first song seen for an album fixes its position).
    private var albumGroups: [(key: String, songs: [DownloadedSong])] {
        var order: [String] = []
        var map: [String: [DownloadedSong]] = [:]
        for download in completedDownloads {
            let key = download.albumName ?? "Unknown Album"
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(download)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    /// Downloaded playlists for the active server that still have at least one
    /// downloaded track present on disk.
    private var downloadedPlaylists: [OfflinePlaylist] {
        let downloadedIds = Set(completedDownloads.map(\.songId))
        return offlinePlaylists.filter { playlist in
            if let serverId = appState.activeServerId, playlist.serverId != serverId {
                return false
            }
            return playlist.songIds.contains { downloadedIds.contains($0) }
        }
    }

    /// Resolve a playlist's downloaded tracks in playlist order.
    private func songs(for playlist: OfflinePlaylist) -> [DownloadedSong] {
        let byId = Dictionary(
            completedDownloads.map { ($0.songId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return playlist.songIds.compactMap { byId[$0] }
    }

    var body: some View {
        List {
            if !activeDownloads.isEmpty {
                Section("Downloading") {
                    ForEach(activeDownloads) { download in
                        DownloadProgressRow(download: download)
                    }
                }
            }

            if completedDownloads.isEmpty {
                Section("Downloaded") {
                    ContentUnavailableView {
                        Label("No Downloads", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Downloaded songs will appear here")
                    }
                }
            } else {
                Section {
                    playAllShuffleButtons(for: completedDownloads.map { $0.toSong() })
                        .listRowSeparator(.hidden)
                }

                if !downloadedPlaylists.isEmpty {
                    Section("Playlists") {
                        ForEach(downloadedPlaylists) { playlist in
                            NavigationLink {
                                DownloadedCollectionView(
                                    title: playlist.playlistName,
                                    coverArtId: playlist.coverArtId,
                                    fallbackSymbol: "music.note.list",
                                    songs: songs(for: playlist)
                                )
                            } label: {
                                DownloadCollectionRow(
                                    title: playlist.playlistName,
                                    subtitle: "\(songs(for: playlist).count) songs",
                                    coverArtId: playlist.coverArtId,
                                    fallbackSymbol: "music.note.list"
                                )
                            }
                        }
                    }
                }

                Section("Albums") {
                    ForEach(albumGroups, id: \.key) { group in
                        NavigationLink {
                            DownloadedCollectionView(
                                title: group.key,
                                coverArtId: group.songs.first?.coverArtId,
                                fallbackSymbol: "square.stack",
                                songs: group.songs
                            )
                        } label: {
                            DownloadCollectionRow(
                                title: group.key,
                                subtitle: albumSubtitle(group.songs),
                                coverArtId: group.songs.first?.coverArtId,
                                fallbackSymbol: "square.stack"
                            )
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Storage Used")
                        Spacer()
                        Text(formatBytes(totalSize(completedDownloads)))
                            .foregroundStyle(.secondary)
                    }

                    Button("Delete All Downloads", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .accessibilityIdentifier("deleteAllDownloadsButton")
                }
            }
        }
        .accessibilityIdentifier("downloadsList")
        #if os(iOS)
            .contentMargins(.bottom, 80)
        #endif
        .navigationTitle("Downloads")
        .alert("Delete All Downloads?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                DownloadManager.shared.deleteAllDownloads()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded songs from this device.")
        }
    }

    private func albumSubtitle(_ songs: [DownloadedSong]) -> String {
        let artists = Set(songs.compactMap(\.artistName))
        let count = songs.count
        let songLabel = count == 1 ? "1 song" : "\(count) songs"
        if artists.count == 1, let artist = artists.first {
            return "\(artist) · \(songLabel)"
        } else if artists.count > 1 {
            return "Various Artists · \(songLabel)"
        }
        return songLabel
    }

    private func totalSize(_ completed: [DownloadedSong]) -> Int64 {
        completed.reduce(0) { $0 + $1.fileSize }
    }
}

// MARK: - Play All / Shuffle

@MainActor @ViewBuilder
func playAllShuffleButtons(for songs: [Song]) -> some View {
    HStack(spacing: 12) {
        Button {
            guard let first = songs.first else { return }
            AudioEngine.shared.play(song: first, from: songs, at: 0)
        } label: {
            Label("Play All", systemImage: "play.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
        .accessibilityIdentifier("downloadsPlayAllButton")

        Button {
            let shuffled = songs.shuffled()
            guard let first = shuffled.first else { return }
            AudioEngine.shared.play(song: first, from: shuffled, at: 0)
        } label: {
            Label("Shuffle", systemImage: "shuffle")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
        .accessibilityIdentifier("downloadsShuffleButton")
    }
}

// MARK: - Downloaded Collection Detail (album or playlist)

struct DownloadedCollectionView: View {
    let title: String
    let coverArtId: String?
    let fallbackSymbol: String
    let songs: [DownloadedSong]

    var body: some View {
        List {
            Section {
                playAllShuffleButtons(for: songs.map { $0.toSong() })
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(songs) { download in
                    DownloadedSongRow(download: download)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let all = songs.map { $0.toSong() }
                            let song = download.toSong()
                            let index = all.firstIndex(where: { $0.id == song.id }) ?? 0
                            AudioEngine.shared.play(song: song, from: all, at: index)
                        }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        DownloadManager.shared.deleteDownload(songId: songs[offset].songId)
                    }
                }
            }
        }
        #if os(iOS)
            .contentMargins(.bottom, 80)
        #endif
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Collection Row (album / playlist)

private struct DownloadCollectionRow: View {
    let title: String
    let subtitle: String
    let coverArtId: String?
    let fallbackSymbol: String

    var body: some View {
        HStack(spacing: 12) {
            if let coverArtId {
                AlbumArtView(coverArtId: coverArtId, size: 48)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: fallbackSymbol)
                            .foregroundStyle(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Downloaded Song Row

private struct DownloadedSongRow: View {
    let download: DownloadedSong

    @Environment(AppState.self) private var appState
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private
        var showAlbumArtInLists: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if showAlbumArtInLists {
                AlbumArtView(coverArtId: download.coverArtId, size: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(download.songTitle)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let artist = download.artistName {
                        Text(artist)
                    }
                    if download.artistName != nil, download.albumName != nil {
                        Text("·")
                    }
                    if let album = download.albumName {
                        Text(album)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if download.category == AudioEngine.predownloadedCategory
                && !UserDefaults.standard.bool(
                    forKey: UserDefaultsKeys.keepSongsInCacheAfterPlayback
                )
            {
                // Delete the file if X minutes * 60 seconds old
                if download.lastAccessedAt != nil
                    && download.lastAccessedAt!.timeIntervalSinceNow
                        < (-60.0 * AudioEngine.predownloadedCacheTimeMins)
                {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(
                            systemName:
                                "arrow.down.app.dashed.trianglebadge.exclamationmark"
                        )
                        .symbolRenderingMode(.multicolor)
                        .font(.caption)
                        .foregroundStyle(.red)

                        Text(formatBytes(download.fileSize))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(
                            systemName:
                                "arrow.down.app.dashed.trianglebadge.exclamationmark"
                        )
                        .symbolRenderingMode(.multicolor)
                        .font(.caption)
                        .foregroundStyle(.green)

                        Text(formatBytes(download.fileSize))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                }

            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)

                    Text(formatBytes(download.fileSize))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Download Progress Row

struct DownloadProgressRow: View {
    let download: DownloadedSong

    private var progress: Double {
        DownloadProgress.shared.progress(for: download.songId)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(download.songTitle)
                    .font(.body)
                    .lineLimit(1)

                if let artist = download.artistName {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ProgressView(value: progress)
                    .tint(Color.accentColor)
            }

            Button {
                DownloadManager.shared.cancelDownload(songId: download.songId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
