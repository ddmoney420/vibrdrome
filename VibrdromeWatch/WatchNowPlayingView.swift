import SwiftUI

struct WatchNowPlayingView: View {
    @ObservedObject var session: WatchSessionManager
    @State private var crownVolume: Double = 0.5

    var body: some View {
        if session.title.isEmpty {
            emptyState
        } else {
            nowPlayingContent
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Vibrdrome")
                .font(.headline)

            Text("Play music on your iPhone to control it here")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var nowPlayingContent: some View {
        ScrollView {
            VStack(spacing: 6) {
                // Album art
                if let artData = session.coverArtData,
                   let uiImage = UIImage(data: artData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 90, height: 90)
                        .cornerRadius(10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)
                        .frame(width: 90, height: 90)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                        }
                }

                // Song info
                VStack(spacing: 2) {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(session.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !session.album.isEmpty {
                        Text(session.album)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                // Progress
                if session.duration > 0 {
                    VStack(spacing: 2) {
                        ProgressView(value: session.elapsed, total: session.duration)
                            .tint(.accentColor)

                        HStack {
                            Text(formatTime(session.elapsed))
                            Spacer()
                            Text("-\(formatTime(session.duration - session.elapsed))")
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                }

                // Playback controls
                HStack(spacing: 20) {
                    Button { session.previous() } label: {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button { session.togglePlayPause() } label: {
                        Image(systemName: session.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                    }
                    .buttonStyle(.plain)

                    Button { session.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)

                // Quick actions
                HStack(spacing: 16) {
                    Button { session.toggleStar() } label: {
                        Image(systemName: session.isStarred ? "heart.fill" : "heart")
                            .foregroundStyle(session.isStarred ? .pink : .secondary)
                    }
                    .buttonStyle(.plain)

                    Button { session.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(session.isShuffleOn ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)

                    Button { session.sendCommand("sleepTimer15") } label: {
                        Image(systemName: session.sleepTimerActive ? "moon.fill" : "moon")
                            .foregroundStyle(session.sleepTimerActive ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)

                    Button { session.cycleRepeat() } label: {
                        Image(systemName: session.repeatMode == "one" ? "repeat.1" : "repeat")
                            .foregroundStyle(session.repeatMode != "off" ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .font(.body)
                .padding(.top, 4)
            }
        }
        .focusable()
        .digitalCrownRotation(
            $crownVolume,
            from: 0.0,
            through: 1.0,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownVolume) { _, newValue in
            session.setVolume(Float(newValue))
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}
