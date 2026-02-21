import SwiftUI

// V1: Enum-based navigation to avoid multiple navigationDestination(item:) for String
enum TrackNavDestination: Hashable {
    case album(String)
    case artist(String)
}

struct TrackContextMenuModifier: ViewModifier {
    let song: Song
    var queue: [Song]?
    var index: Int?

    @Environment(AppState.self) private var appState
    @State private var showAddToPlaylist = false
    @State private var navDestination: TrackNavDestination?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                // Play
                Button {
                    AudioEngine.shared.play(song: song, from: queue, at: index ?? 0)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }

                // Play Next
                Button {
                    AudioEngine.shared.addToQueueNext(song)
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }

                // Add to Queue
                Button {
                    AudioEngine.shared.addToQueue(song)
                } label: {
                    Label("Add to Queue", systemImage: "text.append")
                }

                // Download
                Button {
                    DownloadManager.shared.download(
                        song: song,
                        client: appState.subsonicClient
                    )
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }

                Divider()

                // Add to Playlist
                Button {
                    showAddToPlaylist = true
                } label: {
                    Label("Add to Playlist...", systemImage: "music.note.list")
                }

                // Star / Unstar
                Button {
                    Task {
                        if song.starred != nil {
                            try? await appState.subsonicClient.unstar(id: song.id)
                        } else {
                            try? await appState.subsonicClient.star(id: song.id)
                        }
                    }
                } label: {
                    if song.starred != nil {
                        Label("Unfavorite", systemImage: "heart.slash")
                    } else {
                        Label("Favorite", systemImage: "heart")
                    }
                }

                Divider()

                // Go to Album
                if let albumId = song.albumId {
                    Button {
                        navDestination = .album(albumId)
                    } label: {
                        Label("Go to Album", systemImage: "square.stack")
                    }
                }

                // Go to Artist
                if let artistId = song.artistId {
                    Button {
                        navDestination = .artist(artistId)
                    } label: {
                        Label("Go to Artist", systemImage: "music.mic")
                    }
                }
            }
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistView(songIds: [song.id])
                    .environment(appState)
            }
            .navigationDestination(item: $navDestination) { destination in
                switch destination {
                case .album(let albumId):
                    AlbumDetailView(albumId: albumId)
                case .artist(let artistId):
                    ArtistDetailView(artistId: artistId)
                }
            }
    }
}

extension View {
    func trackContextMenu(song: Song, queue: [Song]? = nil, index: Int? = nil) -> some View {
        modifier(TrackContextMenuModifier(song: song, queue: queue, index: index))
    }
}
