import SwiftUI

struct AlbumCard: View {
    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtView(coverArtId: album.coverArt, size: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.body)
                    .lineLimit(1)
                if let artist = album.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if let year = album.year {
                        Text(verbatim: "\(year)")
                    }
                    if let count = album.songCount {
                        Text(verbatim: "· \(count) songs")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            if album.starred != nil {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(albumAccessibilityLabel)
    }

    private var albumAccessibilityLabel: String {
        var parts = [album.name]
        if let artist = album.artist {
            parts.append("by \(artist)")
        }
        if let year = album.year {
            parts.append(String(year))
        }
        if let count = album.songCount {
            parts.append("\(count) song\(count == 1 ? "" : "s")")
        }
        if album.starred != nil {
            parts.append("Favorited")
        }
        return parts.joined(separator: ", ")
    }
}
