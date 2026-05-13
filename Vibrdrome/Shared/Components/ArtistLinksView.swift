import SwiftUI

/// Renders each artist in `song.artists` as an individually tappable link.
/// Falls back to a single link using `song.artistId` / `song.displayArtist`
/// when the OpenSubsonic `artists` array is absent (older servers).
struct ArtistLinksView: View {
    let song: Song
    var font: Font = .body
    var color: Color = .primary
    var onNavigate: ((String) -> Void)?

    var body: some View {
        if let artists = song.artists, artists.count > 1 {
            multiArtistView(artists)
        } else if let artistId = song.artistId, let name = song.displayArtist {
            artistButton(name: name, id: artistId)
        } else if let name = song.displayArtist {
            Text(name).font(font).foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func multiArtistView(_ artists: [SongArtist]) -> some View {
        // Flow each name as a separate button with ", " separators.
        // Using a wrapping HStack-of-Text approach via AttributedString isn't
        // possible for tappable items, so we compose them linearly in an HStack
        // and let it truncate as a unit — consistent with the rest of the UI.
        HStack(spacing: 0) {
            ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                artistButton(name: artist.name, id: artist.id)
                if index < artists.count - 1 {
                    Text(", ").font(font).foregroundStyle(color)
                }
            }
        }
    }

    @ViewBuilder
    private func artistButton(name: String, id: String) -> some View {
        if let navigate = onNavigate {
            Button {
                navigate(id)
            } label: {
                Text(name).font(font).foregroundStyle(color)
            }
            .buttonStyle(.plain)
        } else {
            Text(name).font(font).foregroundStyle(color)
        }
    }
}
