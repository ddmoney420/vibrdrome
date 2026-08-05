import AVFoundation
import Foundation

/// What a proposed finite-track session needs in order to be routed.
///
/// Deliberately a value: no `AudioEngine`, no router, no ownership coordinator. The planner decides,
/// it does not act, and giving it a handle on anything that *could* act is how "planning" quietly
/// becomes "starting".
struct PlaybackSessionSelectionRequest: Equatable, Sendable {
    /// The queue occurrences, positionally — duplicate song ids stay distinct.
    var songs: [Song]
    var startIndex: Int
    var startOffsetSeconds: TimeInterval
    var contentKind: PlaybackContentKind
    /// Monotonic identity so a newer request can invalidate an older in-flight plan.
    var generation: UInt64

    init(songs: [Song], startIndex: Int = 0, startOffsetSeconds: TimeInterval = 0,
         contentKind: PlaybackContentKind = .finiteTrack, generation: UInt64) {
        self.songs = songs
        self.startIndex = startIndex
        self.startOffsetSeconds = startOffsetSeconds
        self.contentKind = contentKind
        self.generation = generation
    }

    /// The occurrence the session would start on.
    var firstSong: Song? {
        songs.indices.contains(startIndex) ? songs[startIndex] : songs.first
    }
}

/// A materialized, inspected source, ready for a later lane to hand to the persistent engine.
///
/// Owning one of these means owning a **file on disk in the gapless cache**. It is deliberately
/// consumable exactly once: a plan that is executed hands the source on, and a plan that is dropped
/// releases it, so a source can never be adopted twice or leak between planning attempts.
@MainActor
final class PreparedPersistentSource {
    let track: GaplessPreparedTrack
    /// The container actually delivered, taken from the materialized file rather than the request.
    let deliveredContainer: String
    private(set) var isConsumed = false

    init(track: GaplessPreparedTrack, deliveredContainer: String) {
        self.track = track
        self.deliveredContainer = deliveredContainer
    }

    /// Hand the source to the next lane. Returns `nil` if it has already been taken.
    func consume() -> GaplessPreparedTrack? {
        guard !isConsumed else { return nil }
        isConsumed = true
        return track
    }

    /// Release the prepared source without consuming it.
    ///
    /// The cache file itself is owned by the gapless cache directory and reaped there — dropping a
    /// plan must not delete a file a *later* plan may legitimately reuse, so this releases the claim
    /// rather than the bytes. No descriptor is held: `describe` closes its `AVAudioFile` when it
    /// returns, so planning leaves nothing open.
    func release() { isConsumed = true }
}

/// The finalized routing plan. Nothing here starts audio.
enum PlaybackSessionSelectionPlan {
    case legacy(reason: PlaybackBackendDecisionReason)
    case persistent(preparedSource: PreparedPersistentSource, decision: PlaybackBackendDecision)
    case failed(reason: SafePlaybackRoutingFailure)

    var plannedBackend: PlaybackBackend {
        switch self {
        case .persistent: .persistent
        case .legacy, .failed: .legacy
        }
    }

    var decision: PlaybackBackendDecision? {
        if case .persistent(_, let decision) = self { return decision }
        return nil
    }

    var retainsPreparedSource: Bool {
        if case .persistent = self { return true }
        return false
    }

    /// A safe, closed description — never a URL, credential, header or path.
    var describedForDiagnostics: String {
        switch self {
        case .legacy(let reason): "Legacy (\(reason.rawValue))"
        case .persistent(_, let decision): "Persistent (\(decision.reason.rawValue))"
        case .failed(let reason): "Failed (\(reason.rawValue))"
        }
    }
}

/// Turns a proposed session into one finalized routing plan, based on the representation actually
/// delivered rather than the one requested.
///
/// **Decides, never acts.** It does not touch the router's active backend, the ownership
/// coordinator, the audio session, the player node or the legacy queue. A `.persistent` plan is a
/// recommendation carrying a prepared source; something else executes it in a later lane.
@MainActor
struct PlaybackSessionSelectionPlanner {

    /// Prepares the persistent assembly on demand. Injected so a test can fail construction without
    /// a device-only substitute.
    let prepareAssembly: () throws -> PersistentPlaybackAssembly

    /// Whether persistent routing is permitted at all. Defaults to the DEBUG setting.
    let isPersistentRoutingEnabled: () -> Bool

