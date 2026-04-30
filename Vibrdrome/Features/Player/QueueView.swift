import SwiftUI

struct QueueView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""

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

                // Recently played
                let history = engine.recentlyPlayed
                if !history.isEmpty {
                    Section("Recently Played") {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, song in
                            HStack(spacing: 12) {
                                AlbumArtView(coverArtId: song.coverArt, size: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(song.artist ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .opacity(0.6)
                        }
                    }
                }

                // Radio mode badge
                if engine.isRadioMode {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundColor(.accentColor)
                            Text(engine.radioSeedArtistName ?? "Artist Radio")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Stop Radio") {
                                engine.stopRadioMode()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("stopRadioButton")
                        }
                    }
                }

                // Up next
                let upNext = engine.shuffleEnabled ? engine.nextSongs(count: 5) : engine.upNext
                let allUpNext = engine.upNext
                if !upNext.isEmpty {
                    let totalSeconds = allUpNext.compactMap(\.duration).reduce(0, +)
                    let header = engine.shuffleEnabled
                    ? "Up Next — \(upNext.count)/\(allUpNext.count) songs · \(formatDuration(totalSeconds))"
                        : "Up Next — \(upNext.count) songs · \(formatDuration(totalSeconds))"
                    Section(header) {
                        if engine.shuffleEnabled {
                            ForEach(Array(upNext.enumerated()), id: \.offset) { index, song in
                                upNextRow(song: song, index: index)
                            }
                        } else {
                            ForEach(Array(upNext.enumerated()), id: \.offset) { index, song in
                                upNextRow(song: song, index: index)
                            }
                            .onMove { source, destination in
                                engine.moveInQueue(from: source, to: destination)
                            }
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
                        .accessibilityIdentifier("queueDoneButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            saveQueueAsPlaylist()
                        } label: {
                            Label("Save as Playlist", systemImage: "square.and.arrow.down")
                        }
                        .disabled(engine.queue.isEmpty)

                        Button {
                            engine.toggleShuffle()
                        } label: {
                            Label(
                                engine.shuffleEnabled ? "Shuffle On" : "Shuffle Off",
                                systemImage: "shuffle"
                            )
                        }

                        Divider()

                        Button(role: .destructive) {
                            engine.clearQueue()
                        } label: {
                            Label("Clear Queue", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Queue Options")
                    .accessibilityIdentifier("queueOptionsMenu")
                }
            }
            .alert(saveMessage, isPresented: $showingSaveAlert) {
                Button("OK") { }
            }
        }
    }

    @ViewBuilder
    private func upNextRow(song: Song, index: Int) -> some View {
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
            #if os(iOS)
            Haptics.light()
            #endif
            if engine.shuffleEnabled {
                if let absoluteIndex = engine.queue.firstIndex(where: { $0.id == song.id }) {
                    engine.play(song: song, from: engine.queue, at: absoluteIndex)
                }
            } else {
                let absoluteIndex = engine.currentIndex + 1 + index
                engine.play(song: song, from: engine.queue, at: absoluteIndex)
            }
        }
        .contextMenu {
            Button {
                if engine.shuffleEnabled {
                    if let absoluteIndex = engine.queue.firstIndex(where: { $0.id == song.id }) {
                        engine.play(song: song, from: engine.queue, at: absoluteIndex)
                    }
                } else {
                    let absoluteIndex = engine.currentIndex + 1 + index
                    engine.play(song: song, from: engine.queue, at: absoluteIndex)
                }
            } label: {
                Label("Play Now", systemImage: "play.fill")
            }
            Button {
                engine.addToQueueNext(song)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            if !engine.shuffleEnabled {
                Divider()
                Button(role: .destructive) {
                    engine.removeFromQueue(at: index)
                } label: {
                    Label("Remove from Queue", systemImage: "minus.circle")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !engine.shuffleEnabled {
                Button(role: .destructive) {
                    engine.removeFromQueue(at: index)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }

    private func saveQueueAsPlaylist() {
        let songs = engine.queue
        guard !songs.isEmpty else { return }
        let songIds = songs.map(\.id)
        let dateStr = Date().formatted(date: .abbreviated, time: .shortened)
        let name = "Queue — \(dateStr)"
        Task {
            do {
                try await appState.subsonicClient.createPlaylist(name: name, songIds: songIds)
                saveMessage = "Saved \"\(name)\" with \(songIds.count) songs"
                showingSaveAlert = true
            } catch {
                saveMessage = "Failed to save: \(ErrorPresenter.userMessage(for: error))"
                showingSaveAlert = true
            }
        }
    }
}
