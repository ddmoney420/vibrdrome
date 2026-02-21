import SwiftUI
import os.log

struct BookmarksView: View {
    @Environment(AppState.self) private var appState
    @State private var bookmarks: [Bookmark] = []
    @State private var isLoading = true
    @State private var error: String?

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        List {
            ForEach(bookmarks.filter { $0.entry != nil }, id: \.entry!.id) { bookmark in
                if let song = bookmark.entry {
                    HStack(spacing: 12) {
                        AlbumArtView(coverArtId: song.coverArt, size: 50)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.body)
                                .lineLimit(1)
                            Text(song.artist ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("at \(formatDuration(bookmark.position / 1000))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Button {
                            resumeFromBookmark(bookmark, song: song)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteBookmark(id: song.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Bookmarks")
        .overlay {
            if isLoading && bookmarks.isEmpty {
                ProgressView()
            } else if let error, bookmarks.isEmpty {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadBookmarks() } }
                        .buttonStyle(.bordered)
                }
            } else if !isLoading && bookmarks.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks", systemImage: "bookmark")
                } description: {
                    Text("Bookmarks are created automatically when you pause or background the app during playback")
                }
            }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                Button { Task { await loadBookmarks() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        #endif
        .task { await loadBookmarks() }
        .refreshable { await loadBookmarks() }
    }

    private func loadBookmarks() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            bookmarks = try await appState.subsonicClient.getBookmarks()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func resumeFromBookmark(_ bookmark: Bookmark, song: Song) {
        engine.play(song: song, from: [song], at: 0)
        let position = Double(bookmark.position) / 1000.0
        let songId = song.id
        Task {
            // Wait for player readiness with deadline (up to 5 seconds)
            let deadline = ContinuousClock.now + .seconds(5)
            while ContinuousClock.now < deadline {
                guard engine.currentSong?.id == songId else { return }
                if engine.duration > 0 { break }
                try? await Task.sleep(for: .milliseconds(200)) // try? OK: sleep cancellation
            }
            guard engine.currentSong?.id == songId else { return }
            engine.seek(to: position)
            try? await appState.subsonicClient.deleteBookmark(id: songId) // try? OK: best-effort cleanup
            await loadBookmarks()
        }
    }

    private func deleteBookmark(id: String) {
        bookmarks.removeAll { $0.entry?.id == id }
        Task {
            do {
                try await appState.subsonicClient.deleteBookmark(id: id)
            } catch {
                Logger(subsystem: "com.veydrune.app", category: "Bookmarks")
                    .error("Failed to delete bookmark: \(error)")
            }
        }
    }
}
