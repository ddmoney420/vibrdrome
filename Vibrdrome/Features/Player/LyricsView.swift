import SwiftUI

struct LyricsView: View {
    let songId: String
    /// Track metadata used for the LRCLIB internet fallback (#82). Optional so older
    /// call sites keep working; the fallback is skipped when title/artist are missing.
    var title: String?
    var artist: String?
    var album: String?
    var duration: Int?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserDefaultsKeys.fetchInternetLyrics) private var fetchInternetLyrics = true
    @AppStorage(UserDefaultsKeys.lyricHighlightStyle) private var highlightStyle: LyricHighlightStyle = .wordDimmed
    @AppStorage(UserDefaultsKeys.lyricHighlightColor) private var highlightColor: LyricHighlightColor = .accent
    @State private var lyricsList: LyricsList?
    @State private var isLoading = true
    @State private var error: String?

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        NavigationStack {
            Group {
                if let lyrics = selectedLyrics {
                    SyncedLyricsContent(lyrics: lyrics, engine: engine, songId: songId)
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
                if hasWordLevelLyrics {
                    ToolbarItem(placement: highlightMenuPlacement) { highlightStyleMenu }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("lyricsDoneButton")
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

    /// True only when the chosen lyrics carry word-level cue data — the style menu is meaningless
    /// (and hidden) for line-only tracks, LRCLIB, `.lrc`/`.txt`, and old servers.
    private var hasWordLevelLyrics: Bool {
        selectedLyrics?.cueLine?.isEmpty == false
    }

    private var highlightMenuPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .automatic
        #endif
    }

    /// Live switch for the word-highlight style, mirroring the Settings picker via the same
    /// `@AppStorage` key so changes take effect immediately on-screen.
    private var highlightStyleMenu: some View {
        Menu {
            Picker("Highlight", selection: $highlightStyle) {
                ForEach(LyricHighlightStyle.allCases) { style in
                    Label(style.label, systemImage: style.icon).tag(style)
                }
            }
            Picker("Highlight Color", selection: $highlightColor) {
                ForEach(LyricHighlightColor.allCases) { color in
                    Label {
                        Text(color.label)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(color.swatch)
                    }
                    .tag(color)
                }
            }
            .disabled(!highlightStyle.isWordLevel)
        } label: {
            Image(systemName: "music.mic")
        }
        .accessibilityIdentifier("lyricsStyleMenu")
        .accessibilityLabel("Lyrics highlight style")
    }

    private func loadLyrics() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // 1. Try the server first.
        var serverError: String?
        do {
            let serverLyrics = try await appState.subsonicClient.getLyrics(songId: songId)
            if hasLyrics(serverLyrics) {
                lyricsList = serverLyrics
                return
            }
        } catch {
            serverError = ErrorPresenter.userMessage(for: error)
        }

        // 2. Fall back to LRCLIB when the server has none and the user opted in (#82).
        if fetchInternetLyrics, let title, let artist,
           let external = await LRCLIBClient.shared.lyrics(
               title: title, artist: artist, album: album,
               duration: duration, cacheKey: songId
           ) {
            lyricsList = LyricsList(structuredLyrics: [external])
            return
        }

        // 3. Nothing found. Surface a server error if there was one, else "No Lyrics".
        lyricsList = nil
        error = serverError
    }

    /// True when a lyrics payload actually contains at least one non-empty line.
    private func hasLyrics(_ list: LyricsList?) -> Bool {
        guard let entries = list?.structuredLyrics else { return false }
        return entries.contains { !($0.line ?? []).isEmpty }
    }
}

// MARK: - Highlight Style (#113)

/// How word-synced (enhanced) lyrics highlight. Line-level lyrics always render line-by-line
/// regardless of this choice; only tracks with cue data are affected.
enum LyricHighlightStyle: String, CaseIterable, Identifiable {
    /// Karaoke off — the classic line-level highlight only.
    case lineOnly
    /// Active word bold; the rest of the line stays at full strength.
    case word
    /// Active word bold, already-sung words full strength, upcoming words dimmed.
    case wordDimmed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lineOnly: return "Line Only"
        case .word: return "Word"
        case .wordDimmed: return "Word + Dimmed"
        }
    }

    var icon: String {
        switch self {
        case .lineOnly: return "text.alignleft"
        case .word: return "highlighter"
        case .wordDimmed: return "character.cursor.ibeam"
        }
    }

    /// Whether this style renders per-word (karaoke). `.lineOnly` bypasses all per-frame work.
    var isWordLevel: Bool { self != .lineOnly }
}

