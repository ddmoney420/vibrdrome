import AVFoundation
import Foundation

/// The engine-neutral surface every caller uses: UI, Now Playing, scrobbling, remote commands and
/// restoration.
///
/// Nothing above this line may talk to `GaplessRealTimeBackend`, `PersistentGaplessEngine` or
/// `AudioEngine` directly. That is what makes the engine choice an implementation detail rather than
/// a fact scattered through the app — and it is what stops a remote-command handler from capturing
/// one engine while the selector has moved to another.
@MainActor
protocol GaplessPlaybackControlling: AnyObject {
    var playbackState: GaplessEngineState { get }
    var isPlaying: Bool { get }
    /// Song ID of the currently audible item, if any.
    var currentSongID: String? { get }
    /// Seconds into the current item's own audio.
    var elapsedSeconds: TimeInterval { get }
    var queueCount: Int { get }

    func prepare() throws
    func play() async throws
    func pause()
    func resume() throws
    func stop()
    func next() async throws
    @discardableResult
    func previous(elapsedSeconds: TimeInterval) async throws
        -> GaplessTransportPolicy.PreviousDestination
    func seek(toSeconds seconds: TimeInterval) async throws
}

/// Why a command could not be carried out. Mapped to `MPRemoteCommandHandlerStatus` by the
/// coordinator, so the reason survives all the way to the system rather than being flattened.
enum GaplessCommandFailure: Error, Equatable, Sendable {
    /// Nothing to act on — empty queue, or no current item.
    case noActionableItem
    /// The audio session could not be activated.
    case audioSessionUnavailable
    /// The engine could not be started or prepared.
    case engineUnavailable
    /// A seek position outside the item, or with no known duration.
    case invalidPosition
    /// The command is not supported in the current state.
    case unsupported
}

/// Application-level playback controller: owns the engine choice and presents one surface.
///
/// **Selection happens before audio is audible and never during it.** Swapping engines under a
/// playing track would cut the output stream, which is the defect this whole architecture exists to
/// remove — so a selection change while a track is audible is *rejected*, not deferred silently.
@MainActor
final class GaplessApplicationPlaybackController: GaplessPlaybackControlling {
    private let controller: GaplessPlaybackController
    private let selector: GaplessEngineSelector
    private let audioSession: GaplessAudioSessionCoordinator

    /// Bumped whenever the engine choice is re-evaluated, so work started under an old choice can be
    /// recognised as stale.
    private(set) var selectionGeneration: UInt64 = 0
    private(set) var lastSelectionDiagnostics: GaplessSelectionDiagnostics?

    init(controller: GaplessPlaybackController, selector: GaplessEngineSelector,
         audioSession: GaplessAudioSessionCoordinator) {
        self.controller = controller
        self.selector = selector
        self.audioSession = audioSession
    }

    // MARK: - State

    var playbackState: GaplessEngineState { controller.backend.state }
    var isPlaying: Bool { controller.session.isPlaying && controller.backend.state == .playing }
    var currentSongID: String? { controller.session.queue.currentItem?.songID }
    var queueCount: Int { controller.session.queue.count }
    var selectedEngine: GaplessEngineSelection { selector.selection }

    var elapsedSeconds: TimeInterval {
        controller.backend.clockReading(generation: controller.session.queue.generation).elapsedSeconds
    }

    // MARK: - Engine selection

    /// Re-evaluate which engine should play a source. Refused while a track is audible.
    @discardableResult
    func selectEngine(for capability: GaplessCapability, sourceDescription: String,
                      trimReason: GaplessTrim.Reason) -> Bool {
        guard !isTrackAudible else {
            // Never mid-track. The caller keeps the current engine and may retry at a boundary.
            return false
        }
        selectionGeneration += 1
        selector.isTrackAudible = false
        let playable = true          // every classified source is playable; only the guarantee varies
        if !capability.isGaplessCapable, let reason = capability.reason {
            // Playable but not guaranteed gapless. Whether that means fallback is product policy —
            // recorded either way so the decision is visible.
            selector.requestFallback(itemID: sourceDescription, reason: reason)
        }
        lastSelectionDiagnostics = GaplessSelectionDiagnostics(
            selectionGeneration: selectionGeneration, selectedEngine: selector.selection,
            playableByPersistentEngine: playable, gaplessCapable: capability.isGaplessCapable,
            trimClassification: trimReason.rawValue, fallbackReason: capability.reason,
            decidedBeforePlayback: !isTrackAudible)
        return true
    }

