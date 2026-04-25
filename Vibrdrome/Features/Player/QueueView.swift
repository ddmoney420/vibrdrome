import SwiftUI

struct QueueView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                // Recently played (top)
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

                // Now playing (middle, fixed position)
                if let current = engine.currentSong {
                    Section("Now Playing") {
                        EmptyView().id("nowPlayingAnchor")
                        HStack(spacing: 12) {
                            AlbumArtView(coverArtId: current.coverArt, size: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(current.title)
                                    .font(.body)
                                    .bold()
                                    .lineLimit(1)

                                if let artist = current.artist {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
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

                // Up Next (tracks after currently playing)
                let entries = engine.upNextEntries
                if !entries.isEmpty {
                    let totalSeconds = entries.compactMap(\.song.duration).reduce(0, +)
                    Section("Up Next -- \(entries.count) songs -- \(formatDuration(totalSeconds))") {
                        ForEach(Array(entries.enumerated()), id: \.element.song.id) { _, entry in
                            HStack(spacing: 12) {
                                AlbumArtView(coverArtId: entry.song.coverArt, size: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.song.title)
                                        .font(.body)
                                        .lineLimit(1)

                                    if let artist = entry.song.artist {
                                        Text(artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                if let duration = entry.song.duration {
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
                                engine.skipToIndex(entry.index)
                            }
                            .trackContextMenu(song: entry.song) {
                                engine.removeFromQueue(atAbsolute: entry.index)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    engine.removeFromQueue(atAbsolute: entry.index)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        }
                        .onMove { source, destination in
                            engine.moveInUpNext(from: source, to: destination)
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
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation { proxy.scrollTo("nowPlayingAnchor", anchor: .top) }
                }
            }
            } // ScrollViewReader
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
