import Foundation
import Testing
@testable import Vibrdrome

/// Lane 3B: the playback-backend routing decision, as a pure function.
///
/// **Table-driven on purpose.** This is a policy matrix, and the failure mode worth defending
/// against is a case nobody thought about resolving into the wrong default. Every row states its
/// facts and its expected answer, so an unlisted combination is visibly unlisted rather than
/// quietly handled.
///
/// **The two questions are separate.** "Can the persistent engine play this?" and "can it promise a
/// seamless join?" have different answers for MP3 without a trim header, and collapsing them would
/// either give up the engine for playable content or promise gapless it cannot deliver.
///
/// The policy is consulted by nothing in production; `ApplicationPlaybackRouterIsolationTests`
/// below pins that.
@Suite
struct PlaybackBackendPolicyTests {

    /// One row of the matrix.
    private struct Row {
        let name: String
        let source: PlaybackRoutingSource
        let backend: PlaybackBackend
        let playable: Bool
        let gapless: Bool
        let reason: PlaybackBackendDecisionReason
    }

    /// A finite, stereo, duration-known track — the baseline every row varies from.
    private static func track(
        codec: PlaybackCodec,
        delivery: PlaybackDelivery,
        channels: Int? = 2,
        sampleRate: Double? = 44_100,
        finite: Bool? = true,
        metadata: PlaybackGaplessMetadata = .notRequired,
        decoder: Bool? = nil
    ) -> PlaybackRoutingSource {
        PlaybackRoutingSource(
            contentKind: .finiteTrack,
            delivery: delivery,
            codec: codec,
            channelCount: channels,
            sampleRate: sampleRate,
            hasFiniteDuration: finite,
            gaplessMetadata: metadata,
            decoderAvailable: decoder
        )
    }

