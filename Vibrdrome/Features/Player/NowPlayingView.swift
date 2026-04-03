import SwiftUI
import Nuke
#if os(iOS)
import AVKit
#endif

struct NowPlayingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showEQ = false
    @State private var isStarred = false
    @State private var sliderValue: Double = 0
    @State private var isDragging = false
    @State private var albumImage: PlatformImage?
    @State private var loadedCoverArtId: String?
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false
    @AppStorage(UserDefaultsKeys.disableVisualizer) private var disableVisualizer = false
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @State private var nsWindow: NSWindow?
    #endif

    private var engine: AudioEngine { AudioEngine.shared }

    private var artWidth: CGFloat {
        340 // Used by macOS path; iOS uses GeometryReader
    }

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        mainContent
            .offset(y: max(0, dragOffset))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 150 || value.predictedEndTranslation.height > 300 {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.3)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            .task(id: engine.currentSong?.coverArt ?? engine.currentRadioStation?.id) {
                await loadAlbumArt()
            }
            .sheet(isPresented: $showQueue) {
                QueueView()
                    .environment(appState)
            }
            .sheet(isPresented: Bindable(appState).showLyrics) {
                if let song = engine.currentSong {
                    LyricsView(songId: song.id)
                        .environment(appState)
                }
            }
            .sheet(isPresented: $showEQ) {
                EQView()
            }
            #if os(iOS)
            .fullScreenCover(isPresented: Bindable(appState).showVisualizer) {
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
        GeometryReader { geo in
            let controlsNeeded: CGFloat = 330
            let maxArtFromWidth = geo.size.width - 80
            let maxArtFromHeight = geo.size.height - controlsNeeded
            let artSize = max(100, min(maxArtFromWidth, maxArtFromHeight))

            VStack(spacing: 0) {
                dismissHandle

                albumArt(size: artSize)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                songInfo
                    .padding(.bottom, 2)

                metadataBadges
                    .padding(.bottom, 2)

                Spacer(minLength: 0)

                progressSlider
                    .padding(.bottom, 6)

                playbackControls
                    .padding(.bottom, 6)

                bottomToolbar
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 30)
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
        }
        #endif
    }

    // MARK: - Image Loading

    private func loadAlbumArt() async {
        // Try song coverArt first, then radio station artwork
        let coverArtId = engine.currentSong?.coverArt
            ?? engine.currentRadioStation?.radioCoverArtId

        guard let coverArtId else {
            albumImage = nil
            loadedCoverArtId = nil
            return
        }
        if coverArtId == loadedCoverArtId, albumImage != nil { return }

        let url = appState.subsonicClient.coverArtURL(id: coverArtId, size: 800)
        do {
            let response = try await ImagePipeline.shared.image(for: url)
            let currentId = engine.currentSong?.coverArt
                ?? engine.currentRadioStation?.radioCoverArtId
            guard currentId == coverArtId else { return }
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
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer()

            Capsule()
                .fill(.white.opacity(0.4))
                .frame(width: 36, height: 5)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
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
            if engine.isRadioMode {
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.caption2)
                    Text(engine.radioSeedArtistName ?? "Radio")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.15), in: Capsule())
                .foregroundColor(.white.opacity(0.8))
            }

            Text(engine.currentSong?.title ?? "Not Playing")
                .font(.title3)
                .bold()
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let artistId = engine.currentSong?.artistId {
                Button {
                    appState.pendingNavigation = .artist(id: artistId)
                    appState.showNowPlaying = false
                } label: {
                    Text(engine.currentSong?.artist ?? "")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .underline(color: .white.opacity(0.3))
                }
                .buttonStyle(.plain)
            } else {
                Text(engine.currentSong?.artist ?? "")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            if let albumId = engine.currentSong?.albumId {
                Button {
                    appState.pendingNavigation = .album(id: albumId)
                    appState.showNowPlaying = false
                } label: {
                    Text(engine.currentSong?.album ?? "")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .underline(color: .white.opacity(0.2))
                }
                .buttonStyle(.plain)
            } else {
                Text(engine.currentSong?.album ?? "")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
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
        if let year = song.year { result.append(String(year)) }
        if let genre = song.genre { result.append(genre) }
        if let bitRate = song.bitRate { result.append("\(bitRate) kbps") }
        if let suffix = song.suffix { result.append(suffix.uppercased()) }
        return result
    }

    // MARK: - Progress

    private var progressSlider: some View {
        let songDuration = engine.duration > 0 ? engine.duration : Double(engine.currentSong?.duration ?? 1)
        return VStack(spacing: 4) {
            Slider(
                value: $sliderValue,
                in: 0...max(songDuration, 1)
            ) { editing in
                isDragging = editing
                if !editing {
                    engine.seek(to: sliderValue)
                }
            }
            .tint(.white)
            .accessibilityLabel("Track Progress")
            .onChange(of: engine.currentTime) { _, newTime in
                if !isDragging {
                    sliderValue = newTime
                }
            }

            HStack {
                Text(formatDuration(sliderValue))
                Spacer()
                let remaining = songDuration - sliderValue
                Text("-\(formatDuration(max(0, remaining)))")
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))
            .monospacedDigit()
        }
    }

    // MARK: - Controls

    private var playbackControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 40) {
                Button {
                    #if os(iOS)
                    Haptics.light()
                    #endif
                    engine.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Previous Track")

                Button {
                    #if os(iOS)
                    Haptics.medium()
                    #endif
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }
                .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")

                Button {
                    #if os(iOS)
                    Haptics.light()
                    #endif
                    engine.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Next Track")
            }
        }
        .foregroundColor(.white)
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Toolbar

    private var repeatAccessibilityValue: String {
        switch engine.repeatMode {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }

    private var bottomToolbar: some View {
        VStack(spacing: 8) {
            // Row 1: Shuffle, Sleep, Speed, EQ, Lyrics, Repeat
            HStack {
                Button { engine.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundColor(engine.shuffleEnabled ? .white : .white.opacity(0.4))
                }
                .accessibilityLabel("Shuffle")
                .accessibilityValue(engine.shuffleEnabled ? "On" : "Off")

                Spacer()

                Menu {
                    if SleepTimer.shared.isActive {
                        Button {
                            SleepTimer.shared.stop()
                        } label: {
                            Label("Cancel Timer", systemImage: "xmark")
                        }
                    } else {
                        ForEach([15, 30, 45, 60, 120], id: \.self) { minutes in
                            Button {
                                SleepTimer.shared.start(mode: .minutes(minutes))
                            } label: {
                                Text(minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr")
                            }
                        }
                        Button {
                            SleepTimer.shared.start(mode: .endOfTrack)
                        } label: {
                            Text("End of Track")
                        }
                    }
                } label: {
                    Image(systemName: SleepTimer.shared.isActive ? "moon.fill" : "moon")
                        .foregroundColor(SleepTimer.shared.isActive ? .white : .white.opacity(0.4))
                }
                .accessibilityLabel("Sleep Timer")

                Spacer()

                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                        Button {
                            engine.playbackRate = Float(rate)
                        } label: {
                            HStack {
                                Text(rate == 1.0 ? "Normal" : "\(rate, specifier: "%.2g")x")
                                if engine.playbackRate == Float(rate) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(engine.playbackRate == 1.0 ? "1x" : "\(engine.playbackRate, specifier: "%.2g")x")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(engine.playbackRate != 1.0 ? .white : .white.opacity(0.4))
                }
                .accessibilityLabel("Playback Speed")

                Spacer()

                Button { showEQ = true } label: {
                    Image(systemName: "slider.vertical.3")
                        .foregroundColor(
                            engine.eqEnabled
                                ? .white
                                : EQEngine.shared.currentPresetId != "flat"
                                    ? .white.opacity(0.7) : .white.opacity(0.4)
                        )
                }
                .accessibilityLabel("Equalizer")
                .accessibilityValue(engine.eqEnabled ? "Active" : "Inactive")

                Spacer()

                Button { appState.showLyrics = true } label: {
                    Image(systemName: "quote.bubble")
                        .foregroundColor(.white.opacity(0.4))
                }
                .accessibilityLabel("Lyrics")

                Spacer()

                Button { engine.cycleRepeatMode() } label: {
                    Image(systemName: engine.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundColor(engine.repeatMode != .off ? .white : .white.opacity(0.4))
                }
                .accessibilityLabel("Repeat")
                .accessibilityValue(repeatAccessibilityValue)
            }

            // Row 2: Heart, Visualizer, AirPlay, Queue, Fullscreen
            HStack {
                Button {
                    #if os(iOS)
                    Haptics.success()
                    #endif
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
                                if UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoDownloadFavorites) {
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
                .accessibilityLabel(isStarred ? "Remove from Favorites" : "Add to Favorites")

                Spacer()

                #if os(iOS)
                if !disableVisualizer {
                    Button { appState.showVisualizer = true } label: {
                        Image(systemName: "waveform.path")
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .accessibilityLabel("Visualizer")

                    Spacer()
                }

                AirPlayButton()
                    .frame(width: 24, height: 24)

                Spacer()
                #endif

                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Show Queue")

                #if os(macOS)
                Spacer()

                Button {
                    nsWindow?.collectionBehavior.insert(.fullScreenPrimary)
                    nsWindow?.toggleFullScreen(nil)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Toggle Full Screen")
                #endif
            }
        }
        .font(.body)
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