/// Color of the currently-sung word (#113 Slice 3). Only the active word takes this color; sung
/// and upcoming words keep their per-style treatment.
enum LyricHighlightColor: String, CaseIterable, Identifiable {
    case accent
    case yellow
    case green
    case blue
    case pink
    case orange

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accent: return "Accent"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .pink: return "Pink"
        case .orange: return "Orange"
        }
    }

    var swatch: Color {
        switch self {
        case .accent: return .accentColor
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .pink: return .pink
        case .orange: return .orange
        }
    }
}

// MARK: - Synced Lyrics Content

private struct SyncedLyricsContent: View {
    let lyrics: StructuredLyrics
    let engine: AudioEngine
    let songId: String

    @State private var activeLineIndex: Int = 0
    /// User timing nudge for this song, in ms (#86). Persisted per song.
    @State private var userOffsetMs: Int = 0
    @AppStorage(UserDefaultsKeys.lyricHighlightStyle) private var highlightStyle: LyricHighlightStyle = .wordDimmed
    @AppStorage(UserDefaultsKeys.lyricHighlightColor) private var highlightColor: LyricHighlightColor = .accent
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false
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
                            if let artist = lyrics.displayArtist ?? engine.currentSong?.displayArtist {
                                Text(artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    }

                    ForEach(Array((lyrics.line ?? []).enumerated()), id: \.offset) { index, line in
                        lineContent(index: index, line: line)
                            .multilineTextAlignment(.center)
                            .opacity(index == activeLineIndex ? 1.0 : 0.5)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 4)
                            .id(index)
                            .accessibilityIdentifier("lyricsLine_\(index)")
                            .onTapGesture {
                                if lyrics.synced, let start = line.start {
                                    engine.seek(to: Double(max(0, start - userOffsetMs)) / 1000.0)
                                }
                            }
                    }

