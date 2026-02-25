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
                            try await OfflineActionQueue.shared.star(id: id)
                            autoDownloadIfEnabled()
                        } else {
                            try await OfflineActionQueue.shared.unstar(id: id)
                        }
                    case .album:
                        if starred {
                            try await OfflineActionQueue.shared.star(albumId: id)
                        } else {
                            try await OfflineActionQueue.shared.unstar(albumId: id)
                        }
                    case .artist:
                        if starred {
                            try await OfflineActionQueue.shared.star(artistId: id)
                        } else {
                            try await OfflineActionQueue.shared.unstar(artistId: id)
                        }
                    }
                } catch {
                    // Revert on failure
                    starred.toggle()
                }
            }
        } label: {
            let pending = OfflineActionQueue.shared.hasPendingStar(targetId: id)
            Image(systemName: starred ? "heart.fill" : pending ? "heart.circle" : "heart")
                .foregroundStyle(starred ? .pink : pending ? .orange : .secondary)
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
