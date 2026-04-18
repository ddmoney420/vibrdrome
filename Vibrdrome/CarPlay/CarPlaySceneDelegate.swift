#if os(iOS) && CARPLAY_ENABLED
import CarPlay

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    private var carPlayManager: CarPlayManager?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        // C3: Clean up any existing manager before creating a new one
        carPlayManager?.tearDown()
        self.interfaceController = interfaceController
        self.carPlayManager = CarPlayManager(interfaceController: interfaceController)
        carPlayManager?.setupRootTemplate()

        // Ensure remote commands are active for CarPlay controls
        RemoteCommandManager.shared.setup()

        // Refresh now playing info so CarPlay picks up current playback state
        if let song = AudioEngine.shared.currentSong {
            NowPlayingManager.shared.update(song: song, isPlaying: AudioEngine.shared.isPlaying)
            NowPlayingManager.shared.updateElapsedTime(AudioEngine.shared.currentTime)
        } else {
            // No current song — try restoring saved queue
            AudioEngine.shared.restorePlayQueue(client: AppState.shared.subsonicClient)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        carPlayManager?.tearDown()
        self.carPlayManager = nil
        self.interfaceController = nil
    }
}
#endif
