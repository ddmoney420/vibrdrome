import Foundation
import Observation
import os.log

private let timerLog = Logger(subsystem: "com.vibrdrome.app", category: "SleepTimer")

enum SleepTimerMode: Sendable, Equatable {
    case minutes(Int)
    case endOfTrack
}

@Observable
@MainActor
final class SleepTimer {
    static let shared = SleepTimer()

    var isActive = false
    var remainingSeconds: Int = 0
    var mode: SleepTimerMode?

    /// Volume fade factor: 1.0 (full) → 0.0 (silent) in last 30s
    var fadeFactor: Float = 1.0

    private var timer: Timer?
    private let fadeDuration: Int = 30

    private init() {}

    func start(mode: SleepTimerMode) {
        stop()
        self.mode = mode
        isActive = true
        fadeFactor = 1.0

        switch mode {
        case .minutes(let minutes):
            remainingSeconds = minutes * 60
        case .endOfTrack:
            // Will be resolved when track ends
            remainingSeconds = 0
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        remainingSeconds = 0
        mode = nil
        fadeFactor = 1.0
    }

    /// Called when a track ends — if mode is .endOfTrack, trigger pause
    func trackDidEnd() {
        guard isActive, mode == .endOfTrack else { return }
        timerLog.info("Sleep timer: end of track reached")
        expire()
    }

    private func tick() {
        guard isActive else { return }

        if case .endOfTrack = mode {
            // No countdown for end-of-track mode
            return
        }

        remainingSeconds -= 1

        // Fade volume in last 30 seconds
        if remainingSeconds <= fadeDuration && remainingSeconds > 0 {
            fadeFactor = Float(remainingSeconds) / Float(fadeDuration)
        } else if remainingSeconds <= 0 {
            expire()
        }
    }

    private func expire() {
        timerLog.info("Sleep timer expired")
        fadeFactor = 0
        AudioEngine.shared.applyEffectiveVolume()
        AudioEngine.shared.pause()
        stop()
        // Restore volume factor after a delay so the pause has fully taken effect
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            self.fadeFactor = 1.0
        }
    }
}
