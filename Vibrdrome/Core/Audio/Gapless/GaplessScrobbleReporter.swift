import AVFoundation
import Foundation

/// A completed play, ready to be submitted.
struct GaplessScrobbleSubmission: Sendable, Equatable {
    let songID: String
    let itemID: GaplessQueueItemID
    let playInstance: GaplessPlayInstanceID
    /// Frames actually rendered to the output for this play.
    let audibleFrames: AVAudioFramePosition
    let audibleSeconds: TimeInterval
}

/// Decides when a play counts, from audible evidence only.
///
/// Reproduces the existing production policy exactly (`AudioEngine.autoScrobbleIfNeeded` /
/// `submitScrobbleIfNeeded`): the threshold is **half the effective duration, capped at 240 s**, and
/// a play counts once. Nothing here is a new rule.
///
/// **Identity is the play instance, not the song or the queue slot.** Repeat One plays the same slot
/// over and over, Repeat All revisits it, a queue can hold the same song twice, and a seek or tail
/// replacement can reuse a slot under a new timeline. Each of those is a separate play that may earn
/// its own scrobble — and none of them may submit twice. Song identity would collapse them all;
/// slot identity would collapse the repeats.
@MainActor
final class GaplessScrobbleReporter {
    private let policy: GaplessCompletionPolicy
    /// Play instances already submitted. The guarantee is one submission per instance, ever.
    private(set) var submittedInstances: Set<GaplessPlayInstanceID> = []
    private(set) var submissions: [GaplessScrobbleSubmission] = []
    /// Instances a "now playing" notification has been sent for, so it also fires once per play.
    private(set) var announcedInstances: Set<GaplessPlayInstanceID> = []

    /// Injected so the reporter is testable without the network, and so the existing offline queue
    /// stays the only thing that talks to the services.
    var submit: ((GaplessScrobbleSubmission) -> Void)?
    var announceNowPlaying: ((String) -> Void)?

    init(sampleRate: Double = GaplessRenderFormat.sampleRate) {
        policy = GaplessCompletionPolicy(sampleRate: sampleRate)
    }

    /// Frames of audible playback a song needs before it counts.
    func thresholdFrames(durationSeconds: TimeInterval) -> AVAudioFramePosition {
        policy.scrobbleThresholdFrames(effectiveDurationSeconds: durationSeconds)
    }

    /// Announce "now playing" for a play instance — once per play, at the audible boundary.
    @discardableResult
    func announce(songID: String, playInstance: GaplessPlayInstanceID) -> Bool {
        guard !announcedInstances.contains(playInstance) else { return false }
        announcedInstances.insert(playInstance)
        announceNowPlaying?(songID)
        return true
    }

    /// Report a play ending. Submits only if it was heard for long enough and has not already been
    /// submitted.
    ///
    /// Called for every way a play can end — natural completion, manual skip, stop, queue
    /// replacement — because the decision depends on how much was *heard*, not on how it ended.
    @discardableResult
    func playEnded(songID: String, itemID: GaplessQueueItemID,
                   playInstance: GaplessPlayInstanceID,
                   audibleFrames: AVAudioFramePosition,
                   durationSeconds: TimeInterval) -> GaplessScrobbleSubmission? {
        guard !submittedInstances.contains(playInstance) else { return nil }
        guard policy.isEligible(audibleFrames: audibleFrames,
                                effectiveDurationSeconds: durationSeconds) else { return nil }
        submittedInstances.insert(playInstance)
        let submission = GaplessScrobbleSubmission(
            songID: songID, itemID: itemID, playInstance: playInstance,
            audibleFrames: audibleFrames,
            audibleSeconds: Double(audibleFrames) / policy.sampleRate)
        submissions.append(submission)
        submit?(submission)
        return submission
    }

    /// Number of submissions for a song across the session — the play count contribution.
    func submissionCount(forSongID songID: String) -> Int {
        submissions.filter { $0.songID == songID }.count
    }

    /// Clear per-session state. Submitted instances are *not* forgotten while the session lives, so
    /// a replayed instance can never double-submit.
    func reset() {
        submittedInstances.removeAll()
        announcedInstances.removeAll()
        submissions.removeAll()
    }
}