    init(
        prepareAssembly: @escaping () throws -> PersistentPlaybackAssembly,
        isPersistentRoutingEnabled: @escaping () -> Bool = { PersistentRoutingSetting.isEnabled }
    ) {
        self.prepareAssembly = prepareAssembly
        self.isPersistentRoutingEnabled = isPersistentRoutingEnabled
    }

    func plan(request: PlaybackSessionSelectionRequest) async -> PlaybackSessionSelectionPlan {
        // 1. Flag Off short-circuits before anything is constructed, fetched or opened.
        guard isPersistentRoutingEnabled() else {
            return .legacy(reason: .supportedLocalSource)
        }

        // 2. Reject what the Lane 3B policy can already refuse from known facts, so a definitively
        //    legacy source is never materialized.
        switch request.contentKind {
        case .radio: return .legacy(reason: .radioContent)
        case .liveStream: return .legacy(reason: .liveStreamContent)
        case .unknown: return .legacy(reason: .unknownContentKind)
        case .finiteTrack: break
        }
        guard let song = request.firstSong else {
            return .legacy(reason: .requiredMediaPropertiesUnknown)
        }

        // 3. Construct the persistent stack only now that a persistent outcome is possible.
        let assembly: PersistentPlaybackAssembly
        do {
            assembly = try prepareAssembly()
        } catch {
            return .failed(reason: .persistentConstructionFailed)
        }
        guard !Task.isCancelled else { return .failed(reason: .sourcePreparationFailed) }

        // 4. Materialize the first source completely. The provider returns only once the bytes are
        //    fully written — a partial file decodes short and would corrupt boundary accounting —
        //    and names the file from the response's content type, which is what makes the delivered
        //    container knowable at all.
        let fileURL: URL
        do {
            fileURL = try await assembly.preparer.materializeSource(forTrack: song.id)
        } catch {
            return .failed(reason: .sourcePreparationFailed)
        }
        guard !Task.isCancelled else { return .failed(reason: .sourcePreparationFailed) }

        let deliveredContainer = fileURL.pathExtension.lowercased()

        // 5. Open and inspect the real media. `describe` opens an `AVAudioFile`, reads the
        //    processing format, applies the trim policy and computes the render frame count — so
        //    sample rate, channel count, finite length and MP3 trim status all come from the file
        //    rather than from metadata or a request parameter. It closes the file when it returns.
        let track: GaplessPreparedTrack
        do {
            track = try GaplessTrackPreparer.describe(
                trackID: song.id, fileURL: fileURL,
                renderSampleRate: GaplessRenderFormat.sampleRate
            )
        } catch {
            // Unreadable, empty audio, or any other decoder refusal.
            return .legacy(reason: .decoderUnavailable)
        }

        // 6. Build the final routing facts from what was confirmed, never from what was requested.
        let source = PlaybackRoutingSource(
            contentKind: .finiteTrack,
            delivery: .cachedPrepared,
            codec: Self.codec(forContainer: deliveredContainer),
            channelCount: Int(track.sourceChannelCount),
            sampleRate: track.sourceSampleRate,
            hasFiniteDuration: track.renderFrames > 0,
            gaplessMetadata: Self.metadata(for: track.trim.reason),
            decoderAvailable: true
        )

        let decision = PlaybackBackendPolicy.decision(for: source)
        guard !Task.isCancelled else { return .failed(reason: .sourcePreparationFailed) }

        guard decision.backend == .persistent else {
            // Nothing is retained: a legacy decision holds no prepared source.
            return .legacy(reason: decision.reason)
        }
        return .persistent(
            preparedSource: PreparedPersistentSource(
                track: track, deliveredContainer: deliveredContainer
            ),
            decision: decision
        )
    }

    /// The delivered container, mapped to a codec the policy understands. Taken from the
    /// materialized file's extension, which the fetch derives from the response's content type —
    /// a transcoding server returns a different type than the stored file, so this is the only
    /// honest source.
    static func codec(forContainer container: String) -> PlaybackCodec {
        switch container {
        case "flac": .flac
        case "m4a", "alac": .alac
        case "aac", "mp4": .aac
        case "opus", "ogg": .opus
        case "mp3": .mp3
        case "wav", "wave": .wav
        case "": .unknown
        default: .other(container)
        }
    }

    /// Gapless capability comes from the trim policy's actual verdict on this file.
    static func metadata(for reason: GaplessTrim.Reason) -> PlaybackGaplessMetadata {
        switch reason {
        case .wholeFile: .notRequired
        case .lameGaplessHeader: .trusted
        case .mp3WithoutGaplessMetadata: .absent
        }
    }
}
