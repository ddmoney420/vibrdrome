import SwiftUI
import SwiftData
import Nuke
#if os(iOS)
import AVKit
#endif

struct NowPlayingView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) private var dismiss
    @State var showQueue = false
    @State var showEQ = false
    @State var isStarred = false
    @State var currentRating: Int = 0
    @State private var sliderValue: Double = 0
    @State private var isDragging = false
    @State private var albumImage: PlatformImage?
    @State private var loadedCoverArtId: String?
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false
    @AppStorage(UserDefaultsKeys.disableVisualizer) var disableVisualizer = false
    @AppStorage(UserDefaultsKeys.crossfadeDuration) var crossfadeDuration: Int = 0
    @AppStorage(UserDefaultsKeys.showVisualizerInToolbar) var showVisualizerInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showEQInToolbar) var showEQInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showAirPlayInToolbar) var showAirPlayInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showLyricsInToolbar) var showLyricsInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showSettingsInToolbar) var showSettingsInToolbar: Bool = true
    @State var showQuickSettings = false
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @State private var nsWindow: NSWindow?
    #endif

    var engine: AudioEngine { AudioEngine.shared }

    private var artWidth: CGFloat {
        340 // Used by macOS path; iOS uses GeometryReader
    }

    @State private var dragOffset: CGFloat = 0
    @State private var appearScale: CGFloat = 0.95
    @State private var appearOpacity: Double = 0

    var body: some View {
        mainContent
            .scaleEffect(appearScale)
            .opacity(appearOpacity)
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
            .sheet(isPresented: $showQuickSettings) {
                quickSettingsSheet
                    .environment(appState)
            }
            .fullScreenCover(isPresented: Bindable(appState).showVisualizer) {
                VisualizerView()
            }
            #endif
            .onAppear {
                isStarred = engine.currentSong?.starred != nil
                currentRating = engine.currentSong?.userRating ?? 0
                withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
                    appearScale = 1.0
                    appearOpacity = 1.0
                }
            }
            .onChange(of: engine.currentSong?.id) {
                isStarred = engine.currentSong?.starred != nil
                currentRating = engine.currentSong?.userRating ?? 0
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

                controlsToolbar
                    .padding(.bottom, 6)

                progressSlider
                    .padding(.bottom, 10)

                playbackControls
                    .padding(.bottom, 8)

                actionsToolbar
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
            let controlsNeeded: CGFloat = 420
            let maxArtFromWidth = geo.size.width - 60
            let maxArtFromHeight = geo.size.height - controlsNeeded
            let artSize = max(100, min(maxArtFromWidth, maxArtFromHeight))

            VStack(spacing: 0) {
                dismissHandle

                Spacer(minLength: 4)

                albumArt(size: artSize)

                Spacer(minLength: 8)

                iOSSongInfo
                    .padding(.bottom, 10)

                heartRow
                    .padding(.bottom, 12)

                progressSlider
                    .padding(.bottom, 4)

                streamingInfo
                    .padding(.bottom, 16)

                iOSPlaybackRow
                    .padding(.bottom, 16)

                volumeSlider
                    .padding(.bottom, 14)

                bottomToolbar

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 28)
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
        Capsule()
            .fill(.white.opacity(0.5))
            .frame(width: 36, height: 5)
            .padding(.top, 12)
            .padding(.bottom, 8)
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
        #if os(iOS)
        .onTapGesture {
            guard let albumId = engine.currentSong?.albumId else { return }
            appState.pendingNavigation = .album(id: albumId)
            appState.showNowPlaying = false
        }
        .contextMenu {
            if let albumImage {
                Button {
                    UIImageWriteToSavedPhotosAlbum(albumImage, nil, nil, nil)
                    Haptics.success()
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }

                ShareLink(
                    item: Image(uiImage: albumImage),
                    preview: SharePreview(
                        engine.currentSong?.title ?? "Album Art",
                        image: Image(uiImage: albumImage)
                    )
                )
            }
        }
        #endif
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
        if song != nil {
            HStack(spacing: 6) {
                if let year = song?.year {
                    badgeText(String(year))
                }
                if let genre = song?.genre {
                    Button {
                        appState.pendingNavigation = .genre(name: genre)
                        appState.showNowPlaying = false
                    } label: {
                        badgeText(genre)
                    }
                    .buttonStyle(.plain)
                }
                if let bitRate = song?.bitRate {
                    badgeText("\(bitRate) kbps")
                }
                if let suffix = song?.suffix {
                    badgeText(suffix.uppercased())
                }
            }
        }
    }

    private func badgeText(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.15), in: Capsule())
            .foregroundColor(.white.opacity(0.8))
    }

    // MARK: - Progress

    private var progressSlider: some View {
        let songDuration = engine.duration > 0 ? engine.duration : Double(engine.currentSong?.duration ?? 1)
        return VStack(spacing: 4) {
            #if os(iOS)
            GeometryReader { geo in
                let fraction = songDuration > 0 ? sliderValue / songDuration : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: 4)

                    Capsule()
                        .fill(.white)
                        .frame(width: geo.size.width * fraction, height: 4)

                    // Small dot thumb
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .offset(x: geo.size.width * fraction - 5)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let frac = max(0, min(1, value.location.x / geo.size.width))
                            sliderValue = songDuration * frac
                        }
                        .onEnded { value in
                            let frac = max(0, min(1, value.location.x / geo.size.width))
                            sliderValue = songDuration * frac
                            engine.seek(to: sliderValue)
                            isDragging = false
                        }
                )
            }
            .frame(height: 20)
            .accessibilityLabel("Track Progress")
            .onChange(of: engine.currentTime) { _, newTime in
                if !isDragging { sliderValue = newTime }
            }
            #else
            Slider(
                value: $sliderValue,
                in: 0...max(songDuration, 1)
            ) { editing in
                isDragging = editing
                if !editing { engine.seek(to: sliderValue) }
            }
            .tint(.white)
            .accessibilityLabel("Track Progress")
            .onChange(of: engine.currentTime) { _, newTime in
                if !isDragging { sliderValue = newTime }
            }
            #endif

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
                .accessibilityIdentifier("previousButton")

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
                .accessibilityIdentifier("playPauseButton")

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
                .accessibilityIdentifier("nextButton")
            }
        }
        .foregroundColor(.white)
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Toolbar

    var repeatAccessibilityValue: String {
        switch engine.repeatMode {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }

    // MARK: - Star Rating

    var starRating: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= currentRating ? "star.fill" : "star")
                    .font(.system(size: 16))
                    .foregroundColor(star <= currentRating ? .yellow : .white.opacity(0.5))
                    .onTapGesture {
                        #if os(iOS)
                        Haptics.light()
                        #endif
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

    // MARK: - Controls Toolbar (above progress bar, macOS only)

    #if os(macOS)
    private var controlsToolbar: some View {
        HStack(spacing: 0) {
            Button { engine.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .foregroundColor(engine.shuffleEnabled ? .white : .white.opacity(0.5))
            }
            .accessibilityLabel("Shuffle")
            .accessibilityValue(engine.shuffleEnabled ? "On" : "Off")
            .accessibilityIdentifier("shuffleButton")

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
                HStack(spacing: 4) {
                    Image(systemName: SleepTimer.shared.isActive ? "moon.fill" : "moon")
                        .foregroundColor(SleepTimer.shared.isActive ? .white : .white.opacity(0.5))
                    if SleepTimer.shared.isActive {
                        Text(formatSleepTime(SleepTimer.shared.remainingSeconds))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityLabel("Sleep Timer")
            .accessibilityIdentifier("sleepTimerMenu")

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
                    .foregroundColor(engine.playbackRate != 1.0 ? .white : .white.opacity(0.5))
            }
            .accessibilityLabel("Playback Speed")
            .accessibilityIdentifier("playbackSpeedMenu")

            Spacer()

            Button { showEQ = true } label: {
                Image(systemName: "slider.vertical.3")
                    .foregroundColor(
                        engine.eqEnabled
                            ? .white
                            : EQEngine.shared.currentPresetId != "flat"
                                ? .white.opacity(0.7) : .white.opacity(0.5)
                    )
            }
            .accessibilityLabel("Equalizer")
            .accessibilityValue(engine.eqEnabled ? "Active" : "Inactive")
            .accessibilityIdentifier("eqButton")

            Spacer()

            Button { appState.showLyrics = true } label: {
                Image(systemName: "quote.bubble")
                    .foregroundColor(.white.opacity(0.5))
            }
            .accessibilityLabel("Lyrics")
            .accessibilityIdentifier("lyricsButton")

            Spacer()

            Button { engine.cycleRepeatMode() } label: {
                Image(systemName: engine.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundColor(engine.repeatMode != .off ? .white : .white.opacity(0.5))
            }
            .accessibilityLabel("Repeat")
            .accessibilityValue(repeatAccessibilityValue)
            .accessibilityIdentifier("repeatButton")
        }
        .font(.body)
        .buttonStyle(.plain)
        .foregroundColor(.white.opacity(0.5))
    }

    // MARK: - Actions Toolbar (below playback controls, macOS only)

    private var actionsToolbar: some View {
        HStack(spacing: 0) {
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
                    .foregroundColor(isStarred ? .pink : .white.opacity(0.5))
            }
            .accessibilityLabel(isStarred ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityIdentifier("favoriteButton")

            Spacer()

            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Show Queue")
            .accessibilityIdentifier("queueButton")

            Spacer()

            Button {
                nsWindow?.collectionBehavior.insert(.fullScreenPrimary)
                nsWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityLabel("Toggle Full Screen")
        }
        .font(.body)
        .buttonStyle(.plain)
        .foregroundColor(.white.opacity(0.5))
    }
    #endif

    func formatSleepTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return "\(m):\(String(format: "%02d", s))"
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
