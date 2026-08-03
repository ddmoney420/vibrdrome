import AVFoundation
import Foundation

/// The persistent EQ stage of the gapless graph.
///
/// The whole point is that this node is built **once** and never rebuilt: the old playback path
/// attached a per-item `MTAudioProcessingTap`, which was the proven cause of a ~150–200 ms position
/// freeze at every track transition. Here the EQ is an ordinary node inside the running graph, so a
/// track boundary is not an EQ event at all — nothing is attached, detached, or reset, and the
/// filter state simply carries on across the join the way it would mid-track.
///
/// Maps the existing `EQEngine` / `EQTapProcessor` semantics onto `AVAudioUnitEQ` without changing
/// anything the user can hear or set:
///
/// | setting        | existing (`EQTapProcessor`)                    | here                                 |
/// |----------------|-----------------------------------------------|--------------------------------------|
/// | bands          | 10                                            | 10                                   |
/// | frequencies    | `EQPresets.frequencies` (32 Hz … 16 kHz ISO)  | same, per band                       |
/// | filter shape   | RBJ cookbook peaking biquad                   | `.parametric` (same peaking shape)   |
/// | bandwidth      | 1.0 octave (fixed)                            | `bandwidth = 1.0` octave             |
/// | gain range     | clamped ±12 dB in `EQEngine.setGain`          | same clamp applied here              |
/// | clip guard     | pre-gain `10^(-maxBoost/20)` before filtering | `globalGain = -maxBoost` dB          |
/// | presets        | `EQPresets` + custom, persisted in defaults   | unchanged — read through `EQEngine`  |
///
/// Pre-gain placement differs (input attenuation vs the unit's global gain) but the result does not:
/// the biquads are linear, so scaling before or after the filter chain is mathematically identical.
/// Float32 rendering has ample headroom, so there is no dynamic-range cost to the move.
struct GaplessEQSettings: Equatable, Sendable {
    /// Per-band gains in dB, one per `EQPresets.frequencies` entry.
    let gains: [Float]
    /// Whether the user has EQ switched on. Off means transparent bypass, not "flat gains".
    let isEnabled: Bool

    static let bypassed = GaplessEQSettings(gains: Array(repeating: 0, count: 10), isEnabled: false)

    /// Matches `EQEngine.setGain`, which clamps every band to ±12 dB.
    static let gainLimitDB: Float = 12

    /// Mirrors `EQTapProcessor`: attenuate by the largest positive band gain so EQ boost cannot
    /// clip. Below 0.5 dB of boost the existing code applies no attenuation, and neither does this.
    var clipGuardGainDB: Float {
        let maxBoost = gains.max() ?? 0
        return maxBoost > 0.5 ? -maxBoost : 0
    }

    /// Current state of the shared `EQEngine`, mapped onto this value type.
    @MainActor
    static func current() -> GaplessEQSettings {
        GaplessEQSettings(gains: EQEngine.shared.customGains,
                          isEnabled: AudioEngine.shared.eqEnabled)
    }
}

/// Owns the persistent `AVAudioUnitEQ` and applies settings to it in place.
///
/// Every method here mutates parameters on a node that stays connected and running. Nothing in this
/// type stops the engine, touches the player node, or affects what is scheduled — which is what lets
/// EQ changes and track boundaries stay completely independent of each other.
final class GaplessEQStage {
    let node: AVAudioUnitEQ

    /// Duration of the parameter ramp used for every runtime EQ change.
    ///
    /// Measured, not guessed: applying an EQ change in one step produced a clear discontinuity in
    /// the offline render (worst sample-to-sample delta ~5x the signal's own in-cycle step) because
    /// the transfer function changes between one sample and the next — which is what a click *is*.
    /// Ramping removes it without recreating the node.
    static let rampSeconds = 0.05
    /// Frames between ramp updates. Finer steps mean a smaller parameter jump per update; this value
    /// keeps each step well below the signal's own sample-to-sample movement.
    static let rampUpdateFrames = 16

