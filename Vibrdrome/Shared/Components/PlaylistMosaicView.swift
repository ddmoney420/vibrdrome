import SwiftUI

/// Shows a 2x2 grid of album covers from the first 4 songs in a playlist.
/// Falls back to single AlbumArtView if playlist has coverArt.
struct PlaylistMosaicView: View {
    let playlist: Playlist
    let size: CGFloat
    let cornerRadius: CGFloat

    @Environment(AppState.self) private var appState
    @State private var coverArtIds: [String] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if let coverArt = playlist.coverArt {
                // Server-provided artwork (Navidrome 0.61+)
                AlbumArtView(coverArtId: coverArt, size: size, cornerRadius: cornerRadius)
            } else if coverArtIds.count >= 4 {
                // 2x2 mosaic
                let halfSize = size / 2
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        AlbumArtView(coverArtId: coverArtIds[0], size: halfSize, cornerRadius: 0)
                        AlbumArtView(coverArtId: coverArtIds[1], size: halfSize, cornerRadius: 0)
                    }
                    HStack(spacing: 0) {
                        AlbumArtView(coverArtId: coverArtIds[2], size: halfSize, cornerRadius: 0)
                        AlbumArtView(coverArtId: coverArtIds[3], size: halfSize, cornerRadius: 0)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else if coverArtIds.count >= 1 {
                // Single cover fallback
                AlbumArtView(coverArtId: coverArtIds.first, size: size, cornerRadius: cornerRadius)
            } else {
                // Placeholder
                AlbumArtView(coverArtId: nil, size: size, cornerRadius: cornerRadius)
            }
        }
        .task {
            guard !loaded, playlist.coverArt == nil else { return }
            loaded = true
            await loadCovers()
        }
    }

    private func loadCovers() async {
        do {
            let detail = try await appState.subsonicClient.getPlaylist(id: playlist.id)
            let songs = detail.entry ?? []
            var ids: [String] = []
            var seen = Set<String>()
            for song in songs {
                if let art = song.coverArt, !seen.contains(art) {
                    ids.append(art)
                    seen.insert(art)
                    if ids.count >= 4 { break }
                }
            }
            coverArtIds = ids
        } catch {}
    }
}
