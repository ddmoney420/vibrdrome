import SwiftUI
import Nuke
#if os(iOS)
import AVKit
#endif

struct NowPlayingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showVisualizer = false
    @State private var isStarred = false
    @State private var sliderValue: Double = 0
    @State private var isDragging = false
    @State private var albumImage: PlatformImage?
    @State private var loadedCoverArtId: String?
    @AppStorage("reduceMotion") private var reduceMotion = false
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @State private var nsWindow: NSWindow?
    #endif

    private var engine: AudioEngine { AudioEngine.shared }

    private var artWidth: CGFloat {
        #if os(iOS)
        min(UIScreen.main.bounds.width - 150, 400)
        #else
        340
        #endif
    }

    var body: some View {
        mainContent
            .task(id: engine.currentSong?.coverArt) {
                await loadAlbumArt()
            }
            .sheet(isPresented: $showQueue) {
                QueueView()
                    .environment(appState)
            }
            .sheet(isPresented: $showLyrics) {
                if let song = engine.currentSong {
                    LyricsView(songId: song.id)
                        .environment(appState)
                }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showVisualizer) {
                VisualizerView()
            }
            #endif
            .onAppear {
                isStarred = engine.currentSong?.starred != nil
            }
            .onChange(of: engine.currentSong?.id) {
                isStarred = engine.currentSong?.starred != nil
                isDragging = false
                sliderValue = 0
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        #if os(macOS)
        GeometryReader { geo in
            let controlsNeeded: CGFloat = 360
            let artSize = max(150, min(geo.size.width - 120, geo.size.height - controlsNeeded))

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                albumArt(size: artSize)
                    .padding(.bottom, 12)

                songInfo
                    .padding(.bottom, 4)

                metadataBadges
                    .padding(.bottom, 4)

                Spacer(minLength: 0)

                progressSlider
                    .padding(.bottom, 10)

                playbackControls
                    .padding(.bottom, 10)

                bottomToolbar
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 40)
            .frame(width: geo.size.width, height: geo.size.height)
            .background {
                ZStack {
                    Color.black
                    if let albumImage {
                        Image(platformImage: albumImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 30)
                            .scaleEffect(1.5)
                            .saturation(1.3)
                            .clipped()
                            .overlay(Color.black.opacity(0.2))
                    }
                }
                .ignoresSafeArea()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: loadedCoverArtId)
            }
            .background { WindowReader { nsWindow = $0 }.allowsHitTesting(false) }
        }
        #else
        artworkBackground
            .overlay {
                VStack(spacing: 0) {
                    dismissHandle

                    albumArt(size: artWidth)
                        .padding(.top, 4)
                        .padding(.bottom, 8)

                    songInfo
                        .padding(.bottom, 4)

                    metadataBadges
                        .padding(.bottom, 2)

                    Spacer(minLength: 0)

                    progressSlider
                        .padding(.bottom, 10)

                    playbackControls
                        .padding(.bottom, 10)

                    bottomToolbar
                        .padding(.bottom, 6)
                }
                .padding(.horizontal, 40)
            }
        #endif
    }

    // MARK: - Image Loading

    private func loadAlbumArt() async {
        guard let coverArtId = engine.currentSong?.coverArt else {
            albumImage = nil
            loadedCoverArtId = nil
            return
        }
        if coverArtId == loadedCoverArtId, albumImage != nil { return }

        let url = appState.subsonicClient.coverArtURL(id: coverArtId, size: 800)
        do {
            let response = try await ImagePipeline.shared.image(for: url)
            guard engine.currentSong?.coverArt == coverArtId else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.3)) {
                albumImage = response
                loadedCoverArtId = coverArtId
            }
        } catch {}
    }

    // MARK: - Artwork Background

    private var artworkBackground: some View {
        ZStack {
            Color.black

            if let albumImage {
                Image(platformImage: albumImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 30)
                    .scaleEffect(1.5)
                    .saturation(1.3)
                    .clipped()
                    .overlay(Color.black.opacity(0.2))
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: loadedCoverArtId)
    }

    // MARK: - Dismiss Handle

    private var dismissHandle: some View {
        Capsule()
            .fill(.white.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
    }

    // MARK: - Album Art

    private func albumArt(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.1))

            if let albumImage {
                Image(platformImage: albumImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }

    // MARK: - Song Info

    private var songInfo: some View {
        VStack(spacing: 4) {
            Text(engine.currentSong?.title ?? "Not Playing")
                .font(.title3)
                .bold()
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(engine.currentSong?.artist ?? "")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Text(engine.currentSong?.album ?? "")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Metadata Badges

    @ViewBuilder
    private var metadataBadges: some View {
        let song = engine.currentSong
        let badges = buildBadges(song)
        if !badges.isEmpty {
            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.15), in: Capsule())
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }

    private func buildBadges(_ song: Song?) -> [String] {
        guard let song else { return [] }
        var result = [String]()
        if let year = song.year { result.append("\(year)") }
        if let genre = song.genre { result.append(genre) }
        if let bitRate = song.bitRate { result.append("\(bitRate) kbps") }
        if let suffix = song.suffix { result.append(suffix.uppercased()) }
        return result
    }

    // MARK: - Progress

    private var progressSlider: some View {
        let songDuration = engine.duration > 0 ? engine.duration : Double(engine.currentSong?.duration ?? 1)
        let displayTime = isDragging ? sliderValue : engine.currentTime
        return VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { displayTime },
                    set: { sliderValue = $0 }
                ),
                in: 0...max(songDuration, 1)
            ) { editing in
                isDragging = editing
                if !editing {
                    engine.seek(to: sliderValue)
                }
            }
            .tint(.white)

            HStack {
                Text(formatDuration(displayTime))
                Spacer()
                let remaining = songDuration - displayTime
                Text("-\(formatDuration(max(0, remaining)))")
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))
            .monospacedDigit()
        }
    }

    // MARK: - Controls

    private var playbackControls: some View {
        HStack(spacing: 44) {
            Button { engine.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }

            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }

            Button { engine.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
        }
        .foregroundColor(.white)
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack {
            Button { engine.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .foregroundColor(engine.shuffleEnabled ? .white : .white.opacity(0.4))
            }

            Spacer()

            Button { showLyrics = true } label: {
                Image(systemName: "text.quote")
            }
            .disabled(engine.currentSong == nil)

            Spacer()

            Button {
                #if os(macOS)
                openWindow(id: "visualizer")
                #else
                showVisualizer = true
                #endif
            } label: {
                Image(systemName: "waveform.path")
            }

            Spacer()

            Button {
                guard let song = engine.currentSong else { return }
                let songId = song.id
                let wasStarred = isStarred
                isStarred = !wasStarred
                Task {
                    do {
                        if wasStarred {
                            try await appState.subsonicClient.unstar(id: songId)
                        } else {
                            try await appState.subsonicClient.star(id: songId)
                            if UserDefaults.standard.bool(forKey: "autoDownloadFavorites") {
                                DownloadManager.shared.download(song: song, client: appState.subsonicClient)
                            }
                        }
                        guard engine.currentSong?.id == songId else { return }
                    } catch {
                        if engine.currentSong?.id == songId {
                            isStarred = wasStarred
                        }
                    }
                }
            } label: {
                Image(systemName: isStarred ? "heart.fill" : "heart")
                    .foregroundColor(isStarred ? .pink : .white.opacity(0.4))
            }

            Spacer()

            #if os(iOS)
            AirPlayButton()
                .frame(width: 24, height: 24)

            Spacer()
            #endif

            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
            }

            Spacer()

            Button { engine.cycleRepeatMode() } label: {
                Image(systemName: engine.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundColor(engine.repeatMode != .off ? .white : .white.opacity(0.4))
            }

            #if os(macOS)
            Spacer()

            Button {
                nsWindow?.collectionBehavior.insert(.fullScreenPrimary)
                nsWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            #endif
        }
        .font(.title3)
        .buttonStyle(.plain)
        .foregroundColor(.white.opacity(0.4))
    }
}

// MARK: - Cross-platform image helper

private extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

// MARK: - macOS Window Reader

#if os(macOS)
private struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}
#endif
