#if os(iOS)
import CarPlay

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    private var carPlayManager: CarPlayManager?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didConnect interfaceController: CPInterfaceController) {
        // C3: Clean up any existing manager before creating a new one
        carPlayManager?.tearDown()
        self.interfaceController = interfaceController
        self.carPlayManager = CarPlayManager(interfaceController: interfaceController)
        carPlayManager?.setupRootTemplate()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        carPlayManager?.tearDown()
        self.carPlayManager = nil
        self.interfaceController = nil
    }
}
#endif
