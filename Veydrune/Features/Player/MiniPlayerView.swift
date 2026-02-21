import SwiftUI

struct MiniPlayerView: View {
    @Environment(AppState.self) private var appState
    @State private var showNowPlaying = false

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: engine.duration > 0
                           ? geo.size.width * (engine.currentTime / engine.duration)
                           : 0)
            }
            .frame(height: 2)

            HStack(spacing: 12) {
                // Cover art thumbnail
                AlbumArtView(
                    coverArtId: engine.currentSong?.coverArt,
                    size: 44,
                    cornerRadius: 6
                )

                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.subheadline)
                        .bold()
                        .lineLimit(1)
                    Text(displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Controls
                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Button { engine.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .disabled(engine.queue.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .onTapGesture {
            showNowPlaying = true
        }
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
