import SwiftUI
import NukeUI

struct MiniPlayerView: View {
    @Environment(AppState.self) private var appState
    @State private var showNowPlaying = false
    @AppStorage("reduceMotion") private var reduceMotion = false

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        VStack(spacing: 0) {
            // Animated progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.1))

                    Rectangle()
                        .fill(.white.opacity(0.8))
                        .frame(width: engine.duration > 0
                               ? geo.size.width * (engine.currentTime / engine.duration)
                               : 0)
                        .animation(reduceMotion ? nil : .linear(duration: 0.5), value: engine.currentTime)
                }
            }
            .frame(height: 2)

            HStack(spacing: 12) {
                // Tappable area: album art + song info opens Now Playing
                Button {
                    showNowPlaying = true
                } label: {
                    HStack(spacing: 12) {
                        // Album art — rounded
                        AlbumArtView(
                            coverArtId: engine.currentSong?.coverArt,
                            size: 44,
                            cornerRadius: 10
                        )
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .accessibilityIdentifier("MiniPlayer")
        #if os(iOS)
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environment(appState)
        }
        #else
        .sheet(isPresented: $showNowPlaying) {
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
            return song.artist ?? ""
        }
        if engine.currentRadioStation != nil {
            return "Internet Radio"
        }
        return ""
    }
}

// MARK: - macOS Player Bar

#if os(macOS)
struct MacMiniPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("reduceMotion") private var reduceMotion = false

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
    @AppStorage("reduceMotion") private var reduceMotion = false

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
