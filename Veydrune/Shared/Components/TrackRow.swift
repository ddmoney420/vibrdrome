import SwiftUI

struct TrackRow: View {
    let song: Song
    var showTrackNumber: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if showTrackNumber, let track = song.track {
                Text("\(track)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let artist = song.artist {
                        Text(artist)
                    }
                    if let duration = song.duration {
                        Text("·")
                        Text(formatDuration(duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if song.starred != nil {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
            }
        }
        .contentShape(Rectangle())
    }
}
