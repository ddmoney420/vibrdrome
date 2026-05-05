#if os(macOS)
import SwiftUI
import os.log

// MARK: - Side Panel Container

/// Common chrome for a side panel: header bar with title + close button, then content.
struct SidePanelContainer<Content: View>: View {
    let title: String
    let onClose: () -> Void
    var onPopOut: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let onPopOut {
                    Button(action: onPopOut) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pop out \(title)")
                }
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Queue Panel

struct QueuePanelView: View {
    @Environment(AppState.self) private var appState
    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        SidePanelContainer(title: "Queue", onClose: {
            appState.activeSidePanel = nil
        }) {
            List {
                let history = engine.recentlyPlayed
                if !history.isEmpty {
                    Section("Recently Played") {
                        ForEach(history, id: \.id) { song in
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

                if let current = engine.currentSong {
                    Section("Now Playing") {
                        nowPlayingRow(current)
                    }
                }

                let entries = engine.upNextEntries
                if !entries.isEmpty {
                    Section("Up Next -- \(entries.count) songs") {
                        ForEach(Array(entries.enumerated()), id: \.element.song.id) { _, entry in
                            queueRow(entry)
                        }
                    }
                }

                if engine.queue.isEmpty {
                    ContentUnavailableView {
                        Label("No Queue", systemImage: "music.note.list")
                    } description: {
                        Text("Play some music to build a queue")
                    }
                }
            }
        }
    }

    private func nowPlayingRow(_ current: Song) -> some View {
        HStack(spacing: 12) {
            AlbumArtView(coverArtId: current.coverArt, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    appState.pendingNavigation = .song(id: current.id)
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
            }
        }
    }

    private func queueRow(_ entry: (index: Int, song: Song)) -> some View {
        HStack(spacing: 12) {
            AlbumArtView(coverArtId: entry.song.coverArt, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    appState.pendingNavigation = .song(id: entry.song.id)
                } label: {
                    Text(entry.song.title)
                        .font(.body)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                if let artist = entry.song.artist {
                    Button {
                        if let artistId = entry.song.artistId {
                            appState.pendingNavigation = .artist(id: artistId)
                        }
                    } label: {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(entry.song.artistId == nil)
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
            engine.skipToIndex(entry.index)
        }
        .contextMenu {
            Button {
                engine.skipToIndex(entry.index)
            } label: {
                Label("Play Now", systemImage: "play.fill")
            }
            Button(role: .destructive) {
                engine.removeFromQueue(atAbsolute: entry.index)
            } label: {
                Label("Remove from Queue", systemImage: "minus.circle")
            }
        }
    }
}

// MARK: - Lyrics Panel

struct LyricsPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var lyricsList: LyricsList?
    @State private var isLoading = true
    @State private var error: String?
    @State private var loadedSongId: String?

    private var engine: AudioEngine { AudioEngine.shared }

    private var selectedLyrics: StructuredLyrics? {
        guard let list = lyricsList?.structuredLyrics, !list.isEmpty else { return nil }
        return list.first(where: { $0.synced }) ?? list.first
    }

    var body: some View {
        SidePanelContainer(title: "Lyrics", onClose: {
            appState.activeSidePanel = nil
        }) {
            Group {
                if isLoading {
                    ProgressView("Loading lyrics...")
                        .padding(40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let lyrics = selectedLyrics, let lines = lyrics.line, !lines.isEmpty {
                    SyncedLyricsPanelContent(lyrics: lyrics, lines: lines)
                } else if error != nil {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error ?? "")
                    }
                    .padding(20)
                } else {
                    ContentUnavailableView {
                        Label("No Lyrics", systemImage: "text.quote")
                    } description: {
                        Text("No lyrics available for this song")
                    }
                    .padding(20)
                }
            }
        }
        .task(id: engine.currentSong?.id) {
            await loadLyrics()
        }
    }

    private func loadLyrics() async {
        guard let songId = engine.currentSong?.id else {
            lyricsList = nil
            isLoading = false
            return
        }
        if loadedSongId == songId { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            lyricsList = try await appState.subsonicClient.getLyrics(songId: songId)
            loadedSongId = songId
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }
}

/// Synced lyrics content with timer-driven active-line highlight + auto-scroll.
private struct SyncedLyricsPanelContent: View {
    let lyrics: StructuredLyrics
    let lines: [LyricLine]

    @State private var activeLineIndex: Int = 0
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false
    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        GeometryReader { geo in
            let horizontalPadding: CGFloat = 16
            let contentWidth = max(0, geo.size.width - horizontalPadding * 2)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let title = lyrics.displayTitle ?? engine.currentSong?.title {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(.headline)
                                    .frame(width: contentWidth, alignment: .leading)
                                if let artist = lyrics.displayArtist ?? engine.currentSong?.artist {
                                    Text(artist)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .frame(width: contentWidth, alignment: .leading)
                                }
                            }
                            .padding(.bottom, 8)
                        }

                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line.value.isEmpty ? "♪" : line.value)
                                .font(.body)
                                .fontWeight(index == activeLineIndex ? .bold : .regular)
                                .foregroundStyle(index == activeLineIndex ? .primary : .secondary)
                                .opacity(index == activeLineIndex ? 1.0 : 0.55)
                                .multilineTextAlignment(.leading)
                                .frame(width: contentWidth, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if lyrics.synced, let start = line.start {
                                        engine.seek(to: Double(start) / 1000.0)
                                    }
                                }
                        }

                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 16)
                }
                .onChange(of: activeLineIndex) { _, newIndex in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .onReceive(timer) { _ in updateActiveLine() }
                .onAppear { updateActiveLine() }
            }
        }
    }

