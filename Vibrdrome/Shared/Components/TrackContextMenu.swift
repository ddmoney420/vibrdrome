import SwiftUI
import os.log

struct TrackContextMenuModifier: ViewModifier, Equatable {
    let song: Song
    var queue: [Song]?
    var index: Int?
    var onRemove: (() -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var showAddToPlaylist = false
    @State private var showGetInfo = false

    nonisolated static func == (lhs: TrackContextMenuModifier, rhs: TrackContextMenuModifier) -> Bool {
        lhs.song == rhs.song && lhs.index == rhs.index
    }

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .background(Color(.systemBackground))
            #endif
            .contextMenu {
                TrackContextMenuContent(
                    song: song, queue: queue, index: index,
                    onRemove: onRemove,
                    showAddToPlaylist: $showAddToPlaylist,
                    showGetInfo: $showGetInfo
                )
            }
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistView(songIds: [song.id])
            }
            #if os(iOS)
            .sheet(isPresented: $showGetInfo) {
                NavigationStack {
                    GetInfoView(target: GetInfoTarget(type: .song, id: song.id))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showGetInfo = false }
                            }
                        }
                }
                .environment(appState)
            }
            #endif
    }
}

/// Lazy inner view — `@Environment(AppState.self)` is only resolved when the context menu opens.
private struct TrackContextMenuContent: View {
    let song: Song
    var queue: [Song]?
    var index: Int?
    var onRemove: (() -> Void)?
    @Binding var showAddToPlaylist: Bool
    @Binding var showGetInfo: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        playbackActions
        Divider()
        libraryActions
        Divider()
        jukeboxActions
        Divider()
        navigationActions
        if let onRemove {
            Divider()
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove from Queue", systemImage: "minus.circle")
            }
        }
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
                        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoDownloadFavorites) {
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
    private var jukeboxActions: some View {
        Button {
            Task {
                do {
                    try await appState.subsonicClient.jukeboxAdd(ids: [song.id])
                    try await appState.subsonicClient.jukeboxStart()
                } catch {
                    Logger(subsystem: "com.vibrdrome.app", category: "Jukebox")
                        .error("Failed to play on jukebox: \(error)")
                }
            }
        } label: {
            Label("Play on Jukebox", systemImage: "hifispeaker")
        }
    }

    @ViewBuilder
    private var navigationActions: some View {
        Button {
            appState.pendingNavigation = .song(id: song.id)
        } label: {
            Label("Song Info", systemImage: "info.circle")
        }

        Button {
            #if os(macOS)
            openWindow(id: "get-info", value: GetInfoTarget(type: .song, id: song.id))
            #else
            showGetInfo = true
            #endif
        } label: {
            Label("Get Info", systemImage: "doc.text.magnifyingglass")
        }

        if let albumId = song.albumId {
            Button {
                appState.pendingNavigation = .album(id: albumId)
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }

        if let artistId = song.artistId {
            Button {
                appState.pendingNavigation = .artist(id: artistId)
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }

        Divider()

        let shareText: String = {
            var text = "🎵 \(song.title) — \(song.artist ?? "Unknown Artist")"
            if let album = song.album {
                text += "\nAlbum: \(album)"
            }
            text += "\nvibrdrome://song/\(song.id)"
            return text
        }()
        ShareLink(item: shareText) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}

extension View {
    func trackContextMenu(song: Song, queue: [Song]? = nil, index: Int? = nil) -> some View {
        modifier(TrackContextMenuModifier(song: song, queue: queue, index: index))
    }

    func trackContextMenu(
        song: Song, queue: [Song]? = nil, index: Int? = nil,
        onRemove: @escaping () -> Void
    ) -> some View {
        modifier(TrackContextMenuModifier(song: song, queue: queue, index: index, onRemove: onRemove))
    }
}
