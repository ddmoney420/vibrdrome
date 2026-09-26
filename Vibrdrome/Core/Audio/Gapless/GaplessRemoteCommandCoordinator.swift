import Foundation

/// The remote commands the app exposes.
enum GaplessRemoteCommand: String, Sendable, Equatable, CaseIterable {
    case play, pause, togglePlayPause, nextTrack, previousTrack, changePlaybackPosition
    case like, dislike
    /// Deliberately disabled in production so iOS shows next/previous on the lock screen instead of
    /// 15-second skip buttons.
    case skipForward, skipBackward
}

/// The outcome the system is told about, mapped 1:1 onto `MPRemoteCommandHandlerStatus`.
///
/// Modelled separately so the mapping is testable without `MediaPlayer`, and so a command cannot
/// quietly return success for work that failed. The existing production handlers return `.success`
/// unconditionally; this preserves every *successful* path's behaviour while giving real failures a
/// truthful status.
enum GaplessRemoteCommandStatus: String, Sendable, Equatable {
    case success
    case noActionableNowPlayingItem
    case commandFailed
    case noSuchContent

    static func mapping(for failure: GaplessCommandFailure) -> GaplessRemoteCommandStatus {
        switch failure {
        case .noActionableItem: return .noActionableNowPlayingItem
        case .invalidPosition: return .commandFailed
        case .audioSessionUnavailable, .engineUnavailable: return .commandFailed
        case .unsupported: return .noSuchContent
        }
    }
}

/// Identifies one registration cycle, so duplicate registration is detectable.
struct GaplessHandlerToken: Hashable, Sendable, CustomStringConvertible {
    let rawValue: UInt64
    var description: String { "h\(rawValue)" }
}

/// The single owner of remote-command registration.
///
/// **Production audit.** `RemoteCommandManager.shared.setup()` registers once for the app's lifetime
/// behind an `isSetup` flag, never removes handlers, and never re-registers after a media-services
/// reset. Handlers call `AudioEngine.shared` — a singleton, so they cannot capture a stale engine
/// instance. Enabled: play, pause, togglePlayPause, nextTrack, previousTrack,
/// changePlaybackPosition, like, dislike. Disabled: skipForward, skipBackward. Every handler returns
/// `.success` unconditionally except a seek event that fails to cast.
///
/// Registration lives **here**, above the engine, not inside `GaplessRealTimeBackend` or
/// `PersistentGaplessEngine`. That is what allows the engine to be rebuilt after a configuration
/// change or media-services reset without the command handlers being torn down and re-added — the
/// path that would otherwise accumulate duplicates.
@MainActor
final class GaplessRemoteCommandCoordinator {
    /// Commands enabled in production. Preserved exactly.
    static let enabledCommands: Set<GaplessRemoteCommand> = [
        .play, .pause, .togglePlayPause, .nextTrack, .previousTrack, .changePlaybackPosition,
        .like, .dislike
    ]
    /// Deliberately disabled so the lock screen shows track navigation, not 15-second skips.
    static let disabledCommands: Set<GaplessRemoteCommand> = [.skipForward, .skipBackward]

    private weak var controller: GaplessApplicationPlaybackController?
    private(set) var registrationToken: GaplessHandlerToken?
    private(set) var registrationCount = 0
    private(set) var handledCommands: [(GaplessRemoteCommand, GaplessRemoteCommandStatus)] = []
    /// Commands rejected because they arrived under a superseded registration.
    private(set) var rejectedStaleCommands = 0
    private var nextToken: UInt64 = 1

    /// Injected so tests can prove enablement without `MPRemoteCommandCenter`.
    var applyEnablement: ((GaplessRemoteCommand, Bool) -> Void)?

    init(controller: GaplessApplicationPlaybackController? = nil) {
        self.controller = controller
    }

