import Foundation

// The routing decision model for playback backends.
//
// **Pure by construction.** Nothing in this file touches `AudioEngine`, `ApplicationPlayback`, the
// router, app state, a network client, a file, a decoder, an audio session, SwiftUI or a user
// default. It is values in, values out — so the whole matrix is testable without an engine, and the
// answer for a given set of facts cannot drift with global state.
//
// **Lane 3B wires it to nothing.** No production path calls `PlaybackBackendPolicy`; the router
// still always selects `.legacy`. Lane 3D is where a decision starts mattering.

// MARK: - Content

/// What kind of thing is being played. The persistent engine schedules a known finite timeline, so
/// anything without one is legacy by definition rather than by capability.
enum PlaybackContentKind: Equatable, Sendable, CaseIterable {
    case finiteTrack
    case radio
    case liveStream
    case unknown
}

// MARK: - Codec

/// The audio representation actually being decoded.
///
/// Support here means *proven by the persistent engine's format matrix*, measured against
/// independently-encoded parts of one continuous tone — not "AVFoundation can probably open it".
enum PlaybackCodec: Equatable, Sendable {
    case flac
    case alac
    case aac
    case opus
    case mp3
    case wav
    /// A codec the persistent engine has no proven support for.
    case other(String)
    /// Not yet determined.
    case unknown

    /// Formats whose decoded length is frame-exact, so a join needs no trim.
    ///
    /// Measured: WAV and FLAC are exact; ALAC and AAC are exact because Apple applies `iTunSMPB`;
    /// Opus is exact (decoding at 48 kHz). MP3 is the exception — `AVAudioFile` hands back encoder
    /// delay *and* padding as ordinary audio, +1368 frames on the measured sample.
    var isFrameExactWithoutTrim: Bool {
        switch self {
        case .flac, .alac, .aac, .opus, .wav: true
        case .mp3, .other, .unknown: false
        }
    }

    /// Whether the persistent engine can decode this at all.
    var isSupportedByPersistentEngine: Bool {
        switch self {
        case .flac, .alac, .aac, .opus, .wav, .mp3: true
        case .other, .unknown: false
        }
    }
}

// MARK: - Delivery

/// How the bytes reach the decoder, and — critically — **whether the representation is confirmed**.
///
/// The persistent engine reads `AVAudioFile(forReading:)`, so every source must exist as a complete
/// local file before playback. A remote track is materialised by a whole-file download first,
/// because a partial file decodes short and would corrupt boundary accounting.
///
/// That materialisation is also where the representation becomes *knowable*: the fetch reads the
/// response's MIME type and names the cache file from it, explicitly because a transcoding server
/// returns a different type than the stored file. A requested format is a request; a response
/// content type is an answer.
enum PlaybackDelivery: Equatable, Sendable {
    /// A file already on the device, in its original representation.
    case localOriginal
    /// A user-downloaded file, original representation.
    case downloadedOriginal
    /// A file already materialised into the gapless cache.
    case cachedPrepared
    /// Remote, served without transcoding, and the representation is confirmed.
    case remoteDirectConfirmed
    /// Remote, transcoded, and the delivered output is confirmed.
    case remoteTranscodeConfirmed(output: PlaybackCodec)
    /// A transcode was *asked for* and the server's answer is not yet known.
    ///
    /// Never a persistent candidate. The client cannot know whether the server honoured the request
    /// until it sees the response, and routing on the configured preference would be guessing.
    case remoteRequestedButUnconfirmed(requested: PlaybackCodec?)
    /// Nothing reliable is known about how this will arrive.
    case unknown

    /// Whether the representation is settled. Only settled deliveries can be persistent candidates.
    var isConfirmed: Bool {
        switch self {
        case .localOriginal, .downloadedOriginal, .cachedPrepared,
             .remoteDirectConfirmed, .remoteTranscodeConfirmed:
            true
        case .remoteRequestedButUnconfirmed, .unknown:
            false
        }
    }
}

// MARK: - Gapless metadata

/// Whether a trim can be applied where one is needed.
enum PlaybackGaplessMetadata: Equatable, Sendable, CaseIterable {
    /// The format is frame-exact on its own — nothing to parse.
    case notRequired
    /// A Xing/Info + LAME header was parsed and its delay and padding are usable.
    case trusted
    /// No gapless header present.
    case absent
    /// A header was present but did not parse.
    case malformed
    /// A header parsed but its values were rejected as implausible.
    case untrusted
    /// Not yet inspected.
    case unknown
}

// MARK: - Routing input

