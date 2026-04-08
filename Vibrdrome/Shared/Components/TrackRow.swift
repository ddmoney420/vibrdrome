import SwiftUI
import SwiftData

struct TrackRow: View {
    let song: Song
    var showTrackNumber: Bool = true
    var queue: [Song]?
    var index: Int?
    @Environment(\.modelContext) private var modelContext
    @State private var isDownloaded = false
    @State private var isStarred = false

    var body: some View {
        HStack(spacing: 12) {
            if showTrackNumber, let track = song.track {
                Text("\(track)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let artist = song.artist {
                        Text(artist)
                    }
                    if let duration = song.duration {
                        Text("·")
                        Text(formatDuration(duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            // Heart toggle
            Button {
                let wasStarred = isStarred
                isStarred = !wasStarred
                #if os(iOS)
                Haptics.light()
                #endif
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
            .accessibilityIdentifier("trackHeartButton_\(song.id)")

            // Download button
            if isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Button {
                    #if os(iOS)
                    Haptics.light()
                    #endif
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
                .accessibilityIdentifier("trackDownloadButton_\(song.id)")
            }

            // Inline menu
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
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trackMenuButton_\(song.id)")
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(trackAccessibilityLabel)
        .onAppear {
            isStarred = song.starred != nil
            let songId = song.id
            let descriptor = FetchDescriptor<DownloadedSong>(
                predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
            )
            isDownloaded = (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
        }
    }

    private var trackAccessibilityLabel: String {
        var parts = [song.title]
        if let artist = song.artist {
            parts.append("by \(artist)")
        }
        if let duration = song.duration {
            parts.append(formatDuration(duration))
        }
        if isStarred {
            parts.append("Favorited")
        }
        if isDownloaded {
            parts.append("Downloaded")
        }
        return parts.joined(separator: ", ")
    }
}
