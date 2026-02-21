import SwiftUI
import NukeUI

struct MiniPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
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

                // Play/Pause — larger hit target
                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Next
                Button { engine.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(engine.queue.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            showNowPlaying = true
        }
        #if os(iOS)
        .modifier(NowPlayingPresentation(isPresented: $showNowPlaying, isRegular: sizeClass == .regular, appState: appState))
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

#if os(iOS)
/// Uses sheet on iPad, fullScreenCover on iPhone.
private struct NowPlayingPresentation: ViewModifier {
    @Binding var isPresented: Bool
    let isRegular: Bool
    let appState: AppState

    func body(content: Content) -> some View {
        if isRegular {
            content
                .sheet(isPresented: $isPresented) {
                    NowPlayingView()
                        .environment(appState)
                        .presentationDetents([.large])
                }
        } else {
            content
                .fullScreenCover(isPresented: $isPresented) {
                    NowPlayingView()
                        .environment(appState)
                }
        }
    }
}
#endif
