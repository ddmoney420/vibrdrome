import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var engine: AudioEngine { AudioEngine.shared }

    var body: some View {
        Group {
            if appState.isConfigured {
                if sizeClass == .regular {
                    // iPad — sidebar layout
                    SidebarContentView()
                } else {
                    // iPhone — tab bar layout
                    mainTabView
                }
            } else {
                ServerConfigView()
                    .environment(appState)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard appState.isConfigured else { return }
            switch newPhase {
            case .background:
                engine.savePlayQueue(client: appState.subsonicClient)
                engine.saveQueueLocally()
                engine.createBookmarkIfNeeded(client: appState.subsonicClient)
            case .active:
                engine.restorePlayQueue(client: appState.subsonicClient)
                engine.refreshPlaybackState()
            default:
                break
            }
        }
        .sheet(isPresented: Bindable(appState).requiresReAuth) {
            ReAuthView()
                .environment(appState)
                .interactiveDismissDisabled()
        }
    }

    private var mainTabView: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "music.note.house") }
            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack { PlaylistsView() }
                .tabItem { Label("Playlists", systemImage: "music.note.list") }
            NavigationStack { RadioView() }
                .tabItem { Label("Radio", systemImage: "antenna.radiowaves.left.and.right") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .overlay(alignment: .bottom) {
            if engine.currentSong != nil || engine.currentRadioStation != nil {
                MiniPlayerView()
                    .padding(.bottom, 68)
            }
        }
    }

}
