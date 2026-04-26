import SwiftUI
import Nuke
import NukeUI

struct MiniPlayerView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false
    @AppStorage(UserDefaultsKeys.disableSpinningArt) private var disableSpinningArt = false
    @AppStorage(UserDefaultsKeys.enableMiniPlayerTint) private var enableMiniPlayerTint = false
    @AppStorage(UserDefaultsKeys.enableLiquidGlass) private var enableLiquidGlass = true
    @AppStorage(UserDefaultsKeys.enableMiniPlayerSwipe) private var enableMiniPlayerSwipe = true
    @State private var dominantColor: Color?

    private var engine: AudioEngine { AudioEngine.shared }

    private var shouldSpin: Bool {
        engine.isPlaying && !disableSpinningArt && !reduceMotion
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Tappable area: album art + song info opens Now Playing
                Button {
                    appState.showNowPlaying = true
                } label: {
                    HStack(spacing: 12) {
                        // Spinning album art with circular progress ring
                        ZStack {
                            // Progress ring background
                            Circle()
                                .stroke(.white.opacity(0.1), lineWidth: 2.5)
                                .frame(width: 48, height: 48)

                            // Progress ring
                            Circle()
                                .trim(from: 0, to: engine.duration > 0
                                      ? engine.currentTime / engine.duration : 0)
                                .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .frame(width: 48, height: 48)
                                .rotationEffect(.degrees(-90))
                                .animation(reduceMotion ? nil : .linear(duration: 0.5), value: engine.currentTime)

                            // Album art — circular, spinning
                            SpinningAlbumArt(
                                coverArtId: engine.currentSong?.coverArt
                                    ?? engine.currentRadioStation?.radioCoverArtId,
                                shouldSpin: shouldSpin,
                                disableSpinningArt: disableSpinningArt,
                                reduceMotion: reduceMotion
                            )
                        }

                        // Song info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)

                            Text(displaySubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now Playing")
                .accessibilityHint("Open full player")

                // Play/Pause — larger hit target
                if engine.isBuffering {
                    ProgressView()
                        .tint(.primary)
                        .frame(width: 36, height: 36)
                } else {
                    Button { engine.togglePlayPause() } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
                }

                // Next
                Button { engine.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(engine.queue.isEmpty)
                .accessibilityLabel("Next Track")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background {
            if enableMiniPlayerTint, let dominantColor {
                Capsule()
                    .fill(dominantColor.opacity(0.15))
            }
        }
        .background(.bar, in: Capsule())
        #if os(iOS)
        .modifier(ConditionalGlassModifier(enabled: enableLiquidGlass))
        #endif
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .accessibilityIdentifier("MiniPlayer")
        #if os(iOS)
        .contextMenu {
            if let song = engine.currentSong {
                if let albumId = song.albumId {
                    Button {
                        appState.pendingNavigation = .album(id: albumId)
                    } label: {
                        Label("Go to Album", systemImage: "square.stack")
                    }
                }
                if let artistId = song.artistId {
                    Button {
                        appState.pendingNavigation = .artist(id: artistId)
                    } label: {
                        Label("Go to Artist", systemImage: "music.mic")
                    }
                }
                Button {
                    AudioEngine.shared.addToQueueNext(song)
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }
                Button {
                    AudioEngine.shared.startRadioFromSong(song)
                } label: {
                    Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 50, coordinateSpace: .local)
                .onEnded { value in
                    guard enableMiniPlayerSwipe else { return }
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical) * 2 else { return }
                    if horizontal < -50 {
                        Haptics.light()
                        engine.next()
                    } else if horizontal > 50 {
                        Haptics.light()
                        engine.previous()
                    }
                }
        )
        #endif
        .task(id: engine.currentSong?.coverArt ?? engine.currentRadioStation?.id) {
            await loadDominantColor()
        }
        #if os(macOS)
        .sheet(isPresented: Bindable(appState).showNowPlaying) {
            NowPlayingView()
                .environment(appState)
                .frame(minWidth: 400, idealWidth: 440, minHeight: 600, idealHeight: 680)
        }
        #endif
    }

    private var displayTitle: String {
        if let song = engine.currentSong {
            return song.title
        }
        if let station = engine.currentRadioStation {
            return station.name
        }
        return ""
    }

    private var displaySubtitle: String {
        if let song = engine.currentSong {
            // Show "Up Next: [title]" if there's a next track, otherwise artist
            if let nextIndex = engine.queue.indices.first(where: {
                $0 == engine.currentIndex + 1
            }) {
                return "Next: \(engine.queue[nextIndex].title)"
            }
            return song.artist ?? ""
        }
        if engine.currentRadioStation != nil {
            return "Internet Radio"
        }
        return ""
    }

    private func loadDominantColor() async {
        let coverArtId = engine.currentSong?.coverArt
            ?? engine.currentRadioStation?.radioCoverArtId
        guard let coverArtId else {
            withAnimation { dominantColor = nil }
            return
        }
        let url = appState.subsonicClient.coverArtURL(id: coverArtId, size: 80)
        guard let image = try? await ImagePipeline.shared.image(for: url),
              let avgColor = image.averageColor else {
            withAnimation { dominantColor = nil }
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            dominantColor = Color(avgColor)
        }
    }
}

// MARK: - Spinning Album Art (isolated subview to prevent parent re-renders)

private struct SpinningAlbumArt: View {
    let coverArtId: String?
    let shouldSpin: Bool
    let disableSpinningArt: Bool
    let reduceMotion: Bool
    var size: CGFloat = 40

    /// Degrees of rotation accumulated at the moment the last pause/resume happened.
    @State private var accumulatedAngle: Double = 0
    /// The last time the spin was (re)started. Used to compute live angle from elapsed time.
    @State private var resumedAt: Date = .now

    /// Degrees per second — one full revolution every 12 seconds.
    private let degreesPerSecond: Double = 30

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !shouldSpin)) { context in
            let elapsed = shouldSpin ? context.date.timeIntervalSince(resumedAt) : 0
            let angle = accumulatedAngle + elapsed * degreesPerSecond
            AlbumArtView(coverArtId: coverArtId, size: size, cornerRadius: size / 2)
                .drawingGroup()
                .rotationEffect(.degrees(angle))
        }
        .onChange(of: shouldSpin) { wasSpinning, isSpinning in
            if wasSpinning && !isSpinning {
                // Pausing: freeze the current angle so we don't snap back on resume.
                let elapsed = Date.now.timeIntervalSince(resumedAt)
                accumulatedAngle += elapsed * degreesPerSecond
            } else if !wasSpinning && isSpinning {
                resumedAt = .now
            }
        }
    }
}

