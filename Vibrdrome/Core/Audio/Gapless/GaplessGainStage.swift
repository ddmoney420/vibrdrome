import AVFoundation
import Foundation

/// Per-track gain applied at an exact audible boundary — the seam ReplayGain will land on.
///
/// Defined now, deliberately not applied yet (ReplayGain arrives after EQ passes). What matters at
/// this checkpoint is that the *shape* is right, because retro-fitting per-track gain is what forces
/// people into the two designs this architecture exists to avoid: baking gain into cached files, or
/// rebuilding the graph per track.
///
/// Design commitments:
/// - **A persistent node, never a per-track one.** Gain is a parameter on a node that stays
///   connected, so changing it cannot disturb scheduling or the EQ's filter state.
/// - **Applied at the rendered boundary, not the scheduled one.** The scheduler knows the exact
///   render frame each track starts at, so gain flips when the track becomes *audible* rather than
///   when its data was queued.
/// - **Ramped, never stepped.** An instantaneous gain change on a continuous waveform is a step
///   discontinuity — the same thing as a click. `rampSeconds` is short enough to be inaudible as a
///   fade and long enough to avoid that step.
/// - **Never baked into cached files.** The cache holds the server's bytes unmodified, so a
///   ReplayGain preference change takes effect immediately and cached files stay reusable.
struct GaplessGain: Equatable, Sendable {
    /// Linear gain multiplier (1.0 = unity).
    let linear: Float
    /// Why this value was chosen — kept so diagnostics can distinguish "no metadata" from "0 dB".
    let source: Source

    enum Source: String, Equatable, Sendable {
        /// Per-track ReplayGain metadata.
        case trackGain
        /// Per-album ReplayGain metadata — the right choice for gapless albums, since a per-track
        /// value would change level across a continuous join.
        case albumGain
        /// No usable ReplayGain metadata; unity, so an untagged track is never quietly altered.
        case noMetadata
        /// User preamp only.
        case preampOnly
    }

    static let unity = GaplessGain(linear: 1.0, source: .noMetadata)

    /// Project rule: ReplayGain is capped at 1.5x (+3.5 dB) so hot masters cannot clip.
    static let maximumLinear: Float = 1.5

    /// Combine a ReplayGain value, a user preamp, and peak information into a safe linear gain.
    ///
    /// - Parameters:
    ///   - gainDB: ReplayGain track or album gain, if the file carries one.
    ///   - preampDB: the user's preamp.
    ///   - peak: sample peak from ReplayGain metadata, if present. Used to hold the result below
    ///     clipping — a track whose peak is already near full scale cannot take much boost.
    static func resolve(gainDB: Float?, preampDB: Float = 0, peak: Float? = nil,
                        source: Source) -> GaplessGain {
        guard let gainDB else {
            // No metadata: apply the preamp alone rather than inventing a correction.
            let linear = min(pow(10, preampDB / 20), maximumLinear)
            return GaplessGain(linear: preampDB == 0 ? 1.0 : linear,
                               source: preampDB == 0 ? .noMetadata : .preampOnly)
        }
        var linear = pow(10, (gainDB + preampDB) / 20)
        if let peak, peak > 0 {
            // Never push the loudest sample past full scale.
            linear = min(linear, 1.0 / peak)
        }
        linear = min(linear, maximumLinear)
        return GaplessGain(linear: max(linear, 0), source: source)
    }
}

/// A gain change bound to the render frame at which its track becomes audible.
struct GaplessGainEvent: Equatable, Sendable {
    let trackID: String
    /// Render frame at which this track starts — taken from `GaplessScheduler`, so the gain change
    /// is tied to the same frame accounting that drives metadata and scrobbling.
    let boundaryFrame: AVAudioFramePosition
    let gain: GaplessGain
}

/// Owns the persistent gain node sitting between the player and the EQ.
///
/// Holds no ReplayGain policy of its own — it applies a resolved `GaplessGain` at a frame the
/// scheduler chooses. Keeping policy out of here is what allows album-vs-track gain, preamp changes,
/// and clipping rules to evolve without touching the audio graph.
final class GaplessGainStage {
    let node = AVAudioMixerNode()

