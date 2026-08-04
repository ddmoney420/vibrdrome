import AVFoundation
import Foundation
import os.log

/// A track that is fully ready to be scheduled into the persistent gapless graph: its bytes are on
/// local disk, it has been opened and decoded far enough to know its exact length, and the frame
/// range to schedule is resolved.
///
/// Deliberately a `Sendable` value type carrying a *URL* rather than an open `AVAudioFile`. Opening
/// a file is a cheap header parse; the expensive, failure-prone part is getting the bytes local, and
/// that is what preparation guarantees. The engine opens the file at schedule time, which keeps this
/// type sendable across the actor boundary without wrapping a non-Sendable decoder handle.
struct GaplessPreparedTrack: Equatable, Sendable {
    let trackID: String
    /// Always a local file — never a remote URL. The engine must never fetch at a boundary.
    let fileURL: URL
    /// Frame range of the decoded file to schedule (see `GaplessTrimPolicy`).
    let trim: GaplessTrim
    let sourceSampleRate: Double
    let sourceChannelCount: AVAudioChannelCount
    /// Frames this track contributes to the engine's render timeline. Equals `trim.frameCount` when
    /// the source already runs at the render rate; otherwise it is the sample-rate-converted count,
    /// so boundary accounting stays exact for 48 kHz sources in a 44.1 kHz graph.
    let renderFrames: AVAudioFramePosition
    /// How far into the track's own audio this scheduling begins.
    ///
    /// A seek re-schedules the current track with its trim advanced to the seek point, which loses
    /// the original position — the segment would start at frame 0 of a shortened track. Elapsed time
    /// is derived from this, so without it Now Playing reports time-since-seek instead of
    /// position-in-track.
    var sourceStartOffsetFrames: AVAudioFramePosition = 0

    /// True when the source needs no sample-rate conversion to join the render timeline.
    var matchesRenderRate: Bool { renderFrames == AVAudioFramePosition(trim.frameCount) }
}

enum GaplessPreparationError: Error, LocalizedError {
    case noLocalFile(trackID: String)
    case unreadable(trackID: String, underlying: Error)
    case emptyAudio(trackID: String)

    var errorDescription: String? {
        switch self {
        case .noLocalFile(let id): return "No local file could be produced for track \(id)"
        case .unreadable(let id, let error): return "Track \(id) could not be decoded: \(error.localizedDescription)"
        case .emptyAudio(let id): return "Track \(id) decoded to zero frames"
        }
    }
}

/// Supplies a **local file** for a track, fetching it if necessary. Split out as a protocol so the
/// decode/schedule pipeline can be proven offline against real audio files with no server involved.
protocol GaplessFileProviding: Sendable {
    /// Local file URL for the track. Must not return a remote URL, and must only return once the
    /// bytes are completely written — a partially-downloaded file decodes to the wrong length,
    /// which would silently corrupt boundary accounting.
    func localFile(forTrack trackID: String) async throws -> URL
}

