#if os(macOS)
import SwiftUI
import SwiftData

struct PlaylistExportView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \ExportedPlaylist.playlistName) private var exports: [ExportedPlaylist]
    @StateObject private var manager = PlaylistExportManager.shared
    @State private var editingExport: ExportedPlaylist?

    var body: some View {
        Group {
            if exports.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(exports) { export in
                        ExportedPlaylistRow(
                            export: export,
                            isSyncing: manager.syncingPlaylistIds.contains(export.compositeKey),
                            onSync: { Task { await manager.sync(export: export, client: appState.subsonicClient) } },
                            onEdit: { editingExport = export },
                            onOpenInFinder: { openInFinder(export: export) },
                            onRemove: { manager.removeExport(export) }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Playlist Export")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await manager.syncAllActive(client: appState.subsonicClient) }
                } label: {
                    Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(exports.filter(\.isActive).isEmpty)
            }
        }
        .sheet(item: $editingExport) { export in
            PlaylistExportConfigView(
                playlistId: export.playlistId,
                playlistName: export.playlistName,
                existingExport: export
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Exported Playlists",
            systemImage: "square.and.arrow.up",
            description: Text("Open a playlist and choose Export Playlist from the menu.")
        )
    }

    private func openInFinder(export: ExportedPlaylist) {
        guard let data = export.folderBookmarkData,
              let (url, _) = try? PlaylistExportManager.shared.resolveBookmark(data) else { return }
        _ = url.startAccessingSecurityScopedResource()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        url.stopAccessingSecurityScopedResource()
    }
}

private struct ExportedPlaylistRow: View {
    @ObservedObject var observedManager = PlaylistExportManager.shared
    let export: ExportedPlaylist
    let isSyncing: Bool
    let onSync: () -> Void
    let onEdit: () -> Void
    let onOpenInFinder: () -> Void
    let onRemove: () -> Void

    @State private var showFailures = false

    private var folderPath: String {
        if let data = export.folderBookmarkData,
           let (url, _) = try? PlaylistExportManager.shared.resolveBookmark(data) {
            return url.path
        }
        return "No folder selected"
    }

    private var hasFailures: Bool { !export.failedSongIds.isEmpty }

    private var statusColor: Color {
        if isSyncing { return .accentColor }
        if hasFailures { return .red }
        if export.needsResync { return .orange }
        return .green
    }

    private var statusText: String {
        if isSyncing { return "Syncing…" }
        if hasFailures { return "\(export.failedSongIds.count) song(s) failed" }
        if export.needsResync { return "Needs sync" }
        if export.lastSyncedAt == nil { return "Never synced" }
        return "Up to date"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.and.arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(export.playlistName)
                        .font(.headline)
                    Spacer()
                    syncModeTag
                }
                Text(folderPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if isSyncing {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(isSyncing ? .secondary : statusColor)
                    if hasFailures && !isSyncing {
                        Button {
                            showFailures = true
                        } label: {
                            Image(systemName: "chevron.right.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .popover(isPresented: $showFailures, arrowEdge: .bottom) {
                            FailedSongsPopover(export: export, onRetry: onSync)
                        }
                    }
                    if let date = export.lastSyncedAt {
                        Text("·")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Sync Now", action: onSync)
            Button("Edit Configuration…", action: onEdit)
            Button("Open in Finder", action: onOpenInFinder)
            Divider()
            Button("Remove Export", role: .destructive, action: onRemove)
        }
    }

    private var syncModeTag: some View {
        Text(export.syncModeEnum.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}

private struct FailedSongsPopover: View {
    let export: ExportedPlaylist
    let onRetry: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Failed Downloads")
                    .font(.headline)
                Spacer()
                Button("Retry All") {
                    dismiss()
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(export.failedSongTitles.enumerated()), id: \.offset) { _, title in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text(title)
                                .font(.callout)
                        }
                    }
                }
                .padding()
            }
            .frame(maxHeight: 200)
        }
        .frame(width: 280)
    }
}
#endif
