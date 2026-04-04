import ActivityKit
import WidgetKit
import SwiftUI

struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            // Lock screen banner
            HStack(spacing: 12) {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(context.state.artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
            .padding(16)
            .activityBackgroundTint(.black.opacity(0.7))

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .font(.title2)
                        .foregroundColor(.purple)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.caption)
                    .foregroundColor(.purple)
            } compactTrailing: {
                Text(context.state.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 80)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundColor(.purple)
            }
        }
    }
}
