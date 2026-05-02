import SwiftData
import SwiftUI

struct DownloadsView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \DownloadedSong.downloadedAt, order: .reverse)
    private var downloads: [DownloadedSong]
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            let activeDownloads = downloads.filter { !$0.isComplete }
            let completedDownloads = downloads.filter { $0.isComplete }

            if !activeDownloads.isEmpty {
                Section("Downloading") {
                    ForEach(activeDownloads) { download in
                        DownloadProgressRow(download: download)
                    }
                }
            }

            Section("Downloaded (\(completedDownloads.count) songs)") {
                if completedDownloads.isEmpty {
                    ContentUnavailableView {
                        Label("No Downloads", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Downloaded songs will appear here")
                    }
                } else {
                    let songs = completedDownloads.map { $0.toSong() }
                    if !songs.isEmpty {
                        HStack(spacing: 12) {
                            Button {
                                AudioEngine.shared.play(song: songs[0], from: songs, at: 0)
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
                                AudioEngine.shared.play(song: shuffled[0], from: shuffled, at: 0)
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
                        .listRowSeparator(.hidden)
                    }

                    ForEach(completedDownloads) { download in
                        DownloadedSongRow(download: download)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let allSongs = completedDownloads.map { $0.toSong() }
                                let song = download.toSong()
                                let playIndex = allSongs.firstIndex(where: { $0.id == song.id }) ?? 0
                                AudioEngine.shared.play(song: song, from: allSongs, at: playIndex)
                            }
                    }
                    .onDelete { offsets in
                        deleteDownloads(completedDownloads, at: offsets)
                    }
                }
            }

            if !completedDownloads.isEmpty {
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

    private func totalSize(_ completed: [DownloadedSong]) -> Int64 {
        completed.reduce(0) { $0 + $1.fileSize }
    }

    private func deleteDownloads(_ completed: [DownloadedSong], at offsets: IndexSet) {
        for offset in offsets {
            let download = completed[offset]
            DownloadManager.shared.deleteDownload(songId: download.songId)
        }
    }
}

// MARK: - Downloaded Song Row

private struct DownloadedSongRow: View {
    let download: DownloadedSong

    @Environment(AppState.self) private var appState
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private var showAlbumArtInLists: Bool = true

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

            if download.category == AudioEngine.predownloadedCategory &&
                !UserDefaults.standard.bool(forKey: UserDefaultsKeys.keepSongsInCacheAfterPlayback) {
                // Delete the file if X minutes * 60 seconds old
                if download.lastAccessedAt != nil &&
                    download.lastAccessedAt!.timeIntervalSinceNow < (-60.0 * AudioEngine.predownloadedCacheTimeMins) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: "arrow.down.app.dashed.trianglebadge.exclamationmark")
                            .symbolRenderingMode(.multicolor)
                            .font(.caption)
                            .foregroundStyle(.red)

                        Text(formatBytes(download.fileSize))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: "arrow.down.app.dashed.trianglebadge.exclamationmark")
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
