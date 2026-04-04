import SwiftUI
import Network

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab = 0
    @State private var libraryNavPath = NavigationPath()
    @State private var isOffline = false

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
        #if os(iOS)
        .fullScreenCover(isPresented: Bindable(appState).showNowPlaying, onDismiss: {
            handlePendingNavigation()
        }) {
            NowPlayingView()
                .environment(appState)
        }
        #endif
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
                handleWidgetCommand()
            default:
                break
            }
        }
        .overlay(alignment: .top) {
            if isOffline {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                    Text("Offline — Playing downloaded music")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.orange.gradient, in: Capsule())
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: isOffline)
            }
        }
        .task {
            let monitor = NWPathMonitor()
            for await path in monitor.paths() {
                withAnimation {
                    isOffline = path.status != .satisfied
                }
            }
        }
        .sheet(isPresented: Bindable(appState).requiresReAuth) {
            ReAuthView()
                .environment(appState)
                .interactiveDismissDisabled()
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            LibraryView(navPath: $libraryNavPath)
                .tabItem { Label("Library", systemImage: "music.note.house") }
                .tag(0)
            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(1)
            NavigationStack { PlaylistsView() }
                .tabItem { Label("Playlists", systemImage: "music.note.list") }
                .tag(2)
            NavigationStack { RadioView() }
                .tabItem { Label("Radio", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(3)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(4)
        }
        .overlay(alignment: .bottom) {
            if engine.currentSong != nil || engine.currentRadioStation != nil {
                MiniPlayerView()
                    .padding(.bottom, 68)
            }
        }
    }

    private func handlePendingNavigation() {
        guard let nav = appState.pendingNavigation else { return }
        appState.pendingNavigation = nil
        selectedTab = 0
        // Small delay to ensure tab switch completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch nav {
            case .artist(let id):
                libraryNavPath.append(ArtistNavItem(id: id))
            case .album(let id):
                libraryNavPath.append(AlbumNavItem(id: id))
            }
        }
    }

    private func handleWidgetCommand() {
        guard let command = WidgetCommand.consume() else { return }
        switch command {
        case .togglePlayback:
            engine.togglePlayPause()
        case .skipTrack:
            engine.next()
        }
    }
}

// Navigation items for typed NavigationPath
struct ArtistNavItem: Hashable {
    let id: String
}

struct AlbumNavItem: Hashable {
    let id: String
}

// MARK: - NWPathMonitor AsyncStream

extension NWPathMonitor {
    func paths() -> AsyncStream<NWPath> {
        AsyncStream { continuation in
            pathUpdateHandler = { path in
                continuation.yield(path)
            }
            start(queue: DispatchQueue(label: "com.vibrdrome.networkmonitor"))
            continuation.onTermination = { @Sendable _ in
                self.cancel()
            }
        }
    }
}
