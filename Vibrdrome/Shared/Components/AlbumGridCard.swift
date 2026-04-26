import SwiftUI

struct AlbumGridCard: View {
    let album: Album

    @Environment(AppState.self) private var appState
    @State private var isStarred: Bool
    @State private var currentRating: Int
    #if os(macOS)
    @State private var isHovered = false
    #endif

    init(album: Album) {
        self.album = album
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
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                AlbumArtView(coverArtId: album.coverArt, size: geo.size.width, cornerRadius: 10)
                #if os(macOS)
                if isHovered {
                    hoverOverlay
                }
                #endif
            }
        }
        .aspectRatio(1, contentMode: .fit)
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
                .shadow(color: .black.opacity(0.4), radius: 2)
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
                        try? await appState.subsonicClient.setRating(id: album.id, rating: newRating)
                    }
                } label: {
                    Image(systemName: star <= currentRating ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(star <= currentRating ? .yellow : .white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
    }
    #endif
}
