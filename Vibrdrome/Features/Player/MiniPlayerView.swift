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

    #if os(iOS)
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
    #else
    private func loadDominantColor() async {
        dominantColor = nil
    }
    #endif
}

// MARK: - Spinning Album Art (isolated subview to prevent parent re-renders)

private struct SpinningAlbumArt: View {
    let coverArtId: String?
    let shouldSpin: Bool
    let disableSpinningArt: Bool
    let reduceMotion: Bool

    @State private var angle: Double = 0
    @State private var timer: Timer?

    var body: some View {
        AlbumArtView(coverArtId: coverArtId, size: 40, cornerRadius: 20)
            .drawingGroup()
            .rotationEffect(.degrees(angle))
            .onAppear { startIfNeeded() }
            .onDisappear { stop() }
            .onChange(of: shouldSpin) { _, spinning in
                if spinning { startIfNeeded() } else { stop() }
            }
    }

    private func startIfNeeded() {
        guard shouldSpin, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
            Task { @MainActor in
                angle += 1.5
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - macOS Player Bar

#if os(macOS)
struct MacMiniPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        VStack(spacing: 0) {
            // Thin progress bar across full width
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
            .frame(height: 3)

            HStack(spacing: 16) {
                // Album art
                AlbumArtView(
                    coverArtId: engine.currentSong?.coverArt,
                    size: 40,
                    cornerRadius: 6
                )

                // Song info
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 120, alignment: .leading)

                Spacer()

                // Transport controls — centered
                HStack(spacing: 16) {
                    Button { engine.previous() } label: {
                        Image(systemName: "backward.fill")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous Track")

                    Button { engine.togglePlayPause() } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")

                    Button { engine.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.queue.isEmpty)
                    .accessibilityLabel("Next Track")
                }

                Spacer()

                // Volume slider
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Slider(value: Binding(
                        get: { engine.volume },
                        set: { engine.volume = $0 }
                    ).animation(nil), in: 0...1)
                    .frame(width: 100)
                    .accessibilityLabel("Volume")

                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                // Pop-out mini player
                Button {
                    openWindow(id: "mini-player")
                } label: {
                    Image(systemName: "pip.enter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Pop out mini player")
                .accessibilityLabel("Pop Out Mini Player")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture {
            openWindow(id: "now-playing")
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
            return song.artist ?? ""
        }
        if engine.currentRadioStation != nil {
            return "Internet Radio"
        }
        return ""
    }
}

// MARK: - Pop-Out Mini Player (floating window)

struct PopOutPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false

    private var engine: AudioEngine { AudioEngine.shared }

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
                // Album art
                AlbumArtView(
                    coverArtId: engine.currentSong?.coverArt,
                    size: 52,
                    cornerRadius: 8
                )
                .onTapGesture {
                    openWindow(id: "now-playing")
                }

                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.currentSong?.title ?? engine.currentRadioStation?.name ?? "Not Playing")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(engine.currentSong?.artist ?? (engine.currentRadioStation != nil ? "Internet Radio" : ""))
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
        .background(.bar)
        .frame(width: 320, height: 76)
    }
}
#endif