    private static let rows: [Row] = [
        // MARK: Finite direct sources — frame-exact formats

        Row(name: "FLAC local", source: track(codec: .flac, delivery: .localOriginal),
            backend: .persistent, playable: true, gapless: true, reason: .supportedLocalSource),
        Row(name: "FLAC downloaded", source: track(codec: .flac, delivery: .downloadedOriginal),
            backend: .persistent, playable: true, gapless: true, reason: .supportedDownloadedSource),
        Row(name: "FLAC cached", source: track(codec: .flac, delivery: .cachedPrepared),
            backend: .persistent, playable: true, gapless: true, reason: .supportedCachedSource),
        Row(name: "FLAC confirmed direct remote",
            source: track(codec: .flac, delivery: .remoteDirectConfirmed),
            backend: .persistent, playable: true, gapless: true,
            reason: .supportedConfirmedDirectSource),
        Row(name: "ALAC local", source: track(codec: .alac, delivery: .localOriginal),
            backend: .persistent, playable: true, gapless: true, reason: .supportedLocalSource),
        Row(name: "AAC local", source: track(codec: .aac, delivery: .localOriginal),
            backend: .persistent, playable: true, gapless: true, reason: .supportedLocalSource),
        Row(name: "WAV local", source: track(codec: .wav, delivery: .localOriginal),
            backend: .persistent, playable: true, gapless: true, reason: .supportedLocalSource),
        // Opus decodes at 48 kHz against a 44.1 kHz graph — the converter's job, not a rejection.
        Row(name: "Opus prepared at 48 kHz",
            source: track(codec: .opus, delivery: .cachedPrepared, sampleRate: 48_000),
            backend: .persistent, playable: true, gapless: true, reason: .supportedCachedSource),
        Row(name: "Mono FLAC (up-mixes without changing frame count)",
            source: track(codec: .flac, delivery: .localOriginal, channels: 1),
            backend: .persistent, playable: true, gapless: true, reason: .supportedLocalSource),
        Row(name: "48 kHz FLAC against the 44.1 kHz graph",
            source: track(codec: .flac, delivery: .localOriginal, sampleRate: 48_000),
            backend: .persistent, playable: true, gapless: true, reason: .supportedLocalSource),
        Row(name: "Unknown sample rate is informational, not gating",
            source: track(codec: .flac, delivery: .localOriginal, sampleRate: nil),
            backend: .persistent, playable: true, gapless: true, reason: .supportedLocalSource),
        Row(name: "Decoder explicitly available",
            source: track(codec: .flac, delivery: .localOriginal, decoder: true),
            backend: .persistent, playable: true, gapless: true, reason: .supportedLocalSource),

        // MARK: MP3 — playable either way, gapless only with a trusted trim

        Row(name: "MP3 local, trusted Xing/LAME trim",
            source: track(codec: .mp3, delivery: .localOriginal, metadata: .trusted),
            backend: .persistent, playable: true, gapless: true, reason: .supportedLocalSource),
        Row(name: "MP3 local, metadata absent",
            source: track(codec: .mp3, delivery: .localOriginal, metadata: .absent),
            backend: .persistent, playable: true, gapless: false,
            reason: .gaplessMetadataUnavailable),
        Row(name: "MP3 local, metadata malformed",
            source: track(codec: .mp3, delivery: .localOriginal, metadata: .malformed),
            backend: .persistent, playable: true, gapless: false,
            reason: .gaplessMetadataUntrusted),
        Row(name: "MP3 local, metadata present but untrusted",
            source: track(codec: .mp3, delivery: .localOriginal, metadata: .untrusted),
            backend: .persistent, playable: true, gapless: false,
            reason: .gaplessMetadataUntrusted),
        Row(name: "MP3 local, metadata not yet inspected",
            source: track(codec: .mp3, delivery: .localOriginal, metadata: .unknown),
            backend: .persistent, playable: true, gapless: false,
            reason: .gaplessMetadataUnavailable),
        Row(name: "MP3 confirmed transcode, trusted trim",
            source: track(codec: .flac,
                          delivery: .remoteTranscodeConfirmed(output: .mp3),
                          metadata: .trusted),
            backend: .persistent, playable: true, gapless: true,
            reason: .supportedConfirmedTranscode),
        Row(name: "MP3 confirmed transcode, no trim",
            source: track(codec: .flac,
                          delivery: .remoteTranscodeConfirmed(output: .mp3),
                          metadata: .absent),
            backend: .persistent, playable: true, gapless: false,
            reason: .gaplessMetadataUnavailable),
        Row(name: "Opus confirmed transcode from FLAC",
            source: track(codec: .flac,
                          delivery: .remoteTranscodeConfirmed(output: .opus),
                          sampleRate: 48_000),
            backend: .persistent, playable: true, gapless: true,
            reason: .supportedConfirmedTranscode),

        // MARK: Delivery uncertainty — always legacy

        Row(name: "Requested Opus transcode, unconfirmed",
            source: track(codec: .flac,
                          delivery: .remoteRequestedButUnconfirmed(requested: .opus)),
            backend: .legacy, playable: false, gapless: false, reason: .unconfirmedTranscode),
        Row(name: "Requested MP3 transcode, unconfirmed",
            source: track(codec: .flac,
                          delivery: .remoteRequestedButUnconfirmed(requested: .mp3),
                          metadata: .trusted),
            backend: .legacy, playable: false, gapless: false, reason: .unconfirmedTranscode),
        Row(name: "Requested nothing in particular, unconfirmed",
            source: track(codec: .flac,
                          delivery: .remoteRequestedButUnconfirmed(requested: nil)),
            backend: .legacy, playable: false, gapless: false, reason: .unconfirmedTranscode),
        Row(name: "Unknown remote delivery",
            source: track(codec: .flac, delivery: .unknown),
            backend: .legacy, playable: false, gapless: false, reason: .unknownDelivery),
        Row(name: "Original codec known, delivered codec unknown",
            source: track(codec: .unknown, delivery: .remoteDirectConfirmed),
            backend: .legacy, playable: false, gapless: false, reason: .unknownCodec),
        Row(name: "Confirmed transcode to an unknown output",
            source: track(codec: .flac, delivery: .remoteTranscodeConfirmed(output: .unknown)),
            backend: .legacy, playable: false, gapless: false, reason: .unknownCodec),

        // MARK: Unsupported inputs

        Row(name: "Radio",
            source: PlaybackRoutingSource(contentKind: .radio, delivery: .remoteDirectConfirmed,
                                          codec: .mp3, channelCount: 2, hasFiniteDuration: false,
                                          gaplessMetadata: .absent),
            backend: .legacy, playable: false, gapless: false, reason: .radioContent),
        Row(name: "Live stream",
            source: PlaybackRoutingSource(contentKind: .liveStream, delivery: .remoteDirectConfirmed,
                                          codec: .aac, channelCount: 2, hasFiniteDuration: false,
                                          gaplessMetadata: .notRequired),
            backend: .legacy, playable: false, gapless: false, reason: .liveStreamContent),
        Row(name: "Unknown content kind",
            source: PlaybackRoutingSource(contentKind: .unknown, delivery: .localOriginal,
                                          codec: .flac, channelCount: 2, hasFiniteDuration: true,
                                          gaplessMetadata: .notRequired),
            backend: .legacy, playable: false, gapless: false, reason: .unknownContentKind),
        Row(name: "Finite track that is not actually finite",
            source: track(codec: .flac, delivery: .localOriginal, finite: false),
            backend: .legacy, playable: false, gapless: false, reason: .indefiniteStream),
        Row(name: "Duration not yet established",
            source: track(codec: .flac, delivery: .localOriginal, finite: nil),
            backend: .legacy, playable: false, gapless: false,
            reason: .requiredMediaPropertiesUnknown),
        Row(name: "Unsupported codec",
            source: track(codec: .other("wma"), delivery: .localOriginal),
            backend: .legacy, playable: false, gapless: false, reason: .unsupportedCodec),
        Row(name: "Unknown codec on a local file",
            source: track(codec: .unknown, delivery: .localOriginal),
            backend: .legacy, playable: false, gapless: false, reason: .unknownCodec),
        Row(name: "5.1 FLAC — above stereo is refused",
            source: track(codec: .flac, delivery: .localOriginal, channels: 6),
            backend: .legacy, playable: false, gapless: false, reason: .unsupportedChannelLayout),
        Row(name: "3-channel source",
            source: track(codec: .flac, delivery: .localOriginal, channels: 3),
            backend: .legacy, playable: false, gapless: false, reason: .unsupportedChannelLayout),
        Row(name: "Channel count not yet discovered",
            source: track(codec: .flac, delivery: .localOriginal, channels: nil),
            backend: .legacy, playable: false, gapless: false,
            reason: .requiredMediaPropertiesUnknown),
        Row(name: "Nonsensical channel count",
            source: track(codec: .flac, delivery: .localOriginal, channels: 0),
            backend: .legacy, playable: false, gapless: false,
            reason: .requiredMediaPropertiesUnknown),
        Row(name: "Decoder known to be unavailable",
            source: track(codec: .flac, delivery: .localOriginal, decoder: false),
            backend: .legacy, playable: false, gapless: false, reason: .decoderUnavailable),
        Row(name: "Unsupported codec beats a trusted trim",
            source: track(codec: .other("ape"), delivery: .localOriginal, metadata: .trusted),
            backend: .legacy, playable: false, gapless: false, reason: .unsupportedCodec)
    ]

