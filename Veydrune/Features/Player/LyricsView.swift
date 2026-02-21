import SwiftUI

struct LyricsView: View {
    let songId: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var lyricsList: LyricsList?
    @State private var isLoading = true
    @State private var error: String?

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        NavigationStack {
            Group {
                if let lyrics = selectedLyrics {
                    SyncedLyricsContent(lyrics: lyrics, engine: engine)
                } else if isLoading {
                    ProgressView("Loading lyrics...")
                } else if error != nil {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error ?? "")
                    } actions: {
                        Button("Retry") { Task { await loadLyrics() } }
                            .buttonStyle(.bordered)
                    }
                } else {
                    ContentUnavailableView {
                        Label("No Lyrics", systemImage: "text.quote")
                    } description: {
                        Text("No lyrics available for this song")
                    }
                }
            }
            .navigationTitle("Lyrics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadLyrics() }
        }
    }

    private var selectedLyrics: StructuredLyrics? {
        guard let list = lyricsList?.structuredLyrics, !list.isEmpty else { return nil }
        // Prefer synced lyrics, fall back to unsynced
        return list.first(where: { $0.synced }) ?? list.first
    }

    private func loadLyrics() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            lyricsList = try await appState.subsonicClient.getLyrics(songId: songId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Synced Lyrics Content

private struct SyncedLyricsContent: View {
    let lyrics: StructuredLyrics
    let engine: AudioEngine

    @State private var activeLineIndex: Int = 0
    // V7: Extract timer publisher so it's not recreated on every body evaluation
    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Song info header
                    if let title = lyrics.displayTitle ?? engine.currentSong?.title {
                        VStack(spacing: 4) {
                            Text(title)
                                .font(.headline)
                            if let artist = lyrics.displayArtist ?? engine.currentSong?.artist {
                                Text(artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    }

                    ForEach(Array((lyrics.line ?? []).enumerated()), id: \.offset) { index, line in
                        Text(line.value.isEmpty ? "♪" : line.value)
                            .font(.title3)
                            .fontWeight(index == activeLineIndex ? .bold : .regular)
                            .foregroundStyle(index == activeLineIndex ? .primary : .secondary)
                            .opacity(index == activeLineIndex ? 1.0 : 0.5)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 4)
                            .id(index)
                            .onTapGesture {
                                if lyrics.synced, let start = line.start {
                                    engine.seek(to: Double(start) / 1000.0)
                                }
                            }
                    }

                    Spacer(minLength: 100)
                }
            }
            .onChange(of: activeLineIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onReceive(timer) { _ in
                updateActiveLine()
            }
            .onAppear {
                updateActiveLine()
            }
        }
    }

    private func updateActiveLine() {
        guard lyrics.synced else { return }
        let currentMs = Int(engine.currentTime * 1000) + (lyrics.offset ?? 0)
        let lines = lyrics.line ?? []

        var newIndex = 0
        for (index, line) in lines.enumerated() {
            if let start = line.start, currentMs >= start {
                newIndex = index
            }
        }

        if newIndex != activeLineIndex {
            activeLineIndex = newIndex
        }
    }
}
