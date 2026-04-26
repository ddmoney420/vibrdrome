import SwiftUI

#if os(iOS)
// MARK: - iOS-specific views for NowPlayingView

extension NowPlayingView {

    // MARK: - iOS Song Info (title + artist + album)

    var iOSSongInfo: some View {
        VStack(spacing: 4) {
            // Source context — only shows when non-obvious
            if let sourceLabel = playingSourceLabel {
                Text(sourceLabel)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

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

            if let albumId = engine.currentSong?.albumId {
                Button {
                    appState.pendingNavigation = .album(id: albumId)
                    appState.showNowPlaying = false
                } label: {
                    Text(engine.currentSong?.title ?? "Not Playing")
                        .font(.title2)
                        .bold()
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
            } else {
                Text(engine.currentSong?.title ?? "Not Playing")
                    .font(.title2)
                    .bold()
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            if let artistId = engine.currentSong?.artistId {
                Button {
                    appState.pendingNavigation = .artist(id: artistId)
                    appState.showNowPlaying = false
                } label: {
                    Text(engine.currentSong?.artist ?? "")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            } else {
                Text(engine.currentSong?.artist ?? "")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            if let albumId = engine.currentSong?.albumId {
                Button {
                    appState.pendingNavigation = .album(id: albumId)
                    appState.showNowPlaying = false
                } label: {
                    Text(engine.currentSong?.album ?? "")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            } else if let album = engine.currentSong?.album {
                Text(album)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Heart Row (heart + stars)

    var heartRow: some View {
        HStack {
            if showHeartInPlayer {
                Button {
                    Haptics.success()
                    guard let song = engine.currentSong else { return }
                    let songId = song.id
                    let wasStarred = isStarred
                    isStarred = !wasStarred
                    NotificationCenter.default.post(
                        name: .songStarredChanged,
                        object: nil,
                        userInfo: ["id": songId, "starred": !wasStarred]
                    )
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
                                NotificationCenter.default.post(
                                    name: .songStarredChanged,
                                    object: nil,
                                    userInfo: ["id": songId, "starred": wasStarred]
                                )
                            }
                        }
                    }
                } label: {
                    Image(systemName: isStarred ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundColor(isStarred ? .pink : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isStarred ? "Remove from Favorites" : "Add to Favorites")
                .accessibilityIdentifier("favoriteButton")
            }

            Spacer()

            if showRatingInPlayer {
                // Star rating
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= currentRating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundColor(star <= currentRating ? .yellow : .white.opacity(0.6))
                            .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                            .accessibilityAddTraits(.isButton)
                            .onTapGesture {
                                Haptics.light()
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

            Spacer()

            if showQueueInPlayer {
                // Queue button (symmetry with heart)
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show Queue")
                .accessibilityIdentifier("queueButton")
            }
        }
    }

    // MARK: - iOS Playback Row

    var iOSPlaybackRow: some View {
        HStack {
            Button { engine.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.body)
                    .foregroundColor(engine.shuffleEnabled ? .white : .white.opacity(0.5))
            }
            .accessibilityLabel("Shuffle")
            .accessibilityValue(engine.shuffleEnabled ? "On" : "Off")
            .accessibilityIdentifier("shuffleButton")

            Spacer()

            Button {
                Haptics.light()
                engine.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Previous Track")
            .accessibilityIdentifier("previousButton")

            Spacer()

            Button {
                Haptics.medium()
                engine.togglePlayPause()
            } label: {
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 3)
                        .frame(width: 56, height: 56)
                    // Progress ring
                    Circle()
                        .trim(from: 0, to: engine.duration > 0 ? engine.currentTime / engine.duration : 0)
                        .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                    // Play/pause icon
                    Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                }
            }
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("playPauseButton")

            Spacer()

            Button {
                Haptics.light()
                engine.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Next Track")
            .accessibilityIdentifier("nextButton")

            Spacer()

            Button { engine.cycleRepeatMode() } label: {
                Image(systemName: engine.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.body)
                    .foregroundColor(engine.repeatMode != .off ? .white : .white.opacity(0.5))
            }
            .accessibilityLabel("Repeat")
            .accessibilityValue(repeatAccessibilityValue)
            .accessibilityIdentifier("repeatButton")
        }
        .foregroundColor(.white)
        .buttonStyle(.plain)
    }

    // MARK: - Volume Slider (no thumb)

    var volumeSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: 4)

                    Capsule()
                        .fill(.white)
                        .frame(width: geo.size.width * CGFloat(engine.userVolume), height: 4)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = Float(value.location.x / geo.size.width)
                            engine.userVolume = max(0, min(1, fraction))
                        }
                )
            }
            .frame(height: 20)
            .accessibilityLabel("Volume")
            .accessibilityValue(String(format: "%.0f%%", engine.userVolume * 100))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    engine.userVolume = min(1, engine.userVolume + 0.1)
                case .decrement:
                    engine.userVolume = max(0, engine.userVolume - 0.1)
                @unknown default: break
                }
            }

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
        }
    }

    // MARK: - Bottom Toolbar (6 icons)

    @ViewBuilder
    var bottomToolbar: some View {
        let orderedItems = NowPlayingToolbarItem.decodeOrder(from: toolbarOrderJSON)
        let visibleItems = orderedItems.filter { item in
            switch item {
            case .visualizer: return showVisualizerInToolbar && !disableVisualizer
            case .eq: return showEQInToolbar
            case .airplay: return showAirPlayInToolbar
            case .lyrics: return showLyricsInToolbar
            case .settings: return showSettingsInToolbar
            case .radioMix: return showRadioMixInToolbar
            }
        }
        // Hide the entire row when the user has disabled every item --
        // previously the empty pill still rendered.
        if !visibleItems.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                    toolbarButton(for: item)
                    if index < visibleItems.count - 1 {
                        Spacer()
                    }
                }
            }
            .font(.title3)
            .fontWeight(.semibold)
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .modifier(ToolbarBackgroundModifier(enabled: nowPlayingToolbarBackground))
        }
    }

    /// Toggles the pill background + glass effect on the bottom toolbar.
    private struct ToolbarBackgroundModifier: ViewModifier {
        let enabled: Bool
        func body(content: Content) -> some View {
            if enabled {
                content
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .modifier(GlassEffectToolbarModifier())
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private func toolbarButton(for item: NowPlayingToolbarItem) -> some View {
        switch item {
        case .visualizer:
            Button { appState.showVisualizer = true } label: {
                Image(systemName: "waveform.path")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Visualizer")
            .accessibilityIdentifier("visualizerButton")

        case .eq:
            Button { showEQ = true } label: {
                Image(systemName: "slider.vertical.3")
                    .foregroundColor(
                        engine.eqEnabled
                            ? .accentColor
                            : EQEngine.shared.currentPresetId != "flat"
                                ? .accentColor : nil
                    )
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Equalizer")
            .accessibilityValue(engine.eqEnabled ? "Active" : "Inactive")
            .accessibilityIdentifier("eqButton")

        case .airplay:
            AirPlayButton(tintColor: .white)
                .frame(width: 24, height: 24)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("airPlayButton")

        case .lyrics:
            Button { appState.showLyrics = true } label: {
                Image(systemName: "quote.bubble")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Lyrics")
            .accessibilityIdentifier("lyricsButton")

        case .settings:
            Button { showQuickSettings = true } label: {
                Image(systemName: "gearshape")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Quick Settings")
            .accessibilityIdentifier("quickSettingsButton")

        case .radioMix:
            Button {
                guard let song = engine.currentSong else { return }
                Haptics.light()
                AudioEngine.shared.startSongSimilarityMix(song)
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(engine.currentSong == nil)
            .accessibilityLabel("Start Radio Mix")
            .accessibilityIdentifier("radioMixButton")
        }
    }

    // MARK: - Quick Settings Sheet

    var quickSettingsSheet: some View {
        NavigationStack {
            List {
                // Sleep Timer
                Section {
                    sleepTimerSection
                }

                // Playback Speed
                Section {
                    playbackSpeedSection
                }

                // Crossfade
                Section {
                    Picker("Crossfade", selection: $crossfadeDuration) {
                        Text("Off").tag(0)
                        Text("2s").tag(2)
                        Text("5s").tag(5)
                        Text("8s").tag(8)
                        Text("12s").tag(12)
                    }
                    .accessibilityIdentifier("crossfadePicker")
                    .onChange(of: crossfadeDuration) { _, newValue in
                        guard newValue > 0, engine.isPlaying else { return }
                        Haptics.light()
                        let originalVolume = engine.userVolume
                        engine.userVolume = originalVolume * 0.3
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            engine.userVolume = originalVolume
                        }
                    }
                }

                // Actions
                Section {
                    if let song = engine.currentSong {
                        Button {
                            DownloadManager.shared.download(song: song, client: appState.subsonicClient)
                            Haptics.success()
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        .accessibilityIdentifier("quickSettingsDownload")

                        ShareLink(
                            item: "\(song.title) — \(song.artist ?? "")",
                            preview: SharePreview(song.title)
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("quickSettingsShare")
                    }
                }
            }
            .navigationTitle("Quick Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showQuickSettings = false }
                        .accessibilityIdentifier("quickSettingsDone")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Quick Settings Sections

    @ViewBuilder
    private var sleepTimerSection: some View {
        if SleepTimer.shared.isActive {
            HStack {
                Label("Sleep Timer", systemImage: "moon.fill")
                Spacer()
                Text(formatSleepTime(SleepTimer.shared.remainingSeconds))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button(role: .destructive) {
                SleepTimer.shared.stop()
            } label: {
                Label("Cancel Timer", systemImage: "xmark")
            }
        } else {
            Menu {
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
            } label: {
                Label("Sleep Timer", systemImage: "moon")
            }
        }
    }

    @ViewBuilder
    private var playbackSpeedSection: some View {
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
            HStack {
                Label("Playback Speed", systemImage: "gauge.with.dots.needle.33percent")
                Spacer()
                Text(engine.playbackRate == 1.0 ? "1x" : "\(engine.playbackRate, specifier: "%.2g")x")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("playbackSpeedMenu")
    }

    // MARK: - Playing Source Context

    /// Only shows context when it's non-obvious (playlist, radio, shuffle — NOT album)
    private var playingSourceLabel: String? {
        if engine.isRadioMode {
            return nil // Radio badge handles this separately
        }
        if let context = engine.playingFromContext {
            return context
        }
        if engine.shuffleEnabled && engine.queue.count > 1 {
            return "Shuffle"
        }
        return nil
    }
}
#endif
