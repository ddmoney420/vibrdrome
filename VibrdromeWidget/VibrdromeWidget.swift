import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, state: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        let state = NowPlayingState.load()
        completion(NowPlayingEntry(date: .now, state: state))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let state = NowPlayingState.load()
        let entry = NowPlayingEntry(date: .now, state: state)
        // Refresh every 5 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Entry

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let state: NowPlayingState?
}

// MARK: - Widget Views

struct NowPlayingWidgetEntryView: View {
    var entry: NowPlayingEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let state = entry.state {
            switch family {
            case .systemSmall:
                smallWidget(state)
            case .systemMedium:
                mediumWidget(state)
            default:
                mediumWidget(state)
            }
        } else {
            placeholderView
        }
    }

    private func smallWidget(_ state: NowPlayingState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                coverArt(state, size: 44)
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            Text(state.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)

            Text(state.artist)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func mediumWidget(_ state: NowPlayingState) -> some View {
        HStack(spacing: 14) {
            coverArt(state, size: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text(state.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if !state.album.isEmpty {
                    Text(state.album)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                        .font(.caption2)
                        .foregroundColor(state.isPlaying ? .accentColor : .secondary)
                    Text(state.isPlaying ? "Now Playing" : "Paused")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func coverArt(_ state: NowPlayingState, size: CGFloat) -> some View {
        Group {
            if let coverArtId = state.coverArtId,
               let serverURL = state.serverURL,
               let imageData = loadCachedImage(coverArtId: coverArtId, serverURL: serverURL),
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
    }

    private var placeholderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Vibrdrome")
                .font(.caption)
                .fontWeight(.medium)
            Text("Nothing playing")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func loadCachedImage(coverArtId: String, serverURL: String) -> Data? {
        guard let groupDefaults = NowPlayingState.shared else { return nil }
        return groupDefaults.data(forKey: "widgetCoverArt_\(coverArtId)")
    }
}

// MARK: - Widget Configuration

@main
struct VibrdromeWidget: Widget {
    let kind: String = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Shows what's currently playing in Vibrdrome.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
