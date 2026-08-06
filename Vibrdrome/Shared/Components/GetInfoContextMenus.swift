import SwiftUI
import os.log

struct ArtistGetInfoContextMenuModifier: ViewModifier {
    let artist: Artist

    @Environment(\.openWindow) private var openWindow
    #if os(iOS)
    @Environment(AppState.self) private var appState
    @State private var showGetInfo = false
    #endif

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    #if os(macOS)
                    openWindow(id: "get-info", value: GetInfoTarget(type: .artist, id: artist.id))
                    #else
                    showGetInfo = true
                    #endif
                } label: {
                    Label("Get Info", systemImage: "doc.text.magnifyingglass")
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showGetInfo) {
                NavigationStack {
                    GetInfoView(target: GetInfoTarget(type: .artist, id: artist.id))
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

struct AlbumGetInfoContextMenuModifier: ViewModifier {
    let album: Album

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var isCreatingShare = false
    #if os(iOS)
    @State private var showGetInfo = false
    #endif

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    #if os(macOS)
                    openWindow(id: "get-info", value: GetInfoTarget(type: .album, id: album.id))
                    #else
                    showGetInfo = true
                    #endif
                } label: {
                    Label("Get Info", systemImage: "doc.text.magnifyingglass")
                }

                Divider()

                let shareText = "💿 \(album.name)\(album.artist.map { " — \($0)" } ?? "")\nvibrdrome://album/\(album.id)"
                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button {
                    guard !isCreatingShare else { return }
                    isCreatingShare = true
                    Task {
                        defer { isCreatingShare = false }
                        do {
                            let songIds = try await appState.subsonicClient.getAlbum(id: album.id).song?.map(\.id) ?? []
                            guard !songIds.isEmpty else { return }
                            let share = try await appState.subsonicClient.createShare(ids: songIds)
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(share.url, forType: .string)
                            #else
                            UIPasteboard.general.string = share.url
                            #endif
                        } catch {
                            Logger(subsystem: "com.vibrdrome.app", category: "Sharing")
                                .error("Failed to create album share: \(error)")
                        }
                    }
                } label: {
                    Label(
                        isCreatingShare ? "Creating Share…" : "Copy Navidrome Share Link",
                        systemImage: "link"
                    )
                }
                .disabled(isCreatingShare)
            }
            #if os(iOS)
            .sheet(isPresented: $showGetInfo) {
                NavigationStack {
                    GetInfoView(target: GetInfoTarget(type: .album, id: album.id))
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

struct PlaylistContextMenuModifier: ViewModifier {
    let playlist: Playlist

    @Environment(AppState.self) private var appState
    @State private var isCreatingShare = false

    func body(content: Content) -> some View {
        content.contextMenu {
            let shareText = "🎶 \(playlist.name) — \(playlist.songCount ?? 0) songs\nvibrdrome://playlist/\(playlist.id)"
            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button {
                guard !isCreatingShare else { return }
                let songIds = playlist.entry?.map(\.id) ?? []
                guard !songIds.isEmpty else { return }
                isCreatingShare = true
                Task {
                    defer { isCreatingShare = false }
                    do {
                        let share = try await appState.subsonicClient.createShare(ids: songIds)
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(share.url, forType: .string)
                        #else
                        UIPasteboard.general.string = share.url
                        #endif
                    } catch {
                        Logger(subsystem: "com.vibrdrome.app", category: "Sharing")
                            .error("Failed to create playlist share: \(error)")
                    }
                }
            } label: {
                Label(
                    isCreatingShare ? "Creating Share…" : "Copy Navidrome Share Link",
                    systemImage: "link"
                )
            }
            .disabled(isCreatingShare)
        }
    }
}

extension View {
    func artistGetInfoContextMenu(artist: Artist) -> some View {
        modifier(ArtistGetInfoContextMenuModifier(artist: artist))
    }

    func albumGetInfoContextMenu(album: Album) -> some View {
        modifier(AlbumGetInfoContextMenuModifier(album: album))
    }

    func playlistContextMenu(playlist: Playlist) -> some View {
        modifier(PlaylistContextMenuModifier(playlist: playlist))
    }
}