/// Prepares tracks ahead of playback and holds the rolling window of ready ones.
///
/// The pipeline per track is: resolve to a local file (already downloaded, else fetch to cache) ->
/// open it -> read the true decoded length -> resolve the schedulable frame range -> record the
/// render-timeline frame count. All of it happens ahead of the boundary; none of it at the boundary.
actor GaplessTrackPreparer {
    private let provider: GaplessFileProviding
    private let renderSampleRate: Double
    private let window: GaplessPrefetchWindow
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessPrefetch")

    private var prepared: [String: GaplessPreparedTrack] = [:]
    private var inFlight: [String: Task<GaplessPreparedTrack, Error>] = [:]

    init(provider: GaplessFileProviding,
         renderSampleRate: Double = GaplessRenderFormat.sampleRate,
         window: GaplessPrefetchWindow = GaplessPrefetchWindow()) {
        self.provider = provider
        self.renderSampleRate = renderSampleRate
        self.window = window
    }

    // MARK: - Window driving

    /// Bring the rolling window in line with the queue: start preparing anything missing, release
    /// anything that has fallen outside it. Returns once the boundary-critical tracks (current +
    /// next) are ready, so the caller can act on a genuine readiness signal rather than a guess.
    @discardableResult
    func advanceWindow(queue: [String], currentIndex: Int) async -> Bool {
        for trackID in window.trackIDsToRelease(queue: queue, currentIndex: currentIndex,
                                                prepared: Set(prepared.keys)) {
            prepared.removeValue(forKey: trackID)
        }
        let toPrepare = window.trackIDsToPrepare(queue: queue, currentIndex: currentIndex,
                                                 prepared: Set(prepared.keys),
                                                 inFlight: Set(inFlight.keys))
        for trackID in toPrepare { startPreparing(trackID) }

        // Only await the boundary-critical slots. The trailing slot is allowed to still be fetching
        // — that is the whole point of the third window position.
        for trackID in window.mustBeReadyTrackIDs(queue: queue, currentIndex: currentIndex) {
            _ = try? await preparedTrack(trackID)
        }
        let safe = window.isBoundarySafe(queue: queue, currentIndex: currentIndex,
                                         prepared: Set(prepared.keys))
        if !safe {
            // Surfaced, not swallowed: the next transition will not be gapless.
            log.warning("gapless window not boundary-safe at index \(currentIndex, privacy: .public)")
        }
        return safe
    }

    /// The prepared track, awaiting an in-flight preparation if one is running and starting one if
    /// nothing is under way.
    ///
    /// Recording the result here — rather than from a separate observer task — is what makes
    /// readiness truthful: the track is registered as ready before this returns, so a caller that
    /// awaits it and then asks whether the boundary is safe cannot race its own bookkeeping.
    func preparedTrack(_ trackID: String) async throws -> GaplessPreparedTrack {
        if let ready = prepared[trackID] { return ready }
        let task = inFlight[trackID] ?? startPreparing(trackID)
        do {
            let track = try await task.value
            prepared[trackID] = track
            inFlight[trackID] = nil
            log.debug("""
                prepared \(trackID, privacy: .public): \(track.trim.frameCount) frames \
                (\(track.trim.reason.rawValue, privacy: .public)), \
                \(track.renderFrames) render frames
                """)
            return track
        } catch {
            inFlight[trackID] = nil
            if !(error is CancellationError) {
                log.error("""
                    gapless preparation failed for \(trackID, privacy: .public): \
                    \(error.localizedDescription, privacy: .public)
                    """)
            }
            throw error
        }
    }

    /// Already-prepared track, without triggering or awaiting any work.
    func readyTrack(_ trackID: String) -> GaplessPreparedTrack? { prepared[trackID] }

    var readyTrackIDs: Set<String> { Set(prepared.keys) }

    /// Drop everything — queue replaced, playback stopped, or engine torn down.
    func reset() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        prepared.removeAll()
    }

    // MARK: - Preparation

    /// Kick off preparation without waiting for it — this is what fills the trailing "preparing"
    /// window slot. The task caches its own result, so the later `preparedTrack` call that registers
    /// it does no duplicate fetching or decoding.
    @discardableResult
    private func startPreparing(_ trackID: String) -> Task<GaplessPreparedTrack, Error> {
        if let existing = inFlight[trackID] { return existing }
        let task = Task<GaplessPreparedTrack, Error> { [provider, renderSampleRate] in
            let url = try await provider.localFile(forTrack: trackID)
            return try Self.describe(trackID: trackID, fileURL: url, renderSampleRate: renderSampleRate)
        }
        inFlight[trackID] = task
        return task
    }

    /// Open the local file, resolve its schedulable range, and convert its length onto the render
    /// timeline. `nonisolated` and static so it can run off the actor and be tested directly.
    nonisolated static func describe(trackID: String, fileURL: URL,
                                     renderSampleRate: Double) throws -> GaplessPreparedTrack {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: fileURL)
        } catch {
            throw GaplessPreparationError.unreadable(trackID: trackID, underlying: error)
        }
        let format = file.processingFormat
        let trim = GaplessTrimPolicy.trim(forFileAt: fileURL, decodedLength: file.length)
        guard trim.frameCount > 0 else { throw GaplessPreparationError.emptyAudio(trackID: trackID) }

        // Sample-rate conversion changes the frame count; record the converted count so the
        // boundary lands on the right render frame.
        let renderFrames: AVAudioFramePosition
        if format.sampleRate == renderSampleRate {
            renderFrames = AVAudioFramePosition(trim.frameCount)
        } else {
            let ratio = renderSampleRate / format.sampleRate
            renderFrames = AVAudioFramePosition((Double(trim.frameCount) * ratio).rounded())
        }
        return GaplessPreparedTrack(trackID: trackID, fileURL: fileURL, trim: trim,
                                    sourceSampleRate: format.sampleRate,
                                    sourceChannelCount: format.channelCount,
                                    renderFrames: renderFrames)
    }
}
