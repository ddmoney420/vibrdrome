#if os(iOS)
import UIKit

/// Detects device shake and shuffles the queue if enabled in settings.
extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.shakeToShuffle) else { return }
        guard AudioEngine.shared.currentSong != nil else { return }

        Task { @MainActor in
            Haptics.medium()
            AudioEngine.shared.toggleShuffle()
        }
    }
}
#endif
