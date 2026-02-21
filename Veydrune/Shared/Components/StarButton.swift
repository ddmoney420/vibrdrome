import SwiftUI

struct StarButton: View {
    let id: String
    var isStarred: Bool
    var type: StarType = .song
    var song: Song?
    var onToggle: ((Bool) -> Void)?

    @Environment(AppState.self) private var appState
    @State private var starred: Bool

    enum StarType {
        case song, album, artist
    }

    init(id: String, isStarred: Bool, type: StarType = .song, song: Song? = nil, onToggle: ((Bool) -> Void)? = nil) {
        self.id = id
        self.isStarred = isStarred
        self.type = type
        self.song = song
        self.onToggle = onToggle
        self._starred = State(initialValue: isStarred)
    }

    var body: some View {
        Button {
            starred.toggle()
            onToggle?(starred)
            Task {
                do {
                    switch type {
                    case .song:
                        if starred {
                            try await appState.subsonicClient.star(id: id)
                            autoDownloadIfEnabled()
                        } else {
                            try await appState.subsonicClient.unstar(id: id)
                        }
                    case .album:
                        if starred {
                            try await appState.subsonicClient.star(albumId: id)
                        } else {
                            try await appState.subsonicClient.unstar(albumId: id)
                        }
                    case .artist:
                        if starred {
                            try await appState.subsonicClient.star(artistId: id)
                        } else {
                            try await appState.subsonicClient.unstar(artistId: id)
                        }
                    }
                } catch {
                    // Revert on failure
                    starred.toggle()
                }
            }
        } label: {
            Image(systemName: starred ? "heart.fill" : "heart")
                .foregroundStyle(starred ? .pink : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(starred ? "Remove from Favorites" : "Add to Favorites")
    }

    private func autoDownloadIfEnabled() {
        guard type == .song,
              let song,
              UserDefaults.standard.bool(forKey: "autoDownloadFavorites") else { return }
        DownloadManager.shared.download(song: song, client: appState.subsonicClient)
    }
}