/// The facts routing is allowed to depend on — and nothing else.
///
/// Deliberately **not** a `Song`. The policy must not be able to reach app state, credentials or a
/// network client through its input, and building the facts explicitly is what forces a caller to
/// say how confident it actually is.
struct PlaybackRoutingSource: Equatable, Sendable {
    var contentKind: PlaybackContentKind
    var delivery: PlaybackDelivery
    /// The source's own representation. When `delivery` confirms a transcode, the transcode's
    /// output wins — see `effectiveCodec`.
    var codec: PlaybackCodec
    /// `nil` means not yet discovered. The engine refuses anything above stereo, so an unknown
    /// count cannot be assumed safe.
    var channelCount: Int?
    /// `nil` means not yet discovered. Any rate is acceptable — a mismatch against the fixed
    /// 44.1 kHz graph is handled by the converter — so this is informational, not gating.
    var sampleRate: Double?
    /// `nil` means not yet established. A bounded timeline is required.
    var hasFiniteDuration: Bool?
    var gaplessMetadata: PlaybackGaplessMetadata
    /// `false` forces legacy. `nil` means "not asserted" and defers to codec support.
    var decoderAvailable: Bool?

    init(
        contentKind: PlaybackContentKind,
        delivery: PlaybackDelivery,
        codec: PlaybackCodec,
        channelCount: Int? = nil,
        sampleRate: Double? = nil,
        hasFiniteDuration: Bool? = nil,
        gaplessMetadata: PlaybackGaplessMetadata = .unknown,
        decoderAvailable: Bool? = nil
    ) {
        self.contentKind = contentKind
        self.delivery = delivery
        self.codec = codec
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.hasFiniteDuration = hasFiniteDuration
        self.gaplessMetadata = gaplessMetadata
        self.decoderAvailable = decoderAvailable
    }

    /// What will actually be decoded. A confirmed transcode replaces the source's own codec —
    /// routing on the stored format after the server re-encoded it would be routing on fiction.
    var effectiveCodec: PlaybackCodec {
        if case .remoteTranscodeConfirmed(let output) = delivery { return output }
        return codec
    }
}

// MARK: - Decision

/// Why a decision came out the way it did. A closed set, so diagnostics and tests can assert on the
/// reasoning rather than on a formatted string.
enum PlaybackBackendDecisionReason: String, Equatable, Sendable, CaseIterable {
    case supportedLocalSource
    case supportedDownloadedSource
    case supportedCachedSource
    case supportedConfirmedDirectSource
    case supportedConfirmedTranscode
    /// Persistently playable, but no trim is available, so joins would gap.
    case gaplessMetadataUnavailable
    /// Persistently playable, but the trim values were not trustworthy.
    case gaplessMetadataUntrusted
    case radioContent
    case liveStreamContent
    case indefiniteStream
    /// The source could not be made local within the planner's deadline. Play must not hang on a
    /// large uncached file — legacy streams this session; a later (cached) session goes persistent.
    case sourceMaterializationTimedOut
    case unknownContentKind
    case unknownDelivery
    case unconfirmedTranscode
    case unsupportedCodec
    case unknownCodec
    case unsupportedChannelLayout
    case decoderUnavailable
    case requiredMediaPropertiesUnknown
}

/// The routing answer. **Backend eligibility and gapless capability are separate questions** — an
/// MP3 with no trim header is perfectly playable by the persistent engine, it just cannot promise a
/// seamless join, and forcing it back to legacy for that reason would give up the engine's other
/// advantages for nothing.
struct PlaybackBackendDecision: Equatable, Sendable {
    let backend: PlaybackBackend
    let playableByPersistentEngine: Bool
    let gaplessCapable: Bool
    let reason: PlaybackBackendDecisionReason
}

// MARK: - Policy

/// The routing decision, as a pure function.
///
/// **Consulted by nothing in Lane 3B.** It exists so the matrix can be settled and tested before any
/// audio depends on it.
enum PlaybackBackendPolicy {

    /// Legacy, with a stated reason. Every rejection names its own cause rather than funnelling into
    /// a single `.unsupported`.
    private static func legacy(_ reason: PlaybackBackendDecisionReason) -> PlaybackBackendDecision {
        PlaybackBackendDecision(
            backend: .legacy,
            playableByPersistentEngine: false,
            gaplessCapable: false,
            reason: reason
        )
    }

    /// Staged deliberately: each gate answers one question and either rejects with its own reason or
    /// hands on. A single flat function had to be read end-to-end to know why anything was refused.
    static func decision(for source: PlaybackRoutingSource) -> PlaybackBackendDecision {
        if let rejection = contentRejection(source) { return rejection }
        if let rejection = deliveryRejection(source) { return rejection }
        if let rejection = representationRejection(source) { return rejection }
        if let rejection = mediaPropertyRejection(source) { return rejection }
        return persistentDecision(for: source)
    }

