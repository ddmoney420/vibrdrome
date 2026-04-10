import AVFoundation
import Foundation
import os.log

private let crossfadeLog = Logger(subsystem: "com.vibrdrome.app", category: "Crossfade")

/// Crossfade volume curve types
enum CrossfadeCurve: String, CaseIterable, Sendable {
    case linear
    case equalPower
    case logarithmic

    var label: String {
        switch self {
        case .linear: "Linear"
        case .equalPower: "Equal Power"
        case .logarithmic: "Logarithmic"
        }
    }

    /// Compute fade-out gain for a given progress (0.0 = start, 1.0 = end)
    func fadeOutGain(_ progress: Float) -> Float {
        switch self {
        case .linear:
            return 1.0 - progress
        case .equalPower:
            return cos(progress * .pi / 2)
        case .logarithmic:
            return pow(1.0 - progress, 2)
        }
    }

    /// Compute fade-in gain for a given progress (0.0 = start, 1.0 = end)
    func fadeInGain(_ progress: Float) -> Float {
        switch self {
        case .linear:
            return progress
        case .equalPower:
            return sin(progress * .pi / 2)
        case .logarithmic:
            return pow(progress, 2)
        }
    }
}

/// Manages dual-player crossfade transitions.
/// When crossfadeDuration > 0, this controller handles volume ramps between two AVPlayer instances.
@MainActor
final class CrossfadeController {
    private var playerA: AVPlayer?
    private var playerB: AVPlayer?
    private var activeIsA = true

    /// The currently active player
    var activePlayer: AVPlayer? {
        activeIsA ? playerA : playerB
    }

    /// The inactive (standby) player used for crossfade incoming track
    var inactivePlayer: AVPlayer? {
        activeIsA ? playerB : playerA
    }

    /// Volume factors for crossfade ramp (0.0 - 1.0)
    var outFactor: Float = 1.0
    var inFactor: Float = 0.0

    private var rampTimer: Timer?
    private var rampStartTime: Date?
    private var rampDuration: TimeInterval = 0
    private var rampCompletion: (() -> Void)?

    /// Whether the dual-player system has been initialized
    var isSetUp: Bool { playerA != nil && playerB != nil }

    /// Initialize with two AVPlayer instances
    func setup() {
        if playerA == nil {
            playerA = AVPlayer()
            playerA?.automaticallyWaitsToMinimizeStalling = true
        }
        if playerB == nil {
            playerB = AVPlayer()
            playerB?.automaticallyWaitsToMinimizeStalling = true
        }
        activeIsA = true
        outFactor = 1.0
        inFactor = 0.0
    }

    /// Tear down both players
    func tearDown() {
        cancelRamp()
        playerA?.pause()
        playerA?.replaceCurrentItem(with: nil)
        playerB?.pause()
        playerB?.replaceCurrentItem(with: nil)
        playerA = nil
        playerB = nil
        outFactor = 1.0
        inFactor = 0.0
    }

    /// Load a track onto the active player (used for initial play)
    func loadOnActive(url: URL) {
        let item = AudioEngine.makePlayerItem(url: url)
        activePlayer?.replaceCurrentItem(with: item)
    }

    /// Begin crossfade transition: load next track on inactive player and start ramp.
    /// Call `startInactivePlayback()` after applying any processing (e.g. EQ tap) to start playback.
    func beginCrossfade(nextURL: URL, duration: TimeInterval, onComplete: @escaping () -> Void) {
        cancelRamp()

        let item = AudioEngine.makePlayerItem(url: nextURL)
        inactivePlayer?.replaceCurrentItem(with: item)

        rampDuration = duration
        rampStartTime = Date()
        rampCompletion = onComplete
        outFactor = 1.0
        inFactor = 0.0

        rampTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tickRamp()
            }
        }
    }

    /// Called on manual skip during crossfade — instantly complete the transition
    func forceComplete() {
        cancelRamp()
        activePlayer?.pause()
        activePlayer?.replaceCurrentItem(with: nil)
        activeIsA.toggle()
        outFactor = 1.0
        inFactor = 0.0
    }

    /// Swap active/inactive after ramp completes
    func swapPlayers() {
        activeIsA.toggle()
        outFactor = 1.0
        inFactor = 0.0
    }

    private var currentCurve: CrossfadeCurve {
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.crossfadeCurve) ?? "linear"
        return CrossfadeCurve(rawValue: raw) ?? .linear
    }

    private func tickRamp() {
        guard let startTime = rampStartTime, rampDuration > 0 else { return }
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = Float(min(elapsed / rampDuration, 1.0))

        let curve = currentCurve
        outFactor = curve.fadeOutGain(progress)
        inFactor = curve.fadeInGain(progress)

        // Notify AudioEngine to apply effective volume
        AudioEngine.shared.applyEffectiveVolume()

        if progress >= 1.0 {
            let completion = rampCompletion
            cancelRamp()
            // Old active player is done
            activePlayer?.pause()
            activePlayer?.replaceCurrentItem(with: nil)
            swapPlayers()
            completion?()
        }
    }

    /// Whether a crossfade ramp is currently in progress
    var isRamping: Bool { rampTimer != nil }

    /// Cancel any in-progress ramp timer
    func cancelRamp() {
        rampTimer?.invalidate()
        rampTimer = nil
        rampStartTime = nil
        rampCompletion = nil
    }
}
