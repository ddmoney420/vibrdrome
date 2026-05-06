import SwiftUI
import NukeUI
import Nuke

struct AlbumArtView: View {
    let coverArtId: String?
    /// Display size in points. Pass nil to fill the parent frame (no fixed frame applied).
    var size: CGFloat? = 50
    var cornerRadius: CGFloat = 6
    /// Context-appropriate canonical pixel size for the Subsonic request. Pass nil to serve original resolution.
    var requestSize: Int? = CoverArtSize.gridThumb

    @Environment(AppState.self) private var appState

    var body: some View {
        if let coverArtId {
            LazyImage(url: appState.subsonicClient.coverArtURL(id: coverArtId, size: requestSize)) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .transition(isMemoryCached(state) ? .identity : .opacity.animation(.easeIn(duration: 0.15)))
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

    private func isMemoryCached(_ state: any LazyImageState) -> Bool {
        if case .success(let response) = state.result {
            return response.cacheType == .memory
        }
        return false
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .frame(width: size, height: size)
    }
}
