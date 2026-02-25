import SwiftUI

struct ArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtView(coverArtId: artist.coverArt, size: 44, cornerRadius: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.body)
                    .lineLimit(1)
                if let count = artist.albumCount {
                    Text(verbatim: "\(count) album\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
