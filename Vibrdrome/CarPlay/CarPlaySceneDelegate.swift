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
        CarPlayConnectionState.shared.recordConnect()
        self.interfaceController = interfaceController
        self.carPlayManager = CarPlayManager(interfaceController: interfaceController)
        carPlayManager?.setupRootTemplate()

        // Ensure remote commands are active for CarPlay controls
        RemoteCommandManager.shared.setup()

        // Refresh now playing info so CarPlay picks up current playback state, or restore the
        // saved queue when nothing is loaded. Stays the last step of connection, after manager
        // construction, template setup and remote-command registration.
        CarPlayScenePlaybackActions.syncNowPlayingOrRestoreQueue(
            client: AppState.shared.subsonicClient
        )
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        carPlayManager?.tearDown()
        CarPlayConnectionState.shared.recordDisconnect()
        self.carPlayManager = nil
        self.interfaceController = nil
    }
}
#endif