    /// How long the bands run flat before bypass is actually engaged.
    ///
    /// Flattening the bands is not enough on its own: the biquads still hold decaying energy from
    /// the previous curve, and bypassing discards it in a single sample. Measured directly —
    /// engaging bypass the instant the ramp ended produced a step of 0.071 (about 8x the signal's
    /// own in-cycle movement), while letting the filters settle first left the output clean. 50 ms
    /// was already sufficient in measurement; this allows a wide margin for a heavily boosted low
    /// band, whose stored energy decays slowest. The delay costs nothing audible — the node is
    /// already transparent throughout it.
    static let bypassSettleSeconds = 0.2

    /// The user's requested state — what the EQ is heading toward, which may differ from what the
    /// node is applying right now while a ramp is in flight.
    private(set) var settings: GaplessEQSettings = .bypassed

    /// Gains currently applied to the node.
    private var appliedGains: [Float]
    private var rampFromGains: [Float] = []
    private var rampToGains: [Float] = []
    private var rampFromGlobalGain: Float = 0
    private var rampToGlobalGain: Float = 0
    private var rampRemainingFrames = 0
    private var rampTotalFrames = 0
    /// Frames left running flat-but-active before bypass is engaged.
    private var settleRemainingFrames = 0
    /// Render rate of the most recent transition, used to size the settle period.
    private var lastSampleRate = GaplessRenderFormat.sampleRate

    /// True while a parameter ramp is in flight.
    var isRamping: Bool { rampRemainingFrames > 0 }
    /// True while the bands are flat and the filters are draining, ahead of engaging bypass.
    var isSettlingBeforeBypass: Bool { settleRemainingFrames > 0 }
    /// True while any part of a transition is still outstanding.
    var isTransitioning: Bool { isRamping || isSettlingBeforeBypass }

    init(bandCount: Int = EQPresets.frequencies.count) {
        node = AVAudioUnitEQ(numberOfBands: bandCount)
        appliedGains = Array(repeating: 0, count: bandCount)
        configureBands()
        apply(.bypassed)
    }

