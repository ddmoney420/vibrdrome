import SwiftUI
import SwiftData
import Nuke
import os.log

struct SongDetailView: View {
    let songId: String

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var song: Song?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isStarred = false
    @State private var currentRating = 0
    @State private var lyrics: StructuredLyrics?
    @State private var lyricsLoaded = false
    @State private var isDownloaded = false

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        ScrollView {
            if let song {
                VStack(spacing: 24) {
                    header(song)
                    actionButtons(song)
                    metadataGrid(song)
                    lyricsSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(song?.title ?? "Song")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if isLoading && song == nil {
                ProgressView()
            } else if let error, song == nil {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Header

    private func header(_ song: Song) -> some View {
        VStack(spacing: 16) {
            AlbumArtView(coverArtId: song.coverArt, size: 280, cornerRadius: 14)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)

            VStack(spacing: 6) {
                Text(song.title)
                    .font(.title)
                    .bold()
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                if let artist = song.artist {
                    Button {
                        if let artistId = song.artistId {
                            appState.pendingNavigation = .artist(id: artistId)
                        }
                    } label: {
                        Text(artist)
                            .font(.title3)
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(song.artistId == nil)
                }

                if let album = song.album {
                    Button {
                        if let albumId = song.albumId {
                            appState.pendingNavigation = .album(id: albumId)
                        }
                    } label: {
                        Text(album)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(song.albumId == nil)
                }
            }

            heartAndRating(song)
        }
    }

    private func heartAndRating(_ song: Song) -> some View {
        HStack(spacing: 24) {
            Button { toggleStar(song) } label: {
                Image(systemName: isStarred ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(isStarred ? .pink : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isStarred ? "Remove from Favorites" : "Add to Favorites")

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        let newRating = (star == currentRating) ? 0 : star
                        currentRating = newRating
                        Task {
                            try? await appState.subsonicClient.setRating(id: song.id, rating: newRating)
                        }
                    } label: {
                        Image(systemName: star <= currentRating ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundColor(star <= currentRating ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
            }
        }
    }

    // MARK: - Actions

    private func actionButtons(_ song: Song) -> some View {
        HStack(spacing: 12) {
            Button {
                engine.play(song: song, from: [song], at: 0)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)

            Button {
                engine.addToQueueNext(song)
            } label: {
                Label("Play Next", systemImage: "text.insert")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)

            Button {
                engine.addToQueue(song)
            } label: {
                Label("Add to Queue", systemImage: "text.append")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Metadata

    private func metadataGrid(_ song: Song) -> some View {
        let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            if let year = song.year {
                metadataCell("Year", value: "\(year)")
            }
            if let genre = song.genre {
                metadataCell("Genre", value: genre.cleanedGenreDisplay)
            }
            if let duration = song.duration {
                metadataCell("Duration", value: formatDuration(duration))
            }
            if let suffix = song.suffix {
                metadataCell("Format", value: suffix.uppercased())
            }
            if let bitRate = song.bitRate {
                metadataCell("Bitrate", value: "\(bitRate) kbps")
            }
            if let bpm = song.bpm, bpm > 0 {
                metadataCell("BPM", value: "\(bpm)")
            }
            if let track = song.track {
                metadataCell("Track", value: "\(track)")
            }
            if let disc = song.discNumber {
                metadataCell("Disc", value: "\(disc)")
            }
            if let size = song.size {
                metadataCell("Size", value: formatBytes(size))
            }
            metadataCell("Status", value: isDownloaded ? "Downloaded" : "Streaming")
        }
    }

    private func metadataCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Lyrics

    @ViewBuilder
    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Lyrics")
                    .font(.headline)
                Spacer()
                if !lyricsLoaded {
                    ProgressView().controlSize(.small)
                } else if let lyrics, !(lyrics.line ?? []).isEmpty {
                    statusBadge(text: lyrics.synced ? "Synced" : "Available", color: .green)
                } else {
                    statusBadge(text: "Not Available", color: .secondary)
                }
            }

            if let lyrics, let lines = lyrics.line, !lines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.value.isEmpty ? "♪" : line.value)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Loading & actions

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fetched = try await appState.subsonicClient.getSong(id: songId)
            song = fetched
            isStarred = fetched.starred != nil
            currentRating = fetched.userRating ?? 0
            checkDownloaded(songId: fetched.id)
            await loadLyrics()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func loadLyrics() async {
        lyricsLoaded = false
        do {
            let list = try await appState.subsonicClient.getLyrics(songId: songId)
            lyrics = (list?.structuredLyrics ?? []).first(where: { $0.synced })
                ?? list?.structuredLyrics?.first
        } catch {
            Logger(subsystem: "com.vibrdrome.app", category: "SongDetail")
                .error("Lyrics load failed: \(error)")
        }
        lyricsLoaded = true
    }

    private func toggleStar(_ song: Song) {
        let wasStarred = isStarred
        isStarred = !wasStarred
        Task {
            do {
                if wasStarred {
                    try await OfflineActionQueue.shared.unstar(id: song.id)
                } else {
                    try await OfflineActionQueue.shared.star(id: song.id)
                    if UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoDownloadFavorites) {
                        DownloadManager.shared.download(song: song, client: appState.subsonicClient)
                    }
                }
            } catch {
                isStarred = wasStarred
            }
        }
    }

    private func checkDownloaded(songId: String) {
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
        )
        isDownloaded = (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
