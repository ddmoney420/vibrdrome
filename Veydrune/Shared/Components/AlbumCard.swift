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
                        Text("\(year)")
                    }
                    if let count = album.songCount {
                        Text("· \(count) songs")
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
    }
}
