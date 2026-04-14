import SwiftUI
import SwiftData
import Nuke
#if os(iOS)
import AVKit
#endif

struct NowPlayingView: View {
    var isInline: Bool = false

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
    @AppStorage(UserDefaultsKeys.nowPlayingToolbarOrder) var toolbarOrderJSON: String = "[]"
    @AppStorage(UserDefaultsKeys.showVolumeSlider) var showVolumeSlider: Bool = true
    @AppStorage(UserDefaultsKeys.showAudioQualityInfo) var showAudioQualityInfo: Bool = true
    @AppStorage(UserDefaultsKeys.showHeartInPlayer) var showHeartInPlayer: Bool = true
    @AppStorage(UserDefaultsKeys.showRatingInPlayer) var showRatingInPlayer: Bool = true
    @AppStorage(UserDefaultsKeys.showQueueInPlayer) var showQueueInPlayer: Bool = true
    @State var showQuickSettings = false
    #if os(macOS)
    @Environment(\.openWindow) var openWindow
    @State var nsWindow: NSWindow?
    @State var macSheet: MacNowPlayingSheet?
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
            .task(id: engine.currentSong?.id ?? engine.currentRadioStation?.id) {
                await loadAlbumArt()
            }
            #if os(macOS)
            .sheet(item: $macSheet) { sheet in
                switch sheet {
                case .queue:
                    QueueView()
                        .environment(appState)
                        .frame(minWidth: 480, idealWidth: 540, minHeight: 600, idealHeight: 720)
                case .lyrics:
                    if let song = engine.currentSong {
                        LyricsView(songId: song.id)
                            .environment(appState)
                            .frame(minWidth: 480, idealWidth: 540, minHeight: 600, idealHeight: 720)
                    }
                case .eq:
                    EQView()
                        .frame(minWidth: 480, idealWidth: 540, minHeight: 480, idealHeight: 560)
                }
            }
            .onChange(of: showQueue) { _, newValue in
                if newValue {
                    if isInline {
                        appState.activeSidePanel = (appState.activeSidePanel == .queue) ? nil : .queue
                    } else {
                        macSheet = .queue
                    }
                    showQueue = false
                }
            }
            .onChange(of: showEQ) { _, newValue in
                if newValue { macSheet = .eq; showEQ = false }
            }
            .onChange(of: appState.showLyrics) { _, newValue in
                if newValue {
                    if isInline {
                        appState.activeSidePanel = (appState.activeSidePanel == .lyrics) ? nil : .lyrics
                    } else {
                        macSheet = .lyrics
                    }
                    appState.showLyrics = false
                }
            }
            #else
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
            #endif
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
                #if os(macOS)
                if let next = consumePendingAction(appState) { macSheet = next }
                #endif
            }
            #if os(macOS)
            .onChange(of: appState.pendingNowPlayingAction) { _, _ in
                if let next = consumePendingAction(appState) { macSheet = next }
            }
            #endif
            .onChange(of: engine.currentSong?.id) {
                isStarred = engine.currentSong?.starred != nil
                currentRating = engine.currentSong?.userRating ?? 0
                isDragging = false
                sliderValue = 0
                Task { await loadAlbumArt() }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        #if os(macOS)
        GeometryReader { geo in
            let controlsNeeded: CGFloat = 480
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
                    .padding(.bottom, 6)

                if showAudioQualityInfo {
                    streamingInfo
                        .padding(.bottom, 8)
                }

                playbackControls
                    .padding(.bottom, 8)

                if showRatingInPlayer {
                    starRating
                        .padding(.bottom, 10)
                }

                if showVolumeSlider {
                    macVolumeSlider
                        .padding(.bottom, 10)
                }

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
            let controlsNeeded: CGFloat = 460
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

                if showAudioQualityInfo {
                    streamingInfo
                        .padding(.bottom, 16)
                }

                iOSPlaybackRow
                    .padding(.bottom, 16)

                if showVolumeSlider {
                    volumeSlider
                        .padding(.bottom, 14)
                }

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
        .onTapGesture { handleAlbumArtTap() }
        .contextMenu { albumArtContextMenu }
    }

    private func handleAlbumArtTap() {
        #if os(iOS)
        guard let albumId = engine.currentSong?.albumId else { return }
        appState.pendingNavigation = .album(id: albumId)
        appState.showNowPlaying = false
        #else
        if isInline {
            appState.activeSidePanel = (appState.activeSidePanel == .queue) ? nil : .queue
        } else {
            guard let albumId = engine.currentSong?.albumId else { return }
            appState.pendingNavigation = .album(id: albumId)
            dismiss()
        }
        #endif
    }

    @ViewBuilder
    private var albumArtContextMenu: some View {
        if let albumImage {
            #if os(iOS)
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
            #else
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([albumImage])
            } label: {
                Label("Copy Album Art", systemImage: "doc.on.doc")
            }
            Button {
                saveAlbumArtToDownloads(albumImage, title: engine.currentSong?.title)
            } label: {
                Label("Save to Downloads", systemImage: "square.and.arrow.down")
            }
            #endif
        }
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
                let fraction = songDuration > 0 ? min(1, max(0, sliderValue / songDuration)) : 0
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

    // MARK: - Streaming Info (cross-platform)

    var streamingInfo: some View {
        Group {
            if let song = engine.currentSong {
                let downloaded = isCurrentSongDownloaded
                let suffix = song.suffix?.uppercased() ?? "—"
                VStack(spacing: 2) {
                    if downloaded {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 9))
                            Text("Downloaded · \(suffix)")
                        }
                    } else {
                        let bitRate = song.bitRate.map { "\($0) kbps" } ?? "—"
                        HStack(spacing: 4) {
                            Image(systemName: "wifi")
                                .font(.system(size: 9))
                            Text("\(bitRate) · \(suffix)")
                        }
                    }
                    if let rg = song.replayGain {
                        replayGainInfo(rg)
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func replayGainInfo(_ rg: ReplayGain) -> some View {
        let parts = [
            rg.trackGain.map { String(format: "T: %+.1f dB", $0) },
            rg.albumGain.map { String(format: "A: %+.1f dB", $0) },
        ].compactMap { $0 }
        if !parts.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 9))
                Text("RG " + parts.joined(separator: " · "))
            }
        }
    }

    var isCurrentSongDownloaded: Bool {
        guard let songId = engine.currentSong?.id else { return false }
        let modelContext = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
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

    func formatSleepTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}

