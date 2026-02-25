import SwiftUI
import os.log

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
            .contextMenu { contextMenuItems }
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

    @ViewBuilder
    private var contextMenuItems: some View {
        playbackActions
        Divider()
        libraryActions
        Divider()
        navigationActions
    }

    @ViewBuilder
    private var playbackActions: some View {
        Button {
            AudioEngine.shared.play(song: song, from: queue, at: index ?? 0)
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        Button {
            AudioEngine.shared.addToQueueNext(song)
        } label: {
            Label("Play Next", systemImage: "text.insert")
        }

        Button {
            AudioEngine.shared.addToQueue(song)
        } label: {
            Label("Add to Queue", systemImage: "text.append")
        }

        Button {
            AudioEngine.shared.startRadioFromSong(song)
        } label: {
            Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
        }

        Button {
            DownloadManager.shared.download(
                song: song,
                client: appState.subsonicClient
            )
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
    }

    @ViewBuilder
    private var libraryActions: some View {
        Button {
            showAddToPlaylist = true
        } label: {
            Label("Add to Playlist...", systemImage: "music.note.list")
        }

        Button {
            Task {
                do {
                    if song.starred != nil {
                        try await OfflineActionQueue.shared.unstar(id: song.id)
                    } else {
                        try await OfflineActionQueue.shared.star(id: song.id)
                        if UserDefaults.standard.bool(forKey: "autoDownloadFavorites") {
                            DownloadManager.shared.download(song: song, client: appState.subsonicClient)
                        }
                    }
                } catch {
                    Logger(subsystem: "com.vibrdrome.app", category: "Library")
                        .error("Failed to update star status: \(error)")
                }
            }
        } label: {
            if song.starred != nil {
                Label("Unfavorite", systemImage: "heart.slash")
            } else {
                Label("Favorite", systemImage: "heart")
            }
        }
    }

    @ViewBuilder
    private var navigationActions: some View {
        if let albumId = song.albumId {
            Button {
                navDestination = .album(albumId)
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }

        if let artistId = song.artistId {
            Button {
                navDestination = .artist(artistId)
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }
    }
}

extension View {
    func trackContextMenu(song: Song, queue: [Song]? = nil, index: Int? = nil) -> some View {
        modifier(TrackContextMenuModifier(song: song, queue: queue, index: index))
    }
}