    /// Register once. Repeat calls are no-ops — the guarantee is one active handler per command, and
    /// re-registering is how duplicates appear.
    @discardableResult
    func registerIfNeeded() -> GaplessHandlerToken {
        if let existing = registrationToken { return existing }
        let token = GaplessHandlerToken(rawValue: nextToken)
        nextToken += 1
        registrationToken = token
        registrationCount += 1
        for command in Self.enabledCommands { applyEnablement?(command, true) }
        for command in Self.disabledCommands { applyEnablement?(command, false) }
        return token
    }

    /// Explicitly replace the registration — the only path that produces a new token, used if the
    /// system ever clears the command centre. The old token is immediately stale.
    @discardableResult
    func reregister() -> GaplessHandlerToken {
        registrationToken = nil
        return registerIfNeeded()
    }

    func isCurrent(_ token: GaplessHandlerToken) -> Bool { token == registrationToken }

    /// Number of active handlers for a command — one, or zero before registration.
    func activeHandlerCount(for command: GaplessRemoteCommand) -> Int {
        guard registrationToken != nil else { return 0 }
        return Self.enabledCommands.contains(command) ? 1 : 0
    }

    func attach(controller: GaplessApplicationPlaybackController) {
        self.controller = controller
    }

    // MARK: - Dispatch

    /// Handle a command, returning the status the system should see.
    ///
    /// Commands from a superseded registration are rejected rather than executed: after a
    /// re-registration the old handler must not drive the current engine.
    @discardableResult
    func handle(_ command: GaplessRemoteCommand, token: GaplessHandlerToken,
                positionSeconds: TimeInterval? = nil,
                elapsedSeconds: TimeInterval = 0) async -> GaplessRemoteCommandStatus {
        guard isCurrent(token) else {
            rejectedStaleCommands += 1
            return .commandFailed
        }
        // An unsupported command is unsupported regardless of whether a controller is attached, so
        // it is answered before anything else.
        guard !Self.disabledCommands.contains(command) else {
            record(command, .noSuchContent)
            return .noSuchContent
        }
        guard let controller else {
            record(command, .noActionableNowPlayingItem)
            return .noActionableNowPlayingItem
        }
        do {
            switch command {
            case .play:
                try await controller.play()
            case .pause:
                controller.pause()
            case .togglePlayPause:
                try await controller.togglePlayPause()
            case .nextTrack:
                try await controller.next()
            case .previousTrack:
                _ = try await controller.previous(elapsedSeconds: elapsedSeconds)
            case .changePlaybackPosition:
                guard let positionSeconds else {
                    record(command, .commandFailed)
                    return .commandFailed
                }
                try await controller.seek(toSeconds: positionSeconds)
            case .like, .dislike:
                // Handled by the existing star/unstar path; playback is unaffected.
                break
            case .skipForward, .skipBackward:
                // Already handled above; unreachable, but the switch must stay exhaustive.
                return .noSuchContent
            }
        } catch let failure as GaplessCommandFailure {
            let status = GaplessRemoteCommandStatus.mapping(for: failure)
            record(command, status)
            return status
        } catch {
            record(command, .commandFailed)
            return .commandFailed
        }
        record(command, .success)
        return .success
    }

    private func record(_ command: GaplessRemoteCommand, _ status: GaplessRemoteCommandStatus) {
        handledCommands.append((command, status))
    }

    /// How asynchronous preparation is represented: a command that starts work which cannot fail
    /// synchronously returns `.success` once the work is *accepted and under way* — the engine is
    /// started and the queue is committed. A command that can determine failure synchronously
    /// (empty queue, activation refused, invalid position) returns the mapped failure instead of
    /// optimistically succeeding.
    static let asynchronousPreparationNote = """
        Commands return .success once the action is accepted and the engine has started, not when
        every future track is prepared. Synchronously-knowable failures — empty queue, audio-session
        refusal, engine start failure, invalid seek position — return a mapped failure status rather
        than .success.
        """
}