                    Spacer(minLength: 100)
                }
            }
            .onChange(of: activeLineIndex) { _, newIndex in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onReceive(timer) { _ in
                updateActiveLine()
            }
            .onAppear {
                userOffsetMs = UserDefaults.standard.integer(
                    forKey: UserDefaultsKeys.lyricsOffset(songId: songId)
                )
                updateActiveLine()
            }
            .safeAreaInset(edge: .bottom) {
                if lyrics.synced {
                    timingControlBar
                }
            }
        }
    }

    // MARK: - Timing Nudge (#86)

    private var timingControlBar: some View {
        HStack(spacing: 20) {
            Button { adjustOffset(by: -100) } label: {
                Image(systemName: "minus")
                    .frame(minWidth: 28)
            }
            .accessibilityIdentifier("lyricsOffsetDecrease")
            .accessibilityLabel("Lyrics later")

            VStack(spacing: 1) {
                Text(offsetLabel)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                Text("Lyric Timing")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 96)

            Button { adjustOffset(by: 100) } label: {
                Image(systemName: "plus")
                    .frame(minWidth: 28)
            }
            .accessibilityIdentifier("lyricsOffsetIncrease")
            .accessibilityLabel("Lyrics earlier")

            if userOffsetMs != 0 {
                Button { setOffset(0) } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityIdentifier("lyricsOffsetReset")
                .accessibilityLabel("Reset lyric timing")
            }
        }
        .buttonStyle(.bordered)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var offsetLabel: String {
        guard userOffsetMs != 0 else { return "In sync" }
        return String(format: "%+.1fs", Double(userOffsetMs) / 1000.0)
    }

    private func adjustOffset(by deltaMs: Int) {
        // Clamp to a sane range so a stuck button can't run away.
        setOffset(max(-5000, min(5000, userOffsetMs + deltaMs)))
    }

    private func setOffset(_ ms: Int) {
        userOffsetMs = ms
        UserDefaults.standard.set(ms, forKey: UserDefaultsKeys.lyricsOffset(songId: songId))
        updateActiveLine()
    }

    private func updateActiveLine() {
        guard lyrics.synced else { return }
        // Line selection + auto-scroll stay on the lightweight 0.5s-sampled clock. The active
        // word within this line is driven separately at frame rate by KaraokeLineView (#113).
        let nowMs = max(0, Int(engine.currentTime * 1000) + (lyrics.offset ?? 0) + userOffsetMs)
        let lines = lyrics.line ?? []

        var newIndex = 0
        for (index, line) in lines.enumerated() {
            if let start = line.start, nowMs >= start {
                newIndex = index
            }
        }

        if newIndex != activeLineIndex {
            activeLineIndex = newIndex
        }
    }

    // MARK: - Word-level rendering (#113)

    /// The line's rendered content. The active line gets frame-rate word highlighting (via
    /// `KaraokeLineView`) only when a word-level style is selected AND clean cue data exists.
    /// Everything else — every non-active line, `.lineOnly`, unsynced lyrics, `.lrc`/`.txt`, old
    /// servers, LRCLIB, and any line whose cues don't reconstruct — stays on the line-level path.
    @ViewBuilder
    private func lineContent(index: Int, line: LyricLine) -> some View {
        if index == activeLineIndex, highlightStyle.isWordLevel,
           let cueLine = cueLine(for: index), cueLine.cuesReconstructValue {
            KaraokeLineView(
                cueLine: cueLine,
                engine: engine,
                baseOffsetMs: (lyrics.offset ?? 0) + userOffsetMs,
                dimUpcoming: highlightStyle == .wordDimmed,
                highlightColor: highlightColor.swatch
            )
            .font(.title3)
        } else {
            Text(line.value.isEmpty ? "♪" : line.value)
                .font(.title3)
                .fontWeight(index == activeLineIndex ? .bold : .regular)
                .foregroundStyle(index == activeLineIndex ? .primary : .secondary)
        }
    }

    /// The word-level cues for a line row, matched by the server's 0-based `index` (positional
    /// fallback). Returns nil when the track has no cue data for that row.
    private func cueLine(for lineIndex: Int) -> CueLine? {
        guard let cueLines = lyrics.cueLine, !cueLines.isEmpty else { return nil }
        if let match = cueLines.first(where: { $0.index == lineIndex }) { return match }
        return lineIndex < cueLines.count ? cueLines[lineIndex] : nil
    }
}

// MARK: - Karaoke Line (#113 Slice 2)

/// Renders one word-synced line with frame-rate word highlighting. A `TimelineView(.animation)`
/// re-reads the live AVPlayer position (`engine.smoothCurrentTime`) up to 30fps while playing —
/// smoother than the 0.5s periodic observer without touching it — and pauses when playback stops.
/// Only ever instantiated for the single active line under a word-level style, so per-frame cost
/// is one small `Text` rebuild.
private struct KaraokeLineView: View {
    let cueLine: CueLine
    let engine: AudioEngine
    /// `lyrics.offset` + the user's timing nudge, applied to the live clock.
    let baseOffsetMs: Int
    /// `.wordDimmed` dims not-yet-sung words; `.word` keeps them full strength.
    let dimUpcoming: Bool
    /// Color of the currently-sung word (#113 Slice 3).
    let highlightColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !engine.isPlaying)) { _ in
            let currentMs = max(0, Int(engine.smoothCurrentTime * 1000) + baseOffsetMs)
            styledText(currentMs: currentMs)
        }
    }

    /// Concatenated per-word-styled text. Words already sung render primary, the current word
    /// bold, upcoming words dimmed (only in `.wordDimmed`). Uses each cue's own `value` (verified
    /// to reconstruct the line), so no UTF-8 byte slicing happens on this path.
    private func styledText(currentMs: Int) -> Text {
        let cues = cueLine.cue ?? []
        var activeCue = -1
        for (i, cue) in cues.enumerated() where cue.start.map({ currentMs >= $0 }) ?? false {
            activeCue = i
        }

        return cues.enumerated().reduce(Text("")) { result, entry in
            let (i, cue) = entry
            let segment: Text
            if i == activeCue {
                segment = Text(cue.value).foregroundStyle(highlightColor).bold()
            } else if i < activeCue {
                segment = Text(cue.value).foregroundStyle(Color.primary)
            } else {
                segment = Text(cue.value).foregroundStyle(dimUpcoming ? Color.secondary : Color.primary)
            }
            return result + segment
        }
    }
}
