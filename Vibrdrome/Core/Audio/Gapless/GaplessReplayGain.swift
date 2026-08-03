import AVFoundation
import Foundation

/// ReplayGain policy for the persistent gapless engine.
///
/// This mirrors the existing `AudioEngine.computeReplayGainFactor(for:)` exactly, so moving playback
/// onto the new engine does not change what users hear. The one *new* capability — peak-based
/// clipping prevention — is off by default, because the current app never reads the peak fields and
/// enabling it silently would change playback levels.
///
/// Existing policy, as implemented today:
/// - Modes: `off` / `track` / `album` (there is **no** automatic mode).
/// - Track mode uses `trackGain`; album mode uses `albumGain`, falling back to `trackGain`.
/// - `trackPeak` / `albumPeak` are fetched, cached and persisted but **never used**.
/// - Clipping protection is a flat cap at 1.5x (+3.5 dB), per the project rule about hot masters.
/// - Preamp (`replayGainPreGainDb`, UI range 0…+6 dB) is added to the ReplayGain value.
/// - Fallback (`replayGainFallbackDb`, UI range −6…0 dB) applies when there is no ReplayGain data
///   *or* when the selected gain field is absent, and is also capped at 1.5x.
/// - The mode is global: radio, playlists, albums and single tracks all use the same one.
/// - `baseGain` is decoded from the server but unused.
struct GaplessReplayGainSettings: Equatable, Sendable {
    enum Mode: String, Sendable, CaseIterable {
        case off, track, album
    }

    let mode: Mode
    /// Added to the ReplayGain value before conversion. UI exposes 0…+6 dB.
    let preampDB: Double
    /// Applied when no usable ReplayGain value exists. UI exposes −6…0 dB.
    let fallbackDB: Double
    /// Off by default — see the type documentation. Turning this on changes playback levels for
    /// tracks whose peak would otherwise clip, which is a user-visible change and so must be opted
    /// into rather than assumed.
    let clippingPreventionEnabled: Bool
    /// Project rule: never boost past 1.5x (+3.5 dB), so hot masters cannot clip.
    let maximumLinear: Float

    static let defaultMaximumLinear: Float = 1.5

    init(mode: Mode, preampDB: Double = 0, fallbackDB: Double = 0,
         clippingPreventionEnabled: Bool = false,
         maximumLinear: Float = defaultMaximumLinear) {
        self.mode = mode
        self.preampDB = preampDB
        self.fallbackDB = fallbackDB
        self.clippingPreventionEnabled = clippingPreventionEnabled
        self.maximumLinear = maximumLinear
    }

    static let off = GaplessReplayGainSettings(mode: .off)

    /// Read the user's current settings, from the same defaults keys the existing engine uses.
    static func current(defaults: UserDefaults = .standard) -> GaplessReplayGainSettings {
        GaplessReplayGainSettings(
            mode: Mode(rawValue: defaults.string(forKey: UserDefaultsKeys.replayGainMode) ?? "off") ?? .off,
            preampDB: defaults.double(forKey: UserDefaultsKeys.replayGainPreGainDb),
            fallbackDB: defaults.double(forKey: UserDefaultsKeys.replayGainFallbackDb),
            clippingPreventionEnabled: false
        )
    }
}

/// Everything that went into one gain decision. Kept as a value so tests can assert on the
/// *reasoning*, and so diagnostics can explain a level without re-deriving it. Carries no media URL
/// and no authentication data — only gain numbers and a track-local reason.
struct GaplessReplayGainDiagnostics: Equatable, Sendable {
    let mode: GaplessReplayGainSettings.Mode
    let rawTrackGainDB: Double?
    let rawAlbumGainDB: Double?
    /// The gain field actually chosen for this mode, before preamp.
    let selectedGainDB: Double?
    let preampDB: Double
    /// The peak field for the selected mode, if present and usable.
    let rawPeak: Double?
    /// How much the clipping guard removed, in dB (0 when it did not engage).
    let clippingAdjustmentDB: Double
    let finalGainDB: Double
    let finalLinearGain: Float
    /// Why a fallback or unity value was used, when it was.
    let fallbackReason: FallbackReason?

    enum FallbackReason: String, Equatable, Sendable {
        /// ReplayGain is switched off; nothing is applied.
        case modeOff
        /// The track carries no ReplayGain data at all.
        case noReplayGainData
        /// ReplayGain data exists but the field for this mode is absent.
        case selectedGainMissing
        /// The gain value is not a usable number (NaN or infinite).
        case selectedGainInvalid
    }
}