    /// Radio and live streams have no finite timeline to schedule, and a bounded one must be
    /// established rather than assumed.
    private static func contentRejection(
        _ source: PlaybackRoutingSource
    ) -> PlaybackBackendDecision? {
        switch source.contentKind {
        case .radio: return legacy(.radioContent)
        case .liveStream: return legacy(.liveStreamContent)
        case .unknown: return legacy(.unknownContentKind)
        case .finiteTrack: break
        }
        switch source.hasFiniteDuration {
        case .some(false): return legacy(.indefiniteStream)
        case .none: return legacy(.requiredMediaPropertiesUnknown)
        case .some(true): return nil
        }
    }

    /// A requested transcode is a request, not an outcome.
    private static func deliveryRejection(
        _ source: PlaybackRoutingSource
    ) -> PlaybackBackendDecision? {
        switch source.delivery {
        case .unknown: return legacy(.unknownDelivery)
        case .remoteRequestedButUnconfirmed: return legacy(.unconfirmedTranscode)
        case .localOriginal, .downloadedOriginal, .cachedPrepared,
             .remoteDirectConfirmed, .remoteTranscodeConfirmed:
            return nil
        }
    }

    /// What will actually be decoded, and whether anything can decode it.
    private static func representationRejection(
        _ source: PlaybackRoutingSource
    ) -> PlaybackBackendDecision? {
        switch source.effectiveCodec {
        case .unknown: return legacy(.unknownCodec)
        case .other: return legacy(.unsupportedCodec)
        case .flac, .alac, .aac, .opus, .mp3, .wav: break
        }
        // A decoder known to be missing is fatal; "not asserted" defers to codec support.
        if source.decoderAvailable == false { return legacy(.decoderUnavailable) }
        return nil
    }

    /// Mono up-mixes to stereo without changing the frame count, so accounting stays exact; anything
    /// above stereo is refused pending a downmix decision, and an undiscovered count is not safe.
    ///
    /// Sample rate is deliberately **not** gated: a mismatch against the fixed 44.1 kHz graph is the
    /// converter's job, and Opus decoding at 48 kHz is an expected, supported case.
    private static func mediaPropertyRejection(
        _ source: PlaybackRoutingSource
    ) -> PlaybackBackendDecision? {
        switch source.channelCount {
        case .none: return legacy(.requiredMediaPropertiesUnknown)
        case .some(let channels) where channels < 1: return legacy(.requiredMediaPropertiesUnknown)
        case .some(let channels) where channels > 2: return legacy(.unsupportedChannelLayout)
        default: return nil
        }
    }

    /// Persistent is viable by here. Whether it can promise *gapless* is a separate question.
    private static func persistentDecision(
        for source: PlaybackRoutingSource
    ) -> PlaybackBackendDecision {
        func persistent(gapless: Bool, reason: PlaybackBackendDecisionReason) -> PlaybackBackendDecision {
            PlaybackBackendDecision(
                backend: .persistent,
                playableByPersistentEngine: true,
                gaplessCapable: gapless,
                reason: reason
            )
        }

        if source.effectiveCodec.isFrameExactWithoutTrim {
            return persistent(gapless: true, reason: supportedReason(for: source.delivery))
        }

        // MP3: playable either way; seamless only with a trim it can trust.
        switch source.gaplessMetadata {
        case .trusted:
            return persistent(gapless: true, reason: supportedReason(for: source.delivery))
        case .untrusted, .malformed:
            return persistent(gapless: false, reason: .gaplessMetadataUntrusted)
        case .absent, .unknown, .notRequired:
            // `.notRequired` on a format that *does* need a trim is a caller mistake; treating it as
            // "no usable trim" is the conservative reading.
            return persistent(gapless: false, reason: .gaplessMetadataUnavailable)
        }
    }

    private static func supportedReason(
        for delivery: PlaybackDelivery
    ) -> PlaybackBackendDecisionReason {
        switch delivery {
        case .localOriginal: .supportedLocalSource
        case .downloadedOriginal: .supportedDownloadedSource
        case .cachedPrepared: .supportedCachedSource
        case .remoteDirectConfirmed: .supportedConfirmedDirectSource
        case .remoteTranscodeConfirmed: .supportedConfirmedTranscode
        // Unreachable: unconfirmed deliveries returned legacy above.
        case .remoteRequestedButUnconfirmed, .unknown: .unknownDelivery
        }
    }
}