    /// True while audio is actually being heard — the window in which selection must not change.
    var isTrackAudible: Bool {
        controller.session.audibleItemID != nil && controller.backend.state == .playing
    }

    // MARK: - Transport

    func prepare() throws { try controller.backend.prepareGraph() }

    func play() async throws {
        guard !controller.session.queue.isEmpty else { throw GaplessCommandFailure.noActionableItem }
        // Already playing: a repeated Play must not create a second activation or play instance.
        guard !isPlaying else { return }
        selector.isTrackAudible = false
        do {
            try await controller.play()
        } catch let failure as GaplessEngineFailure {
            switch failure {
            case .audioSessionActivationFailed: throw GaplessCommandFailure.audioSessionUnavailable
            default: throw GaplessCommandFailure.engineUnavailable
            }
        }
        selector.isTrackAudible = true
    }

    func pause() {
        controller.pause()
        audioSession.pause()             // policy: does not deactivate
        selector.isTrackAudible = false
    }

    func resume() throws {
        guard !controller.session.queue.isEmpty else { throw GaplessCommandFailure.noActionableItem }
        do { try controller.resume() } catch {
            throw GaplessCommandFailure.engineUnavailable
        }
        selector.isTrackAudible = true
    }

    func stop() {
        controller.stop()
        audioSession.stop()              // policy: does not deactivate
        selector.isTrackAudible = false
    }

    func next() async throws {
        guard !controller.session.queue.isEmpty else { throw GaplessCommandFailure.noActionableItem }
        try await controller.next()
    }

    @discardableResult
    func previous(elapsedSeconds seconds: TimeInterval) async throws
        -> GaplessTransportPolicy.PreviousDestination {
        guard !controller.session.queue.isEmpty else { throw GaplessCommandFailure.noActionableItem }
        return try await controller.previous(elapsedSeconds: seconds)
    }

    func seek(toSeconds seconds: TimeInterval) async throws {
        guard let songID = currentSongID else { throw GaplessCommandFailure.noActionableItem }
        guard seconds.isFinite, seconds >= 0 else { throw GaplessCommandFailure.invalidPosition }
        // A position past the end has no audio to schedule; rejecting is better than silently
        // producing a zero-length segment that looks like a broken track.
        if let duration = controller.session.songDurations[songID], seconds > duration {
            throw GaplessCommandFailure.invalidPosition
        }
        try await controller.seek(toSeconds: seconds)
    }

    /// Toggle from authoritative application state, not from the node, the session, or the last
    /// command — each of those can disagree with what the user is actually hearing.
    func togglePlayPause() async throws {
        if isPlaying { pause() } else if playbackState == .paused { try resume() } else { try await play() }
    }
}

/// What the selector decided and why. DEBUG diagnostics only — carries no URL, token or credential.
struct GaplessSelectionDiagnostics: Sendable, Equatable {
    let selectionGeneration: UInt64
    let selectedEngine: GaplessEngineSelection
    /// Whether the persistent engine can play it at all.
    let playableByPersistentEngine: Bool
    /// Whether it can be *guaranteed* gapless. Deliberately separate: a source may be playable
    /// without being gapless-capable, and conflating them would either refuse playable audio or
    /// promise continuity that cannot be delivered.
    let gaplessCapable: Bool
    let trimClassification: String
    let fallbackReason: GaplessFallbackReason?
    let decidedBeforePlayback: Bool
}
