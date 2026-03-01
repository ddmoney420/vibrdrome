#if os(macOS)
import SwiftUI

struct MacContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    private var engine: AudioEngine { AudioEngine.shared }

    private var windowTitle: String {
        if let song = engine.currentSong {
            let artist = song.artist ?? ""
            return artist.isEmpty ? "\(song.title) — Vibrdrome" : "\(song.title) - \(artist) — Vibrdrome"
        }
        if let station = engine.currentRadioStation {
            return "\(station.name) — Vibrdrome"
        }
        return "Vibrdrome"
    }

    var body: some View {
        Group {
            if appState.isConfigured {
                SidebarContentView()
            } else {
                ServerConfigView()
                    .environment(appState)
            }
        }
        .navigationTitle(windowTitle)
        .onChange(of: scenePhase) { _, newPhase in
            guard appState.isConfigured else { return }
            switch newPhase {
            case .inactive:
                // macOS rarely gets .background; save on .inactive
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

}
#endif
