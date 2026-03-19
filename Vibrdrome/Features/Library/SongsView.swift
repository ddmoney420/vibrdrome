import NukeUI
import SwiftUI

struct SongsView: View {
    @Environment(AppState.self) private var appState
    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var searchResults: [Song] = []
    @State private var isSearching = false
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private var showAlbumArtInLists: Bool = true

    private var displayedSongs: [Song] {
        searchText.count >= 2 ? searchResults : songs
    }

    var body: some View {
        List {
            ForEach(Array(displayedSongs.enumerated()), id: \.element.id) { index, song in
                Button {
                    AudioEngine.shared.play(song: song, from: displayedSongs, at: index)
                } label: {
                    songRow(song)
                }
                .buttonStyle(.plain)
                .trackContextMenu(song: song)
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .navigationTitle("Songs")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search songs")
        .onChange(of: searchText) { _, query in
            guard query.count >= 2 else {
                searchResults = []
                return
            }
            isSearching = true
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, searchText == query else { return }
                do {
                    let result = try await appState.subsonicClient.search(
                        query: query, artistCount: 0, albumCount: 0, songCount: 50)
                    searchResults = result.song ?? []
                } catch {}
                isSearching = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadSongs() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await loadSongs() }
    }

    private func songRow(_ song: Song) -> some View {
        HStack(spacing: 12) {
            if showAlbumArtInLists {
                AlbumArtView(coverArtId: song.coverArt, size: 40, cornerRadius: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let artist = song.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let album = song.album {
                        Text("· \(album)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if let duration = song.duration {
                Text(formatDuration(TimeInterval(duration)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }

    private func loadSongs() async {
        isLoading = true
        defer { isLoading = false }
        do {
            songs = try await appState.subsonicClient.getRandomSongs(size: 100)
        } catch {}
    }
}