    private func updateActiveLine() {
        guard lyrics.synced else { return }
        let currentMs = max(0, Int(engine.currentTime * 1000) + (lyrics.offset ?? 0))
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

// MARK: - Artist Info Panel

struct ArtistInfoPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var info: ArtistInfo2?
    @State private var isLoading = true
    @State private var loadedArtistId: String?

    private var engine: AudioEngine { AudioEngine.shared }
    private var artistId: String? { engine.currentSong?.artistId }
    private var artistName: String? { engine.currentSong?.artist }

    var body: some View {
        SidePanelContainer(title: "Artist Info", onClose: {
            appState.activeSidePanel = nil
        }) {
            ScrollView {
                if isLoading {
                    ProgressView("Loading...").padding(40)
                } else if artistId == nil {
                    ContentUnavailableView {
                        Label("No Artist", systemImage: "music.mic")
                    } description: {
                        Text("No artist information available for this track")
                    }
                    .padding(20)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        if let name = artistName {
                            Button {
                                if let id = artistId {
                                    appState.pendingNavigation = .artist(id: id)
                                }
                            } label: {
                                Text(name)
                                    .font(.title2)
                                    .bold()
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }

                        if let bio = info?.biography, !bio.isEmpty {
                            Text(cleanBio(bio))
                                .font(.body)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No biography available")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                        }

                        if let similar = info?.similarArtist, !similar.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Similar Artists")
                                    .font(.headline)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(similar.prefix(20)) { artist in
                                            Button {
                                                appState.pendingNavigation = .artist(id: artist.id)
                                            } label: {
                                                VStack(spacing: 6) {
                                                    AlbumArtView(
                                                        coverArtId: artist.coverArt,
                                                        size: 64,
                                                        cornerRadius: 32
                                                    )
                                                    Text(artist.name)
                                                        .font(.caption)
                                                        .lineLimit(2)
                                                        .multilineTextAlignment(.center)
                                                        .frame(width: 72)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .task(id: artistId) {
            await loadInfo()
        }
    }

    private func loadInfo() async {
        guard let id = artistId else {
            info = nil
            isLoading = false
            return
        }
        if loadedArtistId == id { return }
        isLoading = true
        defer { isLoading = false }
        do {
            info = try await appState.subsonicClient.getArtistInfo(id: id, count: 20)
            loadedArtistId = id
        } catch {
            Logger(subsystem: "com.vibrdrome.app", category: "ArtistInfoPanel")
                .error("Failed to load artist info: \(error)")
        }
    }

    private func cleanBio(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
