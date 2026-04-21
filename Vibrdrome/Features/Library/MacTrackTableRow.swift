#if os(macOS)
import SwiftUI
import SwiftData
import NukeUI

// MARK: - Single track row for the custom macOS table

struct MacTrackTableRow: View {
    let song: Song
    let visibleColumns: [TrackTableColumn]
    let queue: [Song]
    let index: Int
    /// Binding to the parent-managed selected song id for single-click selection.
    @Binding var selectedSongId: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private var showAlbumArt: Bool = true
    @State private var isStarred = false
    @State private var isDownloaded = false
    @State private var isHovered = false

    private var isCurrentlyPlaying: Bool {
        AudioEngine.shared.currentSong?.id == song.id
    }

    private var isSelected: Bool { selectedSongId == song.id }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleColumns) { col in
                columnCell(col)
            }
            trailingActions
        }
        .padding(.horizontal, 12)
        .frame(height: showAlbumArt ? 44 : 34)
        // Now-playing gets an accent tint; selected gets a system selection bg; hover gets a subtle lift
        .background {
            if isCurrentlyPlaying {
                Color.accentColor.opacity(0.12)
            } else if isSelected {
                Color.accentColor.opacity(0.08)
            } else if isHovered {
                Color.primary.opacity(0.05)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        // Single-click: select
        .onTapGesture(count: 1) {
            selectedSongId = song.id
        }
        // Double-click: play
        .onTapGesture(count: 2) {
            selectedSongId = song.id
            AudioEngine.shared.play(song: song, from: queue, at: index)
        }
        .trackContextMenu(song: song, queue: queue, index: index)
        .onAppear {
            isStarred = song.starred != nil
            let songId = song.id
            let descriptor = FetchDescriptor<DownloadedSong>(
                predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
            )
            isDownloaded = (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
        }
    }

    // MARK: - Column cells

    @ViewBuilder
    private func columnCell(_ col: TrackTableColumn) -> some View {
        let content = cellContent(col)
        content
            .font(col == .trackNumber ? .subheadline : .body)
            .foregroundStyle(cellForegroundStyle(col))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 4)
            .frame(
                minWidth: col.minWidth,
                maxWidth: col.isFlexible ? .infinity : col.minWidth,
                alignment: col == .trackNumber ? .trailing : .leading
            )
    }

    @ViewBuilder
    private func cellContent(_ col: TrackTableColumn) -> some View {
        switch col {
        case .trackNumber:
            if isCurrentlyPlaying {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: col.minWidth, alignment: .trailing)
            } else if let track = song.track {
                Text("\(track)")
            } else {
                Text("—").foregroundStyle(.quaternary)
            }
        case .title:
            if showAlbumArt {
                HStack(spacing: 8) {
                    AlbumArtView(coverArtId: song.coverArt, size: 28, cornerRadius: 3)
                    Text(song.title)
                        .fontWeight(isCurrentlyPlaying ? .semibold : .regular)
                        .lineLimit(1)
                }
            } else {
                Text(song.title)
                    .fontWeight(isCurrentlyPlaying ? .semibold : .regular)
            }
        case .artist:
            Text(song.artist ?? "—")
                .foregroundStyle(song.artist != nil ? .primary : .quaternary)
        case .album:
            Text(song.album ?? "—")
                .foregroundStyle(song.album != nil ? .primary : .quaternary)
        case .duration:
            Text(song.duration.map { formatDuration($0) } ?? "—")
                .foregroundStyle(.secondary)
        case .year:
            Text(song.year.map { String($0) } ?? "—")
                .foregroundStyle(song.year != nil ? .secondary : .quaternary)
        case .genre:
            Text(song.genre ?? "—")
                .foregroundStyle(song.genre != nil ? .secondary : .quaternary)
        case .bitRate:
            if let br = song.bitRate {
                Text("\(br) kbps")
                    .foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.quaternary)
            }
        case .format:
            Text(song.suffix?.uppercased() ?? "—")
                .foregroundStyle(song.suffix != nil ? .secondary : .quaternary)
        case .bpm:
            Text(song.bpm.map { String($0) } ?? "—")
                .foregroundStyle(song.bpm != nil ? .secondary : .quaternary)
        case .dateAdded:
            Text(formattedDateAdded)
                .foregroundStyle(.secondary)
        }
    }

    private func cellForegroundStyle(_ col: TrackTableColumn) -> some ShapeStyle {
        if isCurrentlyPlaying && col == .title {
            return AnyShapeStyle(Color.accentColor)
        }
        return AnyShapeStyle(Color.primary)
    }

    private var formattedDateAdded: String {
        guard let created = song.created else { return "—" }
        // Format: "MMM d, yyyy" from ISO8601 prefix
        let prefix = String(created.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: prefix) {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return prefix
    }

    // MARK: - Trailing fixed actions

    private var trailingActions: some View {
        HStack(spacing: 4) {
            // Heart
            Button {
                let wasStarred = isStarred
                isStarred = !wasStarred
                Task {
                    do {
                        if wasStarred {
                            try await OfflineActionQueue.shared.unstar(id: song.id)
                        } else {
                            try await OfflineActionQueue.shared.star(id: song.id)
                            if UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoDownloadFavorites) {
                                DownloadManager.shared.download(song: song, client: AppState.shared.subsonicClient)
                            }
                        }
                    } catch {
                        isStarred = wasStarred
                    }
                }
            } label: {
                Image(systemName: isStarred ? "heart.fill" : "heart")
                    .font(.caption)
                    .foregroundStyle(isStarred ? .pink : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isStarred ? 1 : 0)
            .accessibilityLabel(isStarred ? "Remove from Favorites" : "Add to Favorites")

            // Download
            if isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Downloaded")
            } else {
                Button {
                    DownloadManager.shared.download(
                        song: song, client: AppState.shared.subsonicClient
                    )
                    isDownloaded = true
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .accessibilityLabel("Download Song")
            }

            // Context menu button
            Menu {
                Button {
                    AudioEngine.shared.addToQueueNext(song)
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }
                Button {
                    AudioEngine.shared.addToQueue(song)
                } label: {
                    Label("Add to Queue", systemImage: "text.append")
                }
                Button {
                    AudioEngine.shared.startRadioFromSong(song)
                } label: {
                    Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                }
                let shareText = "🎵 \(song.title) — \(song.artist ?? "Unknown Artist")"
                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .accessibilityLabel("Song Options")
        }
        .frame(width: 80, alignment: .trailing)
    }
}
#endif