// MARK: - macOS Player Bar

#if os(macOS)
struct MacMiniPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("sidebarSelection") private var sidebarSelectionRaw: String = "artists"
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false
    @AppStorage(UserDefaultsKeys.enableMiniPlayerTint) private var enableMiniPlayerTint = false
    @AppStorage(UserDefaultsKeys.showHeartInPlayer) private var showHeartInPlayer = true
    @AppStorage(UserDefaultsKeys.showRatingInPlayer) private var showRatingInPlayer = true
    @State private var dominantColor: Color?
    @State private var sliderValue: Double = 0
    @State private var isDragging = false
    @State private var isStarred = false
    @State private var currentRating: Int = 0
    @State private var showEQ = false

    private func navigateToNowPlaying() {
        sidebarSelectionRaw = "nowPlaying"
    }

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: album art + track info + heart/rating
            HStack(spacing: 10) {
                AlbumArtView(
                    coverArtId: engine.currentSong?.coverArt
                        ?? engine.currentRadioStation?.radioCoverArtId,
                    size: 52,
                    cornerRadius: 4
                )
                .onTapGesture { navigateToNowPlaying() }

                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.currentSong?.title
                         ?? engine.currentRadioStation?.name
                         ?? "Not Playing")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let artist = engine.currentSong?.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if engine.currentRadioStation != nil {
                        Text("Internet Radio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let album = engine.currentSong?.album {
                        Text(album)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    if showHeartInPlayer || showRatingInPlayer {
                        HStack(spacing: 6) {
                            if showHeartInPlayer {
                                Button {
                                    guard let song = engine.currentSong else { return }
                                    let songId = song.id
                                    let wasStarred = isStarred
                                    isStarred = !wasStarred
                                    Task {
                                        do {
                                            if wasStarred {
                                                try await OfflineActionQueue.shared.unstar(id: songId)
                                            } else {
                                                try await OfflineActionQueue.shared.star(id: songId)
                                            }
                                        } catch {
                                            if engine.currentSong?.id == songId { isStarred = wasStarred }
                                        }
                                    }
                                } label: {
                                    Image(systemName: isStarred ? "heart.fill" : "heart")
                                        .font(.system(size: 9))
                                        .foregroundStyle(isStarred ? .pink : .secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isStarred ? "Remove from Favorites" : "Add to Favorites")
                            }

                            if showRatingInPlayer {
                                HStack(spacing: 3) {
                                    ForEach(1...5, id: \.self) { star in
                                        Image(systemName: star <= currentRating ? "star.fill" : "star")
                                            .font(.system(size: 9))
                                            .foregroundStyle(star <= currentRating ? .yellow : .secondary)
                                            .onTapGesture {
                                                let newRating = star == currentRating ? 0 : star
                                                currentRating = newRating
                                                guard let songId = engine.currentSong?.id else { return }
                                                Task {
                                                    try? await appState.subsonicClient.setRating(id: songId, rating: newRating)
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { navigateToNowPlaying() }
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            // CENTER: transport + seek bar
            VStack(spacing: 4) {
                HStack(spacing: 20) {
                    Button { engine.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .font(.caption)
                            .foregroundStyle(engine.shuffleEnabled ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Shuffle")

                    Button { engine.previous() } label: {
                        Image(systemName: "backward.fill")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous Track")

                    if engine.isBuffering {
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else {
                        Button { engine.togglePlayPause() } label: {
                            Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 32))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
                    }

                    Button { engine.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.queue.isEmpty)
                    .accessibilityLabel("Next Track")

                    Button { engine.cycleRepeatMode() } label: {
                        Image(systemName: engine.repeatMode == .one ? "repeat.1" : "repeat")
                            .font(.caption)
                            .foregroundStyle(engine.repeatMode != .off ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Repeat")
                }

                // Seek bar with timestamps
                let duration = engine.duration > 0 ? engine.duration : Double(engine.currentSong?.duration ?? 1)
                HStack(spacing: 6) {
                    Text(formatDuration(sliderValue))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)

                    Slider(
                        value: $sliderValue,
                        in: 0...max(duration, 1)
                    ) { editing in
                        isDragging = editing
                        if !editing { engine.seek(to: sliderValue) }
                    }
                    .tint(.primary)
                    .accessibilityLabel("Track Progress")
                    .onChange(of: engine.currentTime) { _, newTime in
                        if !isDragging { sliderValue = newTime }
                    }

                    Text("-\(formatDuration(max(0, duration - sliderValue)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .leading)
                }
            }
            .frame(maxWidth: 480)

            // RIGHT: secondary actions + volume
            HStack(spacing: 14) {
                Button {
                    appState.activeSidePanel = (appState.activeSidePanel == .queue) ? nil : .queue
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(appState.activeSidePanel == .queue ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help("Queue")
                .accessibilityLabel("Show Queue")

                Button {
                    appState.activeSidePanel = (appState.activeSidePanel == .lyrics) ? nil : .lyrics
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.caption)
                        .foregroundStyle(appState.activeSidePanel == .lyrics ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help("Lyrics")
                .accessibilityLabel("Show Lyrics")

                Button {
                    showEQ = true
                } label: {
                    Image(systemName: "slider.vertical.3")
                        .font(.caption)
                        .foregroundStyle(engine.eqEnabled ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help("Equalizer")
                .accessibilityLabel("Equalizer")
                .sheet(isPresented: $showEQ) {
                    EQView()
                        .frame(minWidth: 480, idealWidth: 540, minHeight: 480, idealHeight: 560)
                }

                Button {
                    openWindow(id: "visualizer")
                } label: {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Visualizer")
                .accessibilityLabel("Open Visualizer")

                HStack(spacing: 5) {
                    Image(systemName: "speaker.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Slider(value: Binding(
                        get: { Double(engine.userVolume) },
                        set: { engine.userVolume = Float($0) }
                    ).animation(nil), in: 0...1)
                    .frame(width: 80)
                    .accessibilityLabel("Volume")

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .background {
            ZStack {
                Rectangle().fill(.bar)
                if enableMiniPlayerTint, let dominantColor {
                    Rectangle()
                        .fill(dominantColor.opacity(0.15))
                }
            }
        }
        .contextMenu {
            if let song = engine.currentSong {
                if let albumId = song.albumId {
                    Button {
                        appState.pendingNavigation = .album(id: albumId)
                    } label: {
                        Label("Go to Album", systemImage: "square.stack")
                    }
                }
                if let artistId = song.artistId {
                    Button {
                        appState.pendingNavigation = .artist(id: artistId)
                    } label: {
                        Label("Go to Artist", systemImage: "music.mic")
                    }
                }
                Button {
                    AudioEngine.shared.addToQueueNext(song)
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }
                Button {
                    AudioEngine.shared.startRadioFromSong(song)
                } label: {
                    Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                }
            }
        }
        .onAppear {
            isStarred = engine.currentSong?.starred != nil
            currentRating = engine.currentSong?.userRating ?? 0
        }
        .onChange(of: engine.currentSong?.id) {
            isStarred = engine.currentSong?.starred != nil
            currentRating = engine.currentSong?.userRating ?? 0
            isDragging = false
            sliderValue = 0
        }
        .task(id: engine.currentSong?.coverArt ?? engine.currentRadioStation?.id) {
            await loadDominantColor()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    private func loadDominantColor() async {
        let coverArtId = engine.currentSong?.coverArt
            ?? engine.currentRadioStation?.radioCoverArtId
        guard let coverArtId else {
            withAnimation { dominantColor = nil }
            return
        }
        let url = appState.subsonicClient.coverArtURL(id: coverArtId, size: 80)
        guard let image = try? await ImagePipeline.shared.image(for: url),
              let avgColor = image.averageColor else {
            withAnimation { dominantColor = nil }
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            dominantColor = Color(avgColor)
        }
    }
}

// MARK: - Pop-Out Mini Player (floating window)

struct PopOutPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false
    @AppStorage(UserDefaultsKeys.disableSpinningArt) private var disableSpinningArt = false
    @AppStorage(UserDefaultsKeys.enableMiniPlayerTint) private var enableMiniPlayerTint = false
    @State private var dominantColor: Color?

    private var engine: AudioEngine { AudioEngine.shared }

    private var shouldSpin: Bool {
        engine.isPlaying && !disableSpinningArt && !reduceMotion
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.quaternary)
                    Rectangle()
                        .fill(.tint)
                        .frame(width: engine.duration > 0
                               ? geo.size.width * (engine.currentTime / engine.duration)
                               : 0)
                        .animation(reduceMotion ? nil : .linear(duration: 0.5), value: engine.currentTime)
                }
            }
            .frame(height: 2)

            HStack(spacing: 10) {
                // Spinning album art with circular progress ring
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 2.5)
                        .frame(width: 56, height: 56)

                    Circle()
                        .trim(from: 0, to: engine.duration > 0
                              ? engine.currentTime / engine.duration : 0)
                        .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 0.5), value: engine.currentTime)

                    SpinningAlbumArt(
                        coverArtId: engine.currentSong?.coverArt
                            ?? engine.currentRadioStation?.radioCoverArtId,
                        shouldSpin: shouldSpin,
                        disableSpinningArt: disableSpinningArt,
                        reduceMotion: reduceMotion,
                        size: 48
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    openWindow(id: "now-playing")
                }

                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Transport controls
                HStack(spacing: 12) {
                    Button { engine.previous() } label: {
                        Image(systemName: "backward.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous Track")

                    Button { engine.togglePlayPause() } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")

                    Button { engine.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.queue.isEmpty)
                    .accessibilityLabel("Next Track")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background {
            ZStack {
                Rectangle().fill(.bar)
                if enableMiniPlayerTint, let dominantColor {
                    Rectangle()
                        .fill(dominantColor.opacity(0.15))
                }
            }
        }
        .frame(width: 320, height: 84)
        .contextMenu {
            if let song = engine.currentSong {
                if let albumId = song.albumId {
                    Button {
                        appState.pendingNavigation = .album(id: albumId)
                    } label: {
                        Label("Go to Album", systemImage: "square.stack")
                    }
                }
                if let artistId = song.artistId {
                    Button {
                        appState.pendingNavigation = .artist(id: artistId)
                    } label: {
                        Label("Go to Artist", systemImage: "music.mic")
                    }
                }
                Button {
                    AudioEngine.shared.addToQueueNext(song)
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }
                Button {
                    AudioEngine.shared.startRadioFromSong(song)
                } label: {
                    Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                }
            }
        }
        .task(id: engine.currentSong?.coverArt ?? engine.currentRadioStation?.id) {
            await loadDominantColor()
        }
    }

    private var displayTitle: String {
        if let song = engine.currentSong {
            return song.title
        }
        if let station = engine.currentRadioStation {
            return station.name
        }
        return "Not Playing"
    }

    private var displaySubtitle: String {
        if let song = engine.currentSong {
            let nextIndex = engine.currentIndex + 1
            if engine.queue.indices.contains(nextIndex) {
                return "Next: \(engine.queue[nextIndex].title)"
            }
            return song.artist ?? ""
        }
        if engine.currentRadioStation != nil {
            return "Internet Radio"
        }
        return ""
    }

    private func loadDominantColor() async {
        let coverArtId = engine.currentSong?.coverArt
            ?? engine.currentRadioStation?.radioCoverArtId
        guard let coverArtId else {
            withAnimation { dominantColor = nil }
            return
        }
        let url = appState.subsonicClient.coverArtURL(id: coverArtId, size: 80)
        guard let image = try? await ImagePipeline.shared.image(for: url),
              let avgColor = image.averageColor else {
            withAnimation { dominantColor = nil }
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            dominantColor = Color(avgColor)
        }
    }
}
#endif