    // MARK: - The matrix

    @Test func theMatrixDecidesAsSpecified() {
        for row in Self.rows {
            let decision = PlaybackBackendPolicy.decision(for: row.source)
            #expect(decision.backend == row.backend,
                    "\(row.name): backend was \(decision.backend), expected \(row.backend)")
            #expect(decision.playableByPersistentEngine == row.playable,
                    "\(row.name): playable was \(decision.playableByPersistentEngine)")
            #expect(decision.gaplessCapable == row.gapless,
                    "\(row.name): gaplessCapable was \(decision.gaplessCapable)")
            #expect(decision.reason == row.reason,
                    "\(row.name): reason was \(decision.reason), expected \(row.reason)")
        }
    }

    // MARK: - Distinct-output guarantees

    /// Persistent eligibility does not imply gapless capability. If these ever collapse into one
    /// another, the engine either gets withheld from playable content or promises a seam it cannot
    /// deliver.
    @Test func persistentEligibilityDoesNotImplyGaplessCapability() {
        let playableButNotGapless = Self.rows.filter { $0.playable && !$0.gapless }
        #expect(playableButNotGapless.isEmpty == false,
                "the matrix no longer covers persistently playable but non-gapless sources")

        for row in playableButNotGapless {
            let decision = PlaybackBackendPolicy.decision(for: row.source)
            #expect(decision.backend == .persistent, "\(row.name) stopped being a persistent candidate")
            #expect(decision.gaplessCapable == false)
            #expect([.gaplessMetadataUnavailable, .gaplessMetadataUntrusted].contains(decision.reason),
                    "\(row.name): the reason must state the gapless situation, got \(decision.reason)")
        }
    }

    /// The structural invariant: `.persistent` and `playableByPersistentEngine` cannot disagree, in
    /// either direction, for any row.
    @Test func backendAndPlayabilityNeverDisagree() {
        for row in Self.rows {
            let decision = PlaybackBackendPolicy.decision(for: row.source)
            #expect(decision.backend == .persistent ? decision.playableByPersistentEngine : true,
                    "\(row.name): selected persistent while not playable by it")
            #expect(decision.playableByPersistentEngine ? decision.backend == .persistent : true,
                    "\(row.name): playable by persistent but routed to legacy")
        }
    }

    /// Legacy decisions never claim gapless capability.
    @Test func legacyDecisionsNeverClaimGapless() {
        for row in Self.rows where row.backend == .legacy {
            let decision = PlaybackBackendPolicy.decision(for: row.source)
            #expect(decision.gaplessCapable == false, "\(row.name) claimed gapless while legacy")
            #expect(decision.playableByPersistentEngine == false)
        }
    }

    /// Unconfirmed or unknown delivery is always legacy, whatever else is true about the source.
    @Test func unconfirmedDeliveryAlwaysSelectsLegacy() {
        let uncertain: [PlaybackDelivery] = [
            .unknown,
            .remoteRequestedButUnconfirmed(requested: nil),
            .remoteRequestedButUnconfirmed(requested: .opus),
            .remoteRequestedButUnconfirmed(requested: .mp3),
            .remoteRequestedButUnconfirmed(requested: .flac)
        ]
        for delivery in uncertain {
            for codec in [PlaybackCodec.flac, .alac, .aac, .opus, .mp3, .wav] {
                let decision = PlaybackBackendPolicy.decision(
                    for: Self.track(codec: codec, delivery: delivery, metadata: .trusted))
                #expect(decision.backend == .legacy,
                        "\(codec) via \(delivery) selected persistent on an unsettled representation")
                #expect(decision.playableByPersistentEngine == false)
                #expect(decision.isConfirmedRejection)
            }
        }
    }

    /// Radio and live content are legacy regardless of codec or delivery confidence.
    @Test func radioAndLiveContentAlwaysSelectLegacy() {
        for kind in [PlaybackContentKind.radio, .liveStream] {
            for codec in [PlaybackCodec.flac, .aac, .opus, .mp3] {
                let source = PlaybackRoutingSource(
                    contentKind: kind, delivery: .remoteDirectConfirmed, codec: codec,
                    channelCount: 2, sampleRate: 44_100, hasFiniteDuration: true,
                    gaplessMetadata: .notRequired, decoderAvailable: true)
                let decision = PlaybackBackendPolicy.decision(for: source)
                #expect(decision.backend == .legacy, "\(kind) with \(codec) selected persistent")
                #expect(decision.reason == (kind == .radio ? .radioContent : .liveStreamContent))
            }
        }
    }

    /// Above stereo is refused for every codec and delivery.
    @Test func aboveStereoIsRefusedEverywhere() {
        for codec in [PlaybackCodec.flac, .alac, .aac, .opus, .mp3, .wav] {
            for delivery in [PlaybackDelivery.localOriginal, .downloadedOriginal, .cachedPrepared,
                             .remoteDirectConfirmed] {
                for channels in [3, 6, 8] {
                    let decision = PlaybackBackendPolicy.decision(
                        for: Self.track(codec: codec, delivery: delivery,
                                        channels: channels, metadata: .trusted))
                    #expect(decision.backend == .legacy,
                            "\(codec)/\(delivery)/\(channels)ch selected persistent")
                    #expect(decision.reason == .unsupportedChannelLayout)
                }
            }
        }
    }

    /// Mono and stereo are both accepted, for every supported codec and confirmed delivery.
    @Test func monoAndStereoAreAcceptedAcrossTheConfirmedMatrix() {
        for codec in [PlaybackCodec.flac, .alac, .aac, .opus, .wav] {
            for delivery in [PlaybackDelivery.localOriginal, .downloadedOriginal, .cachedPrepared,
                             .remoteDirectConfirmed] {
                for channels in [1, 2] {
                    let decision = PlaybackBackendPolicy.decision(
                        for: Self.track(codec: codec, delivery: delivery, channels: channels))
                    #expect(decision.backend == .persistent,
                            "\(codec)/\(delivery)/\(channels)ch was refused")
                    #expect(decision.gaplessCapable, "\(codec) lost its frame-exact guarantee")
                }
            }
        }
    }

    // MARK: - Purity

    /// The same input always produces the same output, and evaluation order does not matter.
    @Test func thePolicyIsDeterministic() {
        for row in Self.rows {
            let first = PlaybackBackendPolicy.decision(for: row.source)
            for _ in 0..<25 {
                #expect(PlaybackBackendPolicy.decision(for: row.source) == first,
                        "\(row.name) is not deterministic")
            }
        }
        // Reversed order, same answers — no hidden accumulated state.
        for row in Self.rows.reversed() {
            let decision = PlaybackBackendPolicy.decision(for: row.source)
            #expect(decision.backend == row.backend, "\(row.name) changed with evaluation order")
        }
    }

    /// Every reason in the closed set is reachable, so none is dead and none is a catch-all that
    /// swallowed a case the matrix meant to distinguish.
    ///
    /// One reason lives outside the matrix by design: `sourceMaterializationTimedOut` is produced
    /// by the planner's deadline — a statement about *time*, which the pure policy function cannot
    /// see. Its reachability is pinned by
    /// `PlaybackSessionSelectionPlannerTests.aSourceThatCannotMaterializeInTimePlansLegacy`.
    @Test func everyDecisionReasonIsReachable() {
        var seen = Set<PlaybackBackendDecisionReason>()
        for row in Self.rows {
            seen.insert(PlaybackBackendPolicy.decision(for: row.source).reason)
        }
        let plannerProduced: Set<PlaybackBackendDecisionReason> = [.sourceMaterializationTimedOut]
        let unreachable = Set(PlaybackBackendDecisionReason.allCases)
            .subtracting(seen)
            .subtracting(plannerProduced)
        #expect(unreachable.isEmpty,
                "these reasons are never produced by the matrix: \(unreachable.map(\.rawValue).sorted())")
    }

    /// A confirmed transcode routes on what was delivered, not on what was stored. Routing on the
    /// stored format after the server re-encoded it would be routing on fiction.
    @Test func confirmedTranscodeRoutesOnTheDeliveredRepresentation() {
        // Stored as an unsupported codec, delivered as FLAC — the delivered form wins.
        let upgraded = Self.track(codec: .other("wma"),
                                  delivery: .remoteTranscodeConfirmed(output: .flac))
        #expect(PlaybackBackendPolicy.decision(for: upgraded).backend == .persistent,
                "a confirmed transcode did not override the stored codec")

        // Stored as FLAC, delivered as an unsupported codec — the delivered form wins here too.
        let downgraded = Self.track(codec: .flac,
                                    delivery: .remoteTranscodeConfirmed(output: .other("wma")))
        #expect(PlaybackBackendPolicy.decision(for: downgraded).backend == .legacy,
                "a confirmed transcode to an unsupported codec still selected persistent")
        #expect(PlaybackBackendPolicy.decision(for: downgraded).reason == .unsupportedCodec)
    }
}

