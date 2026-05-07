import SwiftUI

struct AlbumGridCard: View {
    let album: Album
    let cellWidth: CGFloat

    @State private var isStarred: Bool
    @State private var currentRating: Int
    #if os(macOS)
    @State private var isHovered = false
    #endif

    init(album: Album, cellWidth: CGFloat) {
        self.album = album
        self.cellWidth = cellWidth
        self._isStarred = State(initialValue: album.starred != nil)
        self._currentRating = State(initialValue: album.userRating ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            artworkWithOverlay
            Text(album.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
            if let artist = album.artist {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var artworkWithOverlay: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    AlbumArtView(
                        coverArtId: album.coverArt,
                        size: cellWidth,
                        cornerRadius: 10,
                        requestSize: CoverArtSize.gridThumb
                    )
                    #if os(macOS)
                    if isHovered {
                        hoverOverlay
                    }
                    #endif
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            #if os(macOS)
            .onHover { isHovered = $0 }
            #endif
    }

    #if os(macOS)
    private var hoverOverlay: some View {
        HStack(spacing: 8) {
            favoriteButton
            Spacer()
            ratingButtons
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .clipShape(
            .rect(
                topLeadingRadius: 0,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 10,
                topTrailingRadius: 0
            )
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var favoriteButton: some View {
        Button {
            isStarred.toggle()
            let newValue = isStarred
            Task {
                do {
                    if newValue {
                        try await OfflineActionQueue.shared.star(albumId: album.id)
                    } else {
                        try await OfflineActionQueue.shared.unstar(albumId: album.id)
                    }
                } catch {
                    isStarred.toggle()
                }
            }
        } label: {
            Image(systemName: isStarred ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isStarred ? .pink : .white)
                .shadow(color: .black.opacity(0.9), radius: 6, y: 2)
                .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isStarred ? "Remove from Favorites" : "Add to Favorites")
    }

    private var ratingButtons: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    let newRating = (star == currentRating) ? 0 : star
                    currentRating = newRating
                    Task {
                        do {
                            try await OfflineActionQueue.shared.setRating(id: album.id, rating: newRating)
                        } catch {
                            currentRating = album.userRating ?? 0
                        }
                    }
                } label: {
                    Image(systemName: star <= currentRating ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(star <= currentRating ? .yellow : .white)
                        .shadow(color: .black.opacity(0.9), radius: 6, y: 2)
                        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
    }
    #endif
}
