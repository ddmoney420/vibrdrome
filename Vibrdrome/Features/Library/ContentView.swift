import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var engine: AudioEngine { AudioEngine.shared }
    @State private var showMiniPlayer = true
    @State private var hideTask: Task<Void, Never>?
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion = false

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
                    .offset(y: showMiniPlayer ? 0 : 140)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showMiniPlayer)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 15)
                .onChanged { _ in
                    hideTask?.cancel()
                    if showMiniPlayer {
                        showMiniPlayer = false
                    }
                }
                .onEnded { _ in
                    hideTask?.cancel()
                    hideTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        showMiniPlayer = true
                    }
                }
        )
    }

}
