import SwiftUI
import NukeUI

struct AlbumArtView: View, Equatable {
    let coverArtId: String?
    var size: CGFloat = 50
    var cornerRadius: CGFloat = 6

    @Environment(AppState.self) private var appState

    nonisolated static func == (lhs: AlbumArtView, rhs: AlbumArtView) -> Bool {
        lhs.coverArtId == rhs.coverArtId && lhs.size == rhs.size && lhs.cornerRadius == rhs.cornerRadius
    }

    var body: some View {
        if let coverArtId {
            LazyImage(url: appState.subsonicClient.coverArtURL(id: coverArtId, size: Int(size * 2))) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .transition(.opacity.animation(.easeIn(duration: 0.2)))
                } else if state.error != nil {
                    placeholderView
                } else {
                    placeholderView
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
        } else {
            placeholderView
                .accessibilityHidden(true)
        }
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }
}
