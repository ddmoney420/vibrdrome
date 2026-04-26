#if os(macOS)
import SwiftUI

extension NowPlayingView {

    // MARK: - Controls Toolbar (above progress bar)

    var controlsToolbar: some View {
        HStack(spacing: 0) {
            Button { engine.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .foregroundColor(engine.shuffleEnabled ? .white : .white.opacity(0.5))
            }
            .accessibilityLabel("Shuffle")
            .accessibilityValue(engine.shuffleEnabled ? "On" : "Off")
            .accessibilityIdentifier("shuffleButton")

            Spacer()

            sleepTimerMenu

            Spacer()

            playbackSpeedMenu

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

    private var sleepTimerMenu: some View {
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
    }

    private var playbackSpeedMenu: some View {
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
    }

    // MARK: - Actions Toolbar (below playback controls)

    var actionsToolbar: some View {
        HStack(spacing: 0) {
            if showHeartInPlayer {
                heartButton
                Spacer()
            }

            if showQueueInPlayer {
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Show Queue")
                .accessibilityIdentifier("queueButton")
                Spacer()
            }

            Button {
                openWindow(id: "visualizer")
            } label: {
                Image(systemName: "waveform")
            }
            .accessibilityLabel("Show Visualizer")
            .accessibilityIdentifier("visualizerButton")

            Spacer()

            if isInline {
                Button {
                    openWindow(id: "now-playing")
                } label: {
                    Image(systemName: "pip.enter")
                }
                .accessibilityLabel("Pop Out Now Playing")
                .accessibilityIdentifier("popOutNowPlayingButton")
                Spacer()
            }

            Button {
                if let window = nsWindow {
                    window.collectionBehavior.insert(.fullScreenPrimary)
                    window.toggleFullScreen(nil)
                } else {
                    NSApp.mainWindow?.toggleFullScreen(nil)
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .accessibilityLabel("Toggle Full Screen")
        }
        .font(.body)
        .buttonStyle(.plain)
        .foregroundColor(.white.opacity(0.5))
    }

    private var heartButton: some View {
        Button {
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
                .foregroundColor(isStarred ? .pink : .white.opacity(0.5))
        }
        .accessibilityLabel(isStarred ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityIdentifier("favoriteButton")
    }

    // MARK: - Volume Slider

    var macVolumeSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)

            Slider(value: Binding(
                get: { Double(engine.userVolume) },
                set: { engine.userVolume = Float($0) }
            ).animation(nil), in: 0...1)
            .tint(.white)
            .accessibilityLabel("Volume")
            .accessibilityValue(String(format: "%.0f%%", engine.userVolume * 100))

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
        }
    }
}
#endif
