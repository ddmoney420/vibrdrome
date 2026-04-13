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
                                Button {
                                    appState.pendingNavigation = .song(id: current.id)
                                    dismiss()
                                } label: {
                                    Text(current.title)
                                        .font(.body)
                                        .bold()
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)

                                if let artist = current.artist {
                                    Button {
                                        if let artistId = current.artistId {
                                            appState.pendingNavigation = .artist(id: artistId)
                                            dismiss()
                                        }
                                    } label: {
                                        Text(artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(current.artistId == nil)
                                }
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
                        ForEach(Array(history.enumerated()), id: \.element.id) { _, song in
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
                let upNext = engine.upNext
                if !upNext.isEmpty {
                    let totalSeconds = upNext.compactMap(\.duration).reduce(0, +)
                    Section("Up Next — \(upNext.count) songs · \(formatDuration(totalSeconds))") {
                        ForEach(Array(upNext.enumerated()), id: \.element.id) { index, song in
                            HStack(spacing: 12) {
                                AlbumArtView(coverArtId: song.coverArt, size: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Button {
                                        appState.pendingNavigation = .song(id: song.id)
                                        dismiss()
                                    } label: {
                                        Text(song.title)
                                            .font(.body)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)

                                    if let artist = song.artist {
                                        Button {
                                            if let artistId = song.artistId {
                                                appState.pendingNavigation = .artist(id: artistId)
                                                dismiss()
                                            }
                                        } label: {
                                            Text(artist)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(song.artistId == nil)
                                    }
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
                                let absoluteIndex = engine.currentIndex + 1 + index
                                engine.play(song: song, from: engine.queue, at: absoluteIndex)
                            }
                            .contextMenu {
                                Button {
                                    let absoluteIndex = engine.currentIndex + 1 + index
                                    engine.play(song: song, from: engine.queue, at: absoluteIndex)
                                } label: {
                                    Label("Play Now", systemImage: "play.fill")
                                }
                                Button {
                                    engine.addToQueueNext(song)
                                } label: {
                                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    engine.removeFromQueue(at: index)
                                } label: {
                                    Label("Remove from Queue", systemImage: "minus.circle")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    engine.removeFromQueue(at: index)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .tint(.red)
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
