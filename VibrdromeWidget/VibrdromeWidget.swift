import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, state: nil, imageData: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        let state = NowPlayingState.load()
        let imageData = loadCachedImageData(state: state)
        completion(NowPlayingEntry(date: .now, state: state, imageData: imageData))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let state = NowPlayingState.load()
        let imageData = loadCachedImageData(state: state)
        let entry = NowPlayingEntry(date: .now, state: state, imageData: imageData)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadCachedImageData(state: NowPlayingState?) -> Data? {
        guard let coverArtId = state?.coverArtId,
              let groupDefaults = NowPlayingState.shared else { return nil }
        return groupDefaults.data(forKey: "widgetCoverArt_\(coverArtId)")
    }
}

// MARK: - Entry

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let state: NowPlayingState?
    let imageData: Data?
}

// MARK: - Interactive Intents

// Widget intents defined in Shared/WidgetIntents.swift

// MARK: - Widget Views

struct NowPlayingWidgetEntryView: View {
    var entry: NowPlayingEntry
    @Environment(\.widgetFamily) var family

    private var albumImage: UIImage? {
        guard let data = entry.imageData else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        if let state = entry.state {
            switch family {
            case .systemSmall:
                smallWidget(state)
            case .systemMedium:
                mediumWidget(state)
            case .systemLarge:
                largeWidget(state)
            case .accessoryCircular:
                circularWidget(state)
            case .accessoryRectangular:
                rectangularWidget(state)
            default:
                mediumWidget(state)
            }
        } else {
            placeholderView
        }
    }

    // MARK: - Small Widget

    private func smallWidget(_ state: NowPlayingState) -> some View {
        ZStack {
            // Blurred album art background
            if let albumImage {
                Image(uiImage: albumImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 20)
                    .scaleEffect(1.5)
                    .overlay(Color.black.opacity(0.4))
            }

            VStack(alignment: .leading, spacing: 6) {
                coverArt(size: 48)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                Spacer(minLength: 0)

                Text(state.title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(state.artist)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)

                // Play state indicator
                HStack(spacing: 4) {
                    Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 8))
                    Text(state.isPlaying ? "Playing" : "Paused")
                        .font(.system(size: 9))
                }
                .foregroundColor(.white.opacity(0.6))
            }
            .padding(14)
        }
        .containerBackground(for: .widget) {
            if albumImage != nil {
                Color.clear
            } else {
                Color(.systemGray6)
            }
        }
    }

    // MARK: - Medium Widget

    private func mediumWidget(_ state: NowPlayingState) -> some View {
        ZStack {
            if let albumImage {
                Image(uiImage: albumImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 25)
                    .scaleEffect(1.5)
                    .overlay(Color.black.opacity(0.45))
            }

            HStack(spacing: 14) {
                coverArt(size: 80)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 5) {
                    Text(state.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(albumImage != nil ? .white : .primary)
                        .lineLimit(2)

                    Text(state.artist)
                        .font(.caption)
                        .foregroundColor(albumImage != nil ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)

                    if !state.album.isEmpty {
                        Text(state.album)
                            .font(.caption2)
                            .foregroundColor(albumImage != nil ? .white.opacity(0.5) : .secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    // Interactive controls
                    HStack(spacing: 16) {
                        Button(intent: WidgetTogglePlaybackIntent()) {
                            Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(albumImage != nil ? .white : .accentColor)
                        }
                        .buttonStyle(.plain)

                        Button(intent: WidgetSkipTrackIntent()) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16))
                                .foregroundColor(albumImage != nil ? .white.opacity(0.8) : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .containerBackground(for: .widget) {
            if albumImage != nil {
                Color.clear
            } else {
                Color(.systemGray6)
            }
        }
    }

    // MARK: - Large Widget

    private func largeWidget(_ state: NowPlayingState) -> some View {
        ZStack {
            if let albumImage {
                Image(uiImage: albumImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 30)
                    .scaleEffect(1.5)
                    .overlay(Color.black.opacity(0.5))
            }

            VStack(spacing: 16) {
                coverArt(size: 160)
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 5)

                VStack(spacing: 4) {
                    Text(state.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(albumImage != nil ? .white : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(state.artist)
                        .font(.subheadline)
                        .foregroundColor(albumImage != nil ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)

                    if !state.album.isEmpty {
                        Text(state.album)
                            .font(.caption)
                            .foregroundColor(albumImage != nil ? .white.opacity(0.5) : .secondary)
                            .lineLimit(1)
                    }
                }

                // Controls
                HStack(spacing: 32) {
                    Button(intent: WidgetTogglePlaybackIntent()) {
                        Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(albumImage != nil ? .white : .accentColor)
                    }
                    .buttonStyle(.plain)

                    Button(intent: WidgetSkipTrackIntent()) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 22))
                            .foregroundColor(albumImage != nil ? .white.opacity(0.8) : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .containerBackground(for: .widget) {
            if albumImage != nil {
                Color.clear
            } else {
                Color(.systemGray6)
            }
        }
    }

    // MARK: - Lock Screen Widgets

    private func circularWidget(_ state: NowPlayingState) -> some View {
        ZStack {
            if let albumImage {
                Image(uiImage: albumImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(Color.black.opacity(0.3))
            } else {
                Color(.systemGray5)
            }
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private func rectangularWidget(_ state: NowPlayingState) -> some View {
        HStack(spacing: 8) {
            if let albumImage {
                Image(uiImage: albumImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(state.artist)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Shared Components

    private func coverArt(size: CGFloat) -> some View {
        Group {
            if let albumImage {
                Image(uiImage: albumImage)
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
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}
