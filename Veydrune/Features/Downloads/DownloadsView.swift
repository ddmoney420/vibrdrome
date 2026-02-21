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
                    ForEach(completedDownloads) { download in
                        DownloadedSongRow(download: download)
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
                }
            }
        }
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

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtView(coverArtId: download.coverArtId, size: 44)

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

// MARK: - Helpers

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
