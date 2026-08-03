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

/// Owns the persistent gain node sitting between the player and the EQ.
///
/// Holds no ReplayGain policy of its own — it applies a resolved `GaplessGain` at a moment the
/// scheduler chooses. Keeping policy out of here is what allows album-vs-track gain, preamp changes,
/// and clipping rules to evolve without touching the audio graph.
final class GaplessGainStage {
    let node = AVAudioMixerNode()

    /// Long enough to avoid a step discontinuity, short enough to be inaudible as a fade.
    static let rampSeconds = 0.02

    private(set) var currentGain: GaplessGain = .unity

    init() {
        node.outputVolume = 1.0
    }

    /// Apply a gain to the live node.
    ///
    /// `AVAudioMixerNode.outputVolume` is set directly here; the ramp is documented as the
    /// contract and becomes a scheduled parameter ramp when ReplayGain lands. Callers must invoke
    /// this at the **rendered** boundary, not when a track is scheduled.
    func apply(_ gain: GaplessGain) {
        currentGain = gain
        node.outputVolume = max(0, gain.linear)
    }

    /// Reset to unity — queue replaced or playback stopped.
    func reset() { apply(.unity) }
}
