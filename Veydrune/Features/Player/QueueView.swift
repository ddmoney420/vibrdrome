import SwiftUI

struct QueueView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        NavigationStack {
            List {
                // Now playing
                if let current = engine.currentSong {
                    Section("Now Playing") {
                        HStack(spacing: 12) {
                            AlbumArtView(coverArtId: current.coverArt, size: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(current.title)
                                    .font(.body)
                                    .bold()
                                    .lineLimit(1)
                                Text(current.artist ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if engine.isPlaying {
                                Image(systemName: "waveform")
                                    .foregroundStyle(Color.accentColor)
                                    .symbolEffect(.variableColor)
                                    .accessibilityLabel("Playing")
                            }
                        }
                    }
                }

                // Up next
                let upNext = engine.upNext
                if !upNext.isEmpty {
                    Section("Up Next — \(upNext.count) songs") {
                        ForEach(Array(upNext.enumerated()), id: \.element.id) { index, song in
                            HStack(spacing: 12) {
                                AlbumArtView(coverArtId: song.coverArt, size: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.body)
                                        .lineLimit(1)
                                    Text(song.artist ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if let duration = song.duration {
                                    Text(formatDuration(duration))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .monospacedDigit()
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let absoluteIndex = engine.currentIndex + 1 + index
                                engine.play(song: song, from: engine.queue, at: absoluteIndex)
                            }
                        }
                        .onDelete { offsets in
                            for offset in offsets.sorted().reversed() {
                                engine.removeFromQueue(at: offset)
                            }
                        }
                        .onMove { source, destination in
                            engine.moveInQueue(from: source, to: destination)
                        }
                    }
                }

                // Queue info
                if engine.queue.isEmpty {
                    ContentUnavailableView {
                        Label("No Queue", systemImage: "music.note.list")
                    } description: {
                        Text("Play some music to build a queue")
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Queue")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            engine.clearQueue()
                        } label: {
                            Label("Clear Queue", systemImage: "trash")
                        }

                        Button {
                            engine.toggleShuffle()
                        } label: {
                            Label(
                                engine.shuffleEnabled ? "Shuffle On" : "Shuffle Off",
                                systemImage: "shuffle"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Queue Options")
                }
            }
        }
    }
}