    /// Measured smoothing time of `AVAudioMixerNode.outputVolume`: setting it never steps the
    /// signal — the node interpolates internally, reaching 10% in ~2.5 ms, 50% in ~16 ms and 90% in
    /// ~28 ms. Verified across gain jumps up to 1.5x → 0.25x, where an unsmoothed change would have
    /// produced a delta of ~0.5 and instead produced nothing above the tone's own movement
    /// (`spike/gapless-replaygain-ramp`).
    ///
    /// This is a property of the platform node, not a value chosen here: an explicit ramp of our own
    /// would convolve with this smoothing and could only make the transition *longer*, never
    /// shorter or sharper. So the node's own interpolation is the ramp, and the engine's job is to
    /// start it on the right frame.
    static let measuredSmoothingSeconds = 0.028

    private(set) var currentGain: GaplessGain = .unity
    /// Gain changes waiting for their boundary, ordered by frame.
    private(set) var pendingEvents: [GaplessGainEvent] = []
    /// The most recently applied event, for diagnostics and duplicate suppression.
    private(set) var lastAppliedEvent: GaplessGainEvent?

    init() {
        node.outputVolume = 1.0
    }

    /// The frame of the next pending change, so the render loop can stop exactly on it.
    var nextEventFrame: AVAudioFramePosition? { pendingEvents.first?.boundaryFrame }

    // MARK: - Scheduling

    /// Schedule a gain change for the frame at which `trackID` becomes audible. Replaces any
    /// existing event for the same track, so re-preparing a track cannot produce two changes.
    func schedule(_ event: GaplessGainEvent) {
        pendingEvents.removeAll { $0.trackID == event.trackID }
        pendingEvents.append(event)
        pendingEvents.sort { $0.boundaryFrame < $1.boundaryFrame }
    }

    /// Drop pending events for audio that will no longer play — the queue was edited, replaced, or
    /// the user skipped past it. Without this a removed track's gain would still be applied to
    /// whatever ends up at that frame.
    func cancelEvents(fromFrame frame: AVAudioFramePosition) {
        pendingEvents.removeAll { $0.boundaryFrame >= frame }
    }

    func cancelEvent(forTrackID trackID: String) {
        pendingEvents.removeAll { $0.trackID == trackID }
    }

    func cancelAllPendingEvents() {
        pendingEvents.removeAll()
    }

    // MARK: - Application

    /// Apply any event whose boundary has been reached. Called from the render loop with the number
    /// of frames rendered so far, so gain changes happen at the **audible** boundary — not when the
    /// track was downloaded, decoded, scheduled, or its metadata prepared.
    ///
    /// If several events are somehow due at once (a very short track, or a long render slice) only
    /// the last is applied: the intermediate ones describe audio that has already gone by.
    @discardableResult
    func advance(toRenderFrame frame: AVAudioFramePosition) -> GaplessGainEvent? {
        var due: GaplessGainEvent?
        while let next = pendingEvents.first, next.boundaryFrame <= frame {
            due = next
            pendingEvents.removeFirst()
        }
        guard let due else { return nil }
        // Skip a redundant set: an unchanged gain must not restart the node's smoothing, which is
        // what keeps an album-gain join completely untouched.
        if due.gain != currentGain { apply(due.gain) }
        lastAppliedEvent = due
        return due
    }

    /// Apply a gain to the live node immediately.
    ///
    /// Setting `outputVolume` is itself the ramp — see `measuredSmoothingSeconds`. Correct for a
    /// mid-track change (a settings edit); boundary changes should go through `schedule` +
    /// `advance` so they land on the right frame.
    func apply(_ gain: GaplessGain) {
        currentGain = gain
        node.outputVolume = max(0, gain.linear)
    }

    /// Reset to unity and drop every pending change — queue replaced or playback stopped.
    func reset() {
        cancelAllPendingEvents()
        lastAppliedEvent = nil
        apply(.unity)
    }
}
