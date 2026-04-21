import SwiftUI

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
                    openWindow(id: "get-info", value: GetInfoTarget(type: .album, id: album.id))
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

extension View {
    func artistGetInfoContextMenu(artist: Artist) -> some View {
        modifier(ArtistGetInfoContextMenuModifier(artist: artist))
    }

    func albumGetInfoContextMenu(album: Album) -> some View {
        modifier(AlbumGetInfoContextMenuModifier(album: album))
    }
}
