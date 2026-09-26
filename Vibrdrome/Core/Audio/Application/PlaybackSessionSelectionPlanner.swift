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

    /// How long Play may wait for the first source to become local before falling back to legacy.
    ///
    /// The persistent engine plays whole local files, so a fresh, uncached track must download
    /// completely before a persistent session can start. Bounded because that download can be
    /// enormous — a 680 MB continuous-mix FLAC turned Play into minutes of dead silence on device
    /// (2026-09-04). Cached, downloaded and small sources finish well inside the deadline and are
    /// unaffected; anything slower streams on legacy this session (instant start, not gapless) and
    /// plans persistent again once cached.
    let materializationDeadline: TimeInterval

    init(
        prepareAssembly: @escaping () throws -> PersistentPlaybackAssembly,
        isPersistentRoutingEnabled: @escaping () -> Bool = { PersistentRoutingSetting.isEnabled },
        materializationDeadline: TimeInterval = 4.0
    ) {
        self.prepareAssembly = prepareAssembly
        self.isPersistentRoutingEnabled = isPersistentRoutingEnabled
        self.materializationDeadline = materializationDeadline
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

        // 4. Materialize the first source completely — under a deadline. The provider returns only
        //    once the bytes are fully written (a partial file decodes short and would corrupt
        //    boundary accounting), and a fresh uncached track means a whole-file download that can
        //    be enormous. Play must never hang on it: past the deadline the fetch is cancelled and
        //    this session streams on legacy instead.
        let fileURL: URL
        do {
            guard let materialized = try await Self.withDeadline(
                seconds: materializationDeadline,
                work: { try await assembly.preparer.materializeSource(forTrack: song.id) })
            else {
                return .legacy(reason: .sourceMaterializationTimedOut)
            }
            fileURL = materialized
        } catch {
            return .failed(reason: .sourcePreparationFailed)
        }
        guard !Task.isCancelled else { return .failed(reason: .sourcePreparationFailed) }
        return Self.decide(fileURL: fileURL, songID: song.id)
    }

    /// Steps 5–6: inspect the real media and build the routing decision from what was confirmed.
    ///
    /// `describe` opens an `AVAudioFile`, reads the processing format, applies the trim policy and
    /// computes the render frame count — so sample rate, channel count, finite length and MP3 trim
    /// status all come from the file rather than from metadata or a request parameter.
    private static func decide(fileURL: URL, songID: String) -> PlaybackSessionSelectionPlan {
        let deliveredContainer = fileURL.pathExtension.lowercased()
        let track: GaplessPreparedTrack
        do {
            track = try GaplessTrackPreparer.describe(
                trackID: songID, fileURL: fileURL,
                renderSampleRate: GaplessRenderFormat.sampleRate
            )
        } catch {
            // Unreadable, empty audio, or any other decoder refusal.
            return .legacy(reason: .decoderUnavailable)
        }

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

    /// Race `work` against a deadline. Returns nil on timeout, with the work task cancelled —
    /// `URLSession`'s async download honours that cooperatively, cleaning up its temporary file.
    private static func withDeadline<T: Sendable>(
        seconds: TimeInterval, work: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            // First finisher decides; the loser is cancelled either way.
            let first = try await group.next().flatMap { $0 }
            group.cancelAll()
            return first
        }
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