private extension PlaybackBackendDecision {
    /// A legacy decision that names a delivery-certainty cause rather than a capability one.
    var isConfirmedRejection: Bool {
        reason == .unknownDelivery || reason == .unconfirmedTranscode
    }
}

/// Lane 3B wires the policy to nothing. These pin that the runtime has not started consulting it.
@Suite(.serialized)
@MainActor
struct ApplicationPlaybackRouterIsolationTests {

    /// The router still always selects legacy, and every seam still observes that.
    @Test func theRouterStillSelectsLegacyOnly() {
        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        #expect(router.selectedBackend == .legacy,
                "the router selected \(router.selectedBackend) — Lane 3B must not change routing")

        // Evaluating the policy for a source the persistent engine *would* accept must not move it.
        let persistentCandidate = PlaybackRoutingSource(
            contentKind: .finiteTrack, delivery: .localOriginal, codec: .flac,
            channelCount: 2, sampleRate: 44_100, hasFiniteDuration: true,
            gaplessMetadata: .notRequired, decoderAvailable: true)
        #expect(PlaybackBackendPolicy.decision(for: persistentCandidate).backend == .persistent,
                "the policy stopped recognising a persistent candidate")
        #expect(router.selectedBackend == .legacy,
                "evaluating the policy changed the router's decision")
    }

    /// Every application seam still resolves the same router and still observes legacy.
    @Test func everySeamStillObservesLegacy() {
        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        let seams: [(String, any ApplicationPlaybackControlling)] = [
            ("composition point", ApplicationPlayback.shared),
            ("CarPlayPlaybackActions", CarPlayPlaybackActions.playback),
            ("CarPlayScenePlaybackActions", CarPlayScenePlaybackActions.playback),
            ("WatchPlaybackActions", WatchPlaybackActions.playback),
            ("AppIntentPlaybackActions", AppIntentPlaybackActions.playback),
            ("AppCommandPlaybackActions", AppCommandPlaybackActions.playback),
            ("ScenePlaybackLifecycleActions", ScenePlaybackLifecycleActions.playback)
        ]
        for (name, resolved) in seams {
            #expect(resolved === router, "\(name) no longer resolves the router")
        }
        #expect(router.selectedBackend == .legacy)
    }

    /// Runtime diagnostics still report legacy and an unconstructed persistent controller.
    @Test func runtimeDiagnosticsStillReportLegacy() {
        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        let summary = router.diagnostics.summary
        #expect(summary.contains("Active transport backend: Legacy"))
        #expect(summary.contains("Persistent controller: Not constructed"))
        #expect(router.diagnostics.persistentControllerConstructed == false)
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "a persistent playback controller was constructed")
    }
}