enum GaplessReplayGainCalculator {
    /// Resolve the gain for one track.
    ///
    ///     requestedGainDB = replayGainDB + preampDB
    ///     linearGain      = 10 ^ (requestedGainDB / 20)
    ///
    /// then, when clipping prevention is on and a usable peak exists, `linearGain * peak <= 1.0`,
    /// and finally the project's flat 1.5x ceiling. Both guards only ever reduce gain.
    static func resolve(replayGain: ReplayGain?,
                        settings: GaplessReplayGainSettings)
        -> (gain: GaplessGain, diagnostics: GaplessReplayGainDiagnostics) {

        let trackGain = usableNumber(replayGain?.trackGain)
        let albumGain = usableNumber(replayGain?.albumGain)

        func result(_ outcome: Outcome) -> (GaplessGain, GaplessReplayGainDiagnostics) {
            finish(outcome, replayGain: replayGain, settings: settings)
        }
        func fallback(_ reason: GaplessReplayGainDiagnostics.FallbackReason)
            -> (GaplessGain, GaplessReplayGainDiagnostics) {
            result(fallbackOutcome(reason, settings: settings))
        }

        guard settings.mode != .off else {
            return result(Outcome(linear: 1.0, reason: .modeOff, source: .noMetadata))
        }
        guard replayGain != nil else { return fallback(.noReplayGainData) }

        let selected: Double?
        let source: GaplessGain.Source
        switch settings.mode {
        case .off:
            return result(Outcome(linear: 1.0, reason: .modeOff, source: .noMetadata))
        case .track:
            selected = trackGain
            source = .trackGain
        case .album:
            // Album mode falls back to the track value when the album value is absent — existing
            // behaviour, preserved.
            selected = albumGain ?? trackGain
            source = albumGain != nil ? .albumGain : .trackGain
        }

        guard let selectedGainDB = selected else {
            // Distinguish "field absent" from "field present but not a number", because they mean
            // different things about the server's metadata.
            let raw = settings.mode == .track ? replayGain?.trackGain
                : (replayGain?.albumGain ?? replayGain?.trackGain)
            return fallback(raw == nil ? .selectedGainMissing : .selectedGainInvalid)
        }

        let requestedGainDB = selectedGainDB + settings.preampDB
        var linear = Float(pow(10, requestedGainDB / 20))

        // Peak protection: hold the loudest sample at or below full scale.
        let peak = usablePeak(settings.mode == .track
                              ? replayGain?.trackPeak
                              : (replayGain?.albumPeak ?? replayGain?.trackPeak))
        var clipAdjustmentDB = 0.0
        if settings.clippingPreventionEnabled, let peak {
            let ceiling = Float(1.0 / peak)
            if linear > ceiling {
                clipAdjustmentDB = 20 * log10(Double(ceiling / linear))
                linear = ceiling
            }
        }

        return result(Outcome(linear: linear, selectedGainDB: selectedGainDB, peak: peak,
                              clipAdjustmentDB: clipAdjustmentDB, source: source))
    }

    /// One resolved outcome, before the project's ceiling is applied.
    private struct Outcome {
        var linear: Float
        var selectedGainDB: Double?
        var peak: Double?
        var clipAdjustmentDB: Double = 0
        var reason: GaplessReplayGainDiagnostics.FallbackReason?
        var source: GaplessGain.Source
    }

    /// Apply the project's ceiling and package the outcome with its diagnostics.
    private static func finish(_ outcome: Outcome, replayGain: ReplayGain?,
                               settings: GaplessReplayGainSettings)
        -> (GaplessGain, GaplessReplayGainDiagnostics) {
        let clamped = max(0, min(outcome.linear, settings.maximumLinear))
        let diagnostics = GaplessReplayGainDiagnostics(
            mode: settings.mode, rawTrackGainDB: replayGain?.trackGain,
            rawAlbumGainDB: replayGain?.albumGain, selectedGainDB: outcome.selectedGainDB,
            preampDB: settings.preampDB, rawPeak: outcome.peak,
            clippingAdjustmentDB: outcome.clipAdjustmentDB,
            finalGainDB: clamped > 0 ? 20 * log10(Double(clamped)) : -.infinity,
            finalLinearGain: clamped, fallbackReason: outcome.reason)
        return (GaplessGain(linear: clamped, source: outcome.source), diagnostics)
    }

    /// Matches the existing engine: a fallback of 0 dB means unity, not "apply 0 dB as if it were a
    /// real measured value".
    private static func fallbackOutcome(_ reason: GaplessReplayGainDiagnostics.FallbackReason,
                                        settings: GaplessReplayGainSettings) -> Outcome {
        let linear = settings.fallbackDB != 0 ? Float(pow(10, settings.fallbackDB / 20)) : 1.0
        return Outcome(linear: linear, reason: reason,
                       source: settings.fallbackDB != 0 ? .preampOnly : .noMetadata)
    }

    /// Server metadata is not guaranteed to be sane; NaN or infinity must not reach `pow`.
    private static func usableNumber(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// A peak is only meaningful when positive and finite. A peak of 0 would imply silence and would
    /// produce an infinite ceiling.
    private static func usablePeak(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
