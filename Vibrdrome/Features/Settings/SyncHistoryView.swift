import SwiftData
import SwiftUI

struct SyncHistoryView: View {
    @Query(sort: \SyncHistory.syncDate, order: .reverse) private var history: [SyncHistory]

    var body: some View {
        List {
            if history.isEmpty {
                ContentUnavailableView(
                    "No Sync History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Sync history will appear here after your first library sync.")
                )
            } else {
                ForEach(history) { entry in
                    SyncHistoryRow(entry: entry)
                }
            }
        }
        .navigationTitle("Sync History")
    }
}

private struct SyncHistoryRow: View {
    let entry: SyncHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(entry.succeeded ? .green : .red)
                    .font(.caption)

                Text(entry.syncType.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(entry.syncDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entry.succeeded {
                HStack(spacing: 12) {
                    if entry.totalChanges > 0 {
                        statsLabel(value: entry.albumsAdded + entry.artistsAdded + entry.songsAdded,
                                   label: "added", color: .green)
                        statsLabel(value: entry.albumsUpdated + entry.artistsUpdated + entry.songsUpdated,
                                   label: "updated", color: .orange)
                        statsLabel(value: entry.albumsRemoved + entry.artistsRemoved + entry.songsRemoved,
                                   label: "removed", color: .red)
                    } else {
                        Text("No changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(String(format: "%.1fs", entry.durationSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if entry.totalChanges > 0 {
                    HStack(spacing: 8) {
                        if entry.albumsAdded + entry.albumsUpdated + entry.albumsRemoved > 0 {
                            Text("\(entry.albumsAdded + entry.albumsUpdated + entry.albumsRemoved) albums")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if entry.artistsAdded + entry.artistsUpdated + entry.artistsRemoved > 0 {
                            Text("\(entry.artistsAdded + entry.artistsUpdated + entry.artistsRemoved) artists")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if entry.songsAdded + entry.songsUpdated + entry.songsRemoved > 0 {
                            Text("\(entry.songsAdded + entry.songsUpdated + entry.songsRemoved) songs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if entry.playlistsSynced > 0 {
                            Text("\(entry.playlistsSynced) playlists")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if entry.conflictsDetected > 0 {
                    Text("\(entry.conflictsResolved)/\(entry.conflictsDetected) conflicts resolved")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else if let error = entry.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statsLabel(value: Int, label: String, color: Color) -> some View {
        if value > 0 {
            Text("\(value) \(label)")
                .font(.caption)
                .foregroundStyle(color)
        }
    }
}