    /// One-time band setup: shape, centre frequency and bandwidth never change at runtime, only
    /// gain does. Doing this once is what keeps a band change from disturbing the graph.
    private func configureBands() {
        for (index, band) in node.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = index < EQPresets.frequencies.count
                ? EQPresets.frequencies[index]
                : Float(1_000)
            band.bandwidth = 1.0                    // octaves — matches EQTapProcessor
            band.gain = 0
            band.bypass = false
        }
    }

    /// Apply settings to the live node immediately, with no ramp.
    ///
    /// Correct before playback starts (initial state) but not for a runtime change on a signal that
    /// is already flowing — use `beginTransition(to:sampleRate:)` for that.
    func apply(_ settings: GaplessEQSettings) {
        self.settings = settings
        rampRemainingFrames = 0
        settleRemainingFrames = 0
        let target = Self.clamped(settings.gains, bandCount: node.bands.count)
        setNodeGains(settings.isEnabled ? target : Array(repeating: 0, count: node.bands.count))
        node.globalGain = settings.isEnabled ? settings.clipGuardGainDB : 0
        node.bypass = !settings.isEnabled
        // Remember the user's gains even while bypassed, so re-enabling restores them.
        appliedGains = settings.isEnabled ? target : appliedGains
        if settings.isEnabled { appliedGains = target }
    }

    /// Begin a ramped transition to new settings. Safe to call at any time, including mid-track and
    /// while scheduled audio is pending: it touches parameters only, never the graph.
    ///
    /// Enabling drops bypass *first*, while the bands are still flat — a 0 dB parametric band is
    /// mathematically unity, so the node is transparent at that instant and dropping bypass is
    /// inaudible. Disabling ramps the bands flat and only then re-engages bypass, which is likewise
    /// a no-op by the time it happens. That is how EQ off stays a genuine bypass (no filter cost)
    /// without the switch itself ever being a discontinuity.
    func beginTransition(to settings: GaplessEQSettings, sampleRate: Double) {
        self.settings = settings
        lastSampleRate = sampleRate
        settleRemainingFrames = 0
        let flat = [Float](repeating: 0, count: node.bands.count)
        let target = Self.clamped(settings.gains, bandCount: node.bands.count)

        if settings.isEnabled && node.bypass {
            setNodeGains(flat)              // transparent right now...
            node.globalGain = 0
            node.bypass = false             // ...so leaving bypass changes nothing audible
            appliedGains = flat
        }

        rampFromGains = appliedGains
        rampToGains = settings.isEnabled ? target : flat
        rampFromGlobalGain = node.globalGain
        rampToGlobalGain = settings.isEnabled ? settings.clipGuardGainDB : 0
        rampTotalFrames = max(1, Int(Self.rampSeconds * sampleRate))
        rampRemainingFrames = rampTotalFrames

        if rampFromGains == rampToGains && rampFromGlobalGain == rampToGlobalGain {
            finishRamp()                    // nothing to move
        }
    }

    /// Advance an in-flight transition by the number of frames just rendered. Driven by the render
    /// loop so the ramp measures in audio time, which is the only clock that matters here.
    func advanceRamp(byFrames frames: Int) {
        if rampRemainingFrames == 0 && settleRemainingFrames > 0 {
            settleRemainingFrames = max(0, settleRemainingFrames - max(0, frames))
            if settleRemainingFrames == 0 {
                // The filters have drained, so bypass is now acoustically a no-op.
                node.bypass = !settings.isEnabled
            }
            return
        }
        guard rampRemainingFrames > 0 else { return }
        rampRemainingFrames = max(0, rampRemainingFrames - max(0, frames))
        let progress = Float(rampTotalFrames - rampRemainingFrames) / Float(rampTotalFrames)

        var interpolated = [Float](repeating: 0, count: node.bands.count)
        for index in interpolated.indices {
            let from = index < rampFromGains.count ? rampFromGains[index] : 0
            let to = index < rampToGains.count ? rampToGains[index] : 0
            interpolated[index] = from + (to - from) * progress
        }
        setNodeGains(interpolated)
        node.globalGain = rampFromGlobalGain + (rampToGlobalGain - rampFromGlobalGain) * progress
        appliedGains = interpolated

        if rampRemainingFrames == 0 { finishRamp() }
    }

    /// Maximum frames the next render slice may cover, so ramp updates stay fine-grained.
    /// `nil` when no ramp is running and slices need no limit.
    var rampSliceLimit: Int? { isRamping ? Self.rampUpdateFrames : nil }

    private func finishRamp() {
        rampRemainingFrames = 0
        let final = settings.isEnabled
            ? Self.clamped(settings.gains, bandCount: node.bands.count)
            : [Float](repeating: 0, count: node.bands.count)
        setNodeGains(final)
        node.globalGain = settings.isEnabled ? settings.clipGuardGainDB : 0
        appliedGains = final

        if settings.isEnabled {
            settleRemainingFrames = 0            // already un-bypassed at the start of the ramp
        } else {
            // Flat is not yet the same as bypassed: the biquads still hold decaying energy from the
            // previous curve. Keep running transparently until it drains, then engage bypass.
            settleRemainingFrames = max(1, Int(Self.bypassSettleSeconds * lastSampleRate))
        }
    }

    private func setNodeGains(_ gains: [Float]) {
        for (index, band) in node.bands.enumerated() {
            band.gain = index < gains.count ? gains[index] : 0
        }
    }

    private static func clamped(_ gains: [Float], bandCount: Int) -> [Float] {
        (0..<bandCount).map { index in
            let raw = index < gains.count ? gains[index] : 0
            return min(max(raw, -GaplessEQSettings.gainLimitDB), GaplessEQSettings.gainLimitDB)
        }
    }

    /// Change one band — the hot path while a user drags a slider.
    func setGain(_ gain: Float, forBand index: Int, sampleRate: Double) {
        guard index >= 0, index < node.bands.count else { return }
        var gains = settings.gains
        while gains.count < node.bands.count { gains.append(0) }
        gains[index] = gain
        beginTransition(to: GaplessEQSettings(gains: gains, isEnabled: settings.isEnabled),
                        sampleRate: sampleRate)
    }

    /// Turn EQ on or off. Bypass is a genuine transparent path — the unit is skipped entirely rather
    /// than run with flat bands — but the switch itself is ramped so it cannot click.
    func setEnabled(_ enabled: Bool, sampleRate: Double) {
        beginTransition(to: GaplessEQSettings(gains: settings.gains, isEnabled: enabled),
                        sampleRate: sampleRate)
    }

    /// The gain the node is actually applying at a given band, for tests and diagnostics.
    func effectiveGain(forBand index: Int) -> Float {
        guard index >= 0, index < node.bands.count else { return 0 }
        return node.bands[index].gain
    }
}