// MARK: - macOS Sheet Coordinator

#if os(macOS)
enum MacNowPlayingSheet: String, Identifiable {
    case queue, lyrics, eq
    var id: String { rawValue }
}

@MainActor
func consumePendingAction(_ appState: AppState) -> MacNowPlayingSheet? {
    guard let action = appState.pendingNowPlayingAction else { return nil }
    appState.pendingNowPlayingAction = nil
    switch action {
    case .showQueue: return .queue
    case .showLyrics: return .lyrics
    }
}

func saveAlbumArtToDownloads(_ image: NSImage, title: String?) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    let safeTitle = (title ?? "Album Art").replacingOccurrences(of: "/", with: "_")
    let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser
    let url = downloads.appendingPathComponent("\(safeTitle).png")
    try? png.write(to: url)
}
#endif

// MARK: - Toolbar Item Identifiers

enum NowPlayingToolbarItem: String, CaseIterable, Identifiable {
    case visualizer
    case eq
    case airplay
    case lyrics
    case settings

    var id: String { rawValue }

    static let defaultOrder: [NowPlayingToolbarItem] = [.visualizer, .eq, .airplay, .lyrics, .settings]

    static func decodeOrder(from json: String) -> [NowPlayingToolbarItem] {
        guard let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data),
              !ids.isEmpty
        else {
            return defaultOrder
        }
        let mapped = ids.compactMap { NowPlayingToolbarItem(rawValue: $0) }
        // Append any missing items at the end
        let missing = defaultOrder.filter { item in !mapped.contains(item) }
        return mapped + missing
    }

    static func encodeOrder(_ items: [NowPlayingToolbarItem]) -> String {
        let ids = items.map(\.rawValue)
        guard let data = try? JSONEncoder().encode(ids),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
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
