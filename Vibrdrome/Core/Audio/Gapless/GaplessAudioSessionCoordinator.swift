import AVFoundation
import Foundation
import os.log

/// Owns audio-session activation for the persistent engine, and nothing else.
///
/// The whole reason this is a separate, injectable type is that activation is the one operation with
/// an externally visible side effect: activating stops whatever the user is listening to in another
/// app. Build 60 fixed a cold-launch bug where the app activated before the user pressed Play (#134)
/// and silently interrupted Spotify. Keeping activation behind one counted seam is what lets a test
/// assert "restoration activated the session zero times" instead of hoping.
///
/// **Mapped production configuration, preserved exactly:**
/// - category `.playback`, mode `.default`, route-sharing policy `.longFormAudio`, options: none.
/// - `.longFormAudio` is what promotes the app to the system Now Playing app (#45); without it the
///   lock-screen and CarPlay promotion can fail on cold launch.
/// - Configuration happens at launch. **Activation does not.**
/// - Production activates in exactly three places: play, resume, and interruption-ended.
/// - Production **never** calls `setActive(false)` — not on pause, not on stop — and never uses
///   `notifyOthersOnDeactivation`. This type preserves that: it has no deactivation path, because
///   adding one would be a product behaviour change, not an engine change.
@MainActor
final class GaplessAudioSessionCoordinator {
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessSession")

    private(set) var configurationCount = 0
    private(set) var activationCount = 0
    private(set) var isActive = false
    /// Playback state captured when an interruption began, so `.ended` can decide about resuming.
    private(set) var wasPlayingBeforeInterruption = false
    private(set) var isInterrupted = false

    /// Injected so tests can count activations without touching the real session, and so the one
    /// side-effecting call stays visible in the type's surface.
    var configureSession: (() throws -> Void)?
    var activateSession: (() throws -> Void)?

    /// Configure the category at launch. Explicitly does **not** activate.
    func configureAtLaunch() {
        configurationCount += 1
        do { try configureSession?() } catch {
            log.error("audio session configuration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Activate for an explicit playback action. Idempotent while already active, so a repeated Play
    /// does not churn the session.
    @discardableResult
    func activateForPlayback() throws -> Bool {
        guard !isActive else { return false }
        do {
            try activateSession?()
        } catch {
            log.error("audio session activation failed: \(error.localizedDescription, privacy: .public)")
            throw GaplessEngineFailure.audioSessionActivationFailed(error.localizedDescription)
        }
        activationCount += 1
        isActive = true
        return true
    }

    /// Pause. Production leaves the session active — it does not deactivate on pause, and there is
    /// no idle timeout to invent one.
    func pause() {
        // Deliberately empty of session work: the graph, the tail and the session all stay as they
        // are, which is what makes resume instant and keeps the Now Playing promotion.
    }

    /// Stop. Production likewise does not deactivate; the session stays active until the app is
    /// suspended by the system.
    func stop() {
        // See `pause()`. Preserved rather than "improved" — deactivating here would change how the
        // app interacts with other audio apps, which is a product decision.
    }

    // MARK: - Interruption

    /// An interruption began: capture whether we were playing, and let the caller pause.
    func interruptionBegan(wasPlaying: Bool) {
        wasPlayingBeforeInterruption = wasPlaying
        isInterrupted = true
        // The system has already taken the session away; it is no longer ours.
        isActive = false
    }

    /// Whether playback should resume after an interruption, under the **current production rule**.
    ///
    /// Production resumes when `shouldResume || wasPlayingBeforeInterruption` — an OR, not the
    /// system's `shouldResume` alone. See `GaplessAudioSessionCoordinator.resumePolicyNote` for what
    /// that means and why it is preserved here rather than changed.
    func shouldResumeAfterInterruption(systemShouldResume: Bool) -> Bool {
        systemShouldResume || wasPlayingBeforeInterruption
    }

    /// Handle interruption end: reactivate, then report whether to resume.
    ///
    /// Production reactivates the session on `.ended` regardless of whether it then resumes, so that
    /// is preserved.
    @discardableResult
    func interruptionEnded(systemShouldResume: Bool) throws -> Bool {
        isInterrupted = false
        let resume = shouldResumeAfterInterruption(systemShouldResume: systemShouldResume)
        do {
            try activateSession?()
            activationCount += 1
            isActive = true
        } catch {
            log.error("reactivation after interruption failed: \(error.localizedDescription, privacy: .public)")
            wasPlayingBeforeInterruption = false
            throw GaplessEngineFailure.audioSessionActivationFailed(error.localizedDescription)
        }
        wasPlayingBeforeInterruption = false
        return resume
    }

    /// The one case worth flagging, recorded here so it is not lost in a commit message.
    ///
    /// With `wasPlayingBeforeInterruption == true` and the system's `shouldResume == false`, the OR
    /// rule resumes anyway. `shouldResume` is the system's way of saying "do not resume" — for
    /// example after a phone call the user answered on the same device, or when another app has
    /// taken over long-form audio. Resuming against it can restart music the user did not ask for,
    /// and re-activating can pull the route back from whatever took it.
    ///
    /// It is preserved unchanged here because it is existing, shipped behaviour and changing it is a
    /// **product decision**, not part of moving to a new render engine. Folding a behaviour change
    /// into an engine migration is exactly how a regression gets attributed to the wrong thing.
    /// Recommendation and the isolated change belong in their own unit.
    static let resumePolicyNote = """
        Current rule: resume when (systemShouldResume || wasPlayingBeforeInterruption).
        The second term can override the system's explicit "do not resume". Preserved as-is;
        any change should be its own decision, separate from the engine migration.
        """
}
