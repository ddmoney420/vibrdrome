import NukeUI
import SwiftUI

struct SongsView: View {
    @Environment(AppState.self) private var appState
    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var hasMore = true
    @State private var searchText = ""
    @State private var searchResults: [Song] = []
    @State private var isSearching = false
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private var showAlbumArtInLists: Bool = true
    @State private var sortBy: SongSortOption = .title

    private let albumPageSize = 50

    enum SongSortOption: String, CaseIterable {
        case title, artist, album, duration
        var label: String {
            switch self {
            case .title: "Title"
            case .artist: "Artist"
            case .album: "Album"
            case .duration: "Duration"
            }
        }
    }

    private var displayedSongs: [Song] {
        let base = searchText.count >= 2 ? searchResults : songs
        switch sortBy {
        case .title: return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist: return base.sorted { ($0.artist ?? "").localizedCaseInsensitiveCompare($1.artist ?? "") == .orderedAscending }
        case .album: return base.sorted { ($0.album ?? "").localizedCaseInsensitiveCompare($1.album ?? "") == .orderedAscending }
        case .duration: return base.sorted { ($0.duration ?? 0) < ($1.duration ?? 0) }
        }
    }

    var body: some View {
        List {
            if !displayedSongs.isEmpty {
                HStack(spacing: 12) {
                    Button {
                        let songs = displayedSongs
                        AudioEngine.shared.play(song: songs[0], from: songs, at: 0)
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityIdentifier("songsPlayAllButton")

                    Button {
                        let shuffled = displayedSongs.shuffled()
                        AudioEngine.shared.play(song: shuffled[0], from: shuffled, at: 0)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityIdentifier("songsShuffleButton")
                }
                .listRowSeparator(.hidden)
            }

            ForEach(Array(displayedSongs.enumerated()), id: \.element.id) { index, song in
                Button {
                    AudioEngine.shared.play(song: song, from: displayedSongs, at: index)
                } label: {
                    songRow(song)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("songRow_\(song.id)")
                .trackContextMenu(song: song)
                .onAppear {
                    if searchText.isEmpty && hasMore && !isLoading && song.id == songs.last?.id {
                        Task { await loadMore() }
                    }
                }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .navigationTitle(songs.isEmpty ? "Songs" : "Songs (\(songs.count))")
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
                Menu {
                    ForEach(SongSortOption.allCases, id: \.self) { option in
                        Button {
                            sortBy = option
                        } label: {
                            HStack {
                                Text(option.label)
                                if sortBy == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        Task { await loadSongs() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
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

            VStack(alignment: .trailing, spacing: 2) {
                if let duration = song.duration {
                    Text(formatDuration(TimeInterval(duration)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                HStack(spacing: 4) {
                    if let suffix = song.suffix {
                        Text(suffix.uppercased())
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    if let bitRate = song.bitRate {
                        Text("\(bitRate)k")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }

    @State private var albumOffset = 0

    private func loadSongs() async {
        isLoading = true
        hasMore = true
        albumOffset = 0
        songs = []
        defer { isLoading = false }
        await loadNextBatch()
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await loadNextBatch()
    }

    private func loadNextBatch() async {
        do {
            let albums = try await appState.subsonicClient.getAlbumList(
                type: .alphabeticalByName, size: albumPageSize, offset: albumOffset
            )
            guard !albums.isEmpty else {
                hasMore = false
                return
            }
            var newSongs: [Song] = []
            for album in albums {
                let detail = try await appState.subsonicClient.getAlbum(id: album.id)
                if let albumSongs = detail.song {
                    newSongs.append(contentsOf: albumSongs)
                }
            }
            songs.append(contentsOf: newSongs)
            albumOffset += albums.count
            hasMore = albums.count >= albumPageSize
        } catch {}
    }
}
