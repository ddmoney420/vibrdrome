import SwiftUI
import NukeUI

struct AlbumArtView: View {
    let coverArtId: String?
    var size: CGFloat = 50
    var cornerRadius: CGFloat = 6

    @Environment(AppState.self) private var appState

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
        } else {
            placeholderView
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
