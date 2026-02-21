import SwiftUI
import NukeUI
#if os(iOS)
import AVKit
#endif

struct NowPlayingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var isStarred = false
    @State private var sliderValue: Double = 0
    @State private var isDragging = false

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 20) {
                        Spacer(minLength: 8)

                        // Album art
                        albumArt(width: min(geo.size.width - 80, 340))

                        // Song info
                        songInfo

                        // Progress slider
                        progressSlider

                        // Playback controls
                        playbackControls

                        // Bottom toolbar
                        bottomToolbar

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 24)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3)
                    }
                }
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
            .onAppear {
                isStarred = engine.currentSong?.starred != nil
            }
            .onChange(of: engine.currentSong?.id) {
                isStarred = engine.currentSong?.starred != nil
                // V2: Reset slider state on song change
                isDragging = false
                sliderValue = 0
            }
        }
    }

    // MARK: - Album Art

    @ViewBuilder
    private func albumArt(width: CGFloat) -> some View {
        if let coverArtId = engine.currentSong?.coverArt {
            LazyImage(url: appState.subsonicClient.coverArtURL(id: coverArtId, size: 800)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else if state.error != nil {
                    artPlaceholder(width: width)
                } else {
                    artPlaceholder(width: width)
                        .overlay { ProgressView() }
                }
            }
            .frame(width: width, height: width)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        } else {
            artPlaceholder(width: width)
        }
    }

    private func artPlaceholder(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary)
            .frame(width: width, height: width)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }
    }

    // MARK: - Song Info

    private var songInfo: some View {
        VStack(spacing: 4) {
            Text(engine.currentSong?.title ?? "Not Playing")
                .font(.title3)
                .bold()
                .lineLimit(1)

            Text(engine.currentSong?.artist ?? "")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(engine.currentSong?.album ?? "")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Progress

    private var progressSlider: some View {
        // V5: Use song metadata duration as initial range to avoid 0...1 flicker
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
            .tint(.primary)

            HStack {
                Text(formatDuration(displayTime))
                Spacer()
                let remaining = songDuration - displayTime
                Text("-\(formatDuration(max(0, remaining)))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    // MARK: - Controls

    private var playbackControls: some View {
        HStack(spacing: 36) {
            Button { engine.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.body)
                    .foregroundColor(engine.shuffleEnabled ? .accentColor : .secondary)
            }

            Button { engine.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }

            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
            }

            Button { engine.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }

            Button { engine.cycleRepeatMode() } label: {
                Image(systemName: engine.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.body)
                    .foregroundColor(engine.repeatMode != .off ? .accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 36) {
            // Lyrics
            Button { showLyrics = true } label: {
                Image(systemName: "text.quote")
            }
            .disabled(engine.currentSong == nil)

            // Star
            Button {
                guard let song = engine.currentSong else { return }
                let songId = song.id
                let wasStarred = isStarred
                // Optimistic toggle
                isStarred = !wasStarred
                Task {
                    do {
                        if wasStarred {
                            try await appState.subsonicClient.unstar(id: songId)
                        } else {
                            try await appState.subsonicClient.star(id: songId)
                        }
                        // V3: Only update if still on same song
                        guard engine.currentSong?.id == songId else { return }
                    } catch {
                        // Revert on failure if still on same song
                        if engine.currentSong?.id == songId {
                            isStarred = wasStarred
                        }
                    }
                }
            } label: {
                Image(systemName: isStarred ? "heart.fill" : "heart")
                    .foregroundStyle(isStarred ? .pink : .secondary)
            }

            // AirPlay
            #if os(iOS)
            AirPlayButton()
                .frame(width: 24, height: 24)
            #endif

            // Queue
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
