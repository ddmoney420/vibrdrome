import AVFoundation
import Foundation

/// Identity and frame accounting for one scheduled PCM chunk.
///
/// Every field the boundary logic, the tail logic and the diagnostics need is here, so nothing has
/// to be recovered by looking back at a track, a queue or an open file. That is what allows the
/// completion callback to carry only a token: the chunk record on the main actor holds the meaning.
struct GaplessChunkDescriptor: Sendable, Equatable {
    let itemID: GaplessQueueItemID
    let playInstance: GaplessPlayInstanceID
    let tailGeneration: UInt64
    let songID: String

    /// Frame of the *source file* this chunk starts at, already inside the trimmed range.
    let sourceStartFrame: AVAudioFramePosition
    /// Source frames consumed for this chunk. Differs from `timelineFrameCount` whenever a
    /// converter is in the path.
    let sourceFrameCount: AVAudioFrameCount
    /// Frame on the engine's render timeline this chunk starts at.
    let timelineStartFrame: AVAudioFramePosition
    /// Output frames **actually produced** and scheduled. Never an estimate.
    let timelineFrameCount: AVAudioFrameCount

    let chunkIndex: Int
    let isFirstChunk: Bool
    let isFinalChunk: Bool
    /// Whether a converter produced this chunk, for diagnostics that need to separate the two paths.
    let wasConverted: Bool

    var timelineEndFrame: AVAudioFramePosition {
        timelineStartFrame + AVAudioFramePosition(timelineFrameCount)
    }
}

enum GaplessChunkSourceError: Error, LocalizedError {
    case readFailed(trackID: String, underlying: Error)
    case seekFailed(trackID: String)
    /// The source's decoded format cannot be played under the current channel policy.
    case unsupportedFormat(trackID: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .readFailed(let id, let error):
            return "Track \(id) could not be read: \(error.localizedDescription)"
        case .seekFailed(let id):
            return "Track \(id) could not seek to its trimmed start"
        case .unsupportedFormat(let id, let reason):
            return "Track \(id) cannot be played: \(reason)"
        }
    }
}

/// Reads one track's trimmed audio **in its own source format**, then lets go of the file.
///
/// Deliberately knows nothing about the render format or about conversion. Conversion is a separate,
/// independently fallible stage owned by the scheduler, because a converter may legitimately outlive
/// a single track — which is a policy question this type must not silently decide.
///
/// The file is opened here, read here, and closed here; it is never handed to the player node. In
/// the tested persistent `AVAudioPlayerNode` configuration, `scheduleSegment` retains each supplied
/// `AVAudioFile` and file descriptor until the node is stopped, so a long session grows without
/// bound in both. A chunk source holds its file only while there is still audio to read from it.
///
/// Trim is applied before any audio is produced, so encoder delay and end padding are never decoded
/// as music.
final class GaplessPCMChunkSource {
    /// Live `AVAudioFile` objects held by chunk sources anywhere in the process.
    ///
    /// The whole substrate exists because file lifetime was not observable from the outside, so it
    /// is made observable from the inside. Incremented when a source opens a file and decremented
    /// the moment it lets go, this is a direct count rather than a descriptor-count inference.
    private static let liveFileLock = NSLock()
    nonisolated(unsafe) private static var liveFileStorage = 0

    static var liveFileCount: Int {
        liveFileLock.lock(); defer { liveFileLock.unlock() }
        return liveFileStorage
    }

    private static func adjustLiveFiles(_ delta: Int) {
        liveFileLock.lock()
        liveFileStorage += delta
        liveFileLock.unlock()
    }

    let track: GaplessPreparedTrack
    let itemID: GaplessQueueItemID
    let playInstance: GaplessPlayInstanceID
    let generation: UInt64
    /// The format this source's audio actually decodes to.
    let processingFormat: AVAudioFormat

    private var file: AVAudioFile?
    /// Frames of the trimmed range already read.
    private(set) var framesRead: AVAudioFrameCount = 0
    private(set) var isClosed = false
    /// Set when a read returned fewer frames than the trim range promised — a truncated or
    /// mis-declared file. Recorded rather than ignored, because the timeline must be built from what
    /// the file actually contained.
    private(set) var endedEarly = false

    var isSourceExhausted: Bool { framesRead >= track.trim.frameCount || isClosed }
    var framesRemaining: AVAudioFrameCount {
        track.trim.frameCount - min(framesRead, track.trim.frameCount)
    }
    /// Whether this source is still holding an open file (and therefore a descriptor).
    var holdsOpenFile: Bool { file != nil }

    /// Opens the file and seeks to the trimmed start. `startFrameOffset` lets a seek begin partway
    /// into the track without changing the trim policy.
    init(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
         playInstance: GaplessPlayInstanceID, generation: UInt64,
         startFrameOffset: AVAudioFrameCount = 0) throws {
        self.track = track
        self.itemID = itemID
        self.playInstance = playInstance
        self.generation = generation

        let opened: AVAudioFile
        do {
            opened = try AVAudioFile(forReading: track.fileURL)
        } catch {
            throw GaplessChunkSourceError.readFailed(trackID: track.trackID, underlying: error)
        }
        processingFormat = opened.processingFormat
        guard GaplessChannelPolicy.supports(sourceChannels: processingFormat.channelCount) else {
            throw GaplessChunkSourceError.unsupportedFormat(
                trackID: track.trackID,
                reason: "\(processingFormat.channelCount) channels exceeds the stereo policy")
        }
        framesRead = min(startFrameOffset, track.trim.frameCount)
        opened.framePosition = track.trim.startFrame + AVAudioFramePosition(framesRead)
        guard opened.framePosition == track.trim.startFrame + AVAudioFramePosition(framesRead) else {
            throw GaplessChunkSourceError.seekFailed(trackID: track.trackID)
        }
        file = opened
        Self.adjustLiveFiles(1)
    }

    /// Read source-format PCM into `buffer`. Returns frames written, or 0 when the trimmed range is
    /// finished — at which point the file is already closed.
    ///
    /// Never reads past the trimmed range, so end padding cannot leak into the last chunk and become
    /// audible at a boundary.
    @discardableResult
    func readSource(into buffer: AVAudioPCMBuffer,
                    maxFrames: AVAudioFrameCount? = nil) throws -> AVAudioFrameCount {
        guard !isSourceExhausted, let file else {
            close()
            return 0
        }
        let limit = min(maxFrames ?? buffer.frameCapacity, buffer.frameCapacity)
        let wanted = min(limit, framesRemaining)
        guard wanted > 0 else {
            close()
            return 0
        }
        do {
            try file.read(into: buffer, frameCount: wanted)
        } catch {
            close()
            throw GaplessChunkSourceError.readFailed(trackID: track.trackID, underlying: error)
        }
        let produced = buffer.frameLength
        framesRead += produced
        // A short read means the decoder has no more audio, whatever the container claimed. Closing
        // now keeps the descriptor bound tight rather than waiting for an exhaustion check that a
        // truncated file would never satisfy.
        if produced < wanted {
            endedEarly = true
            close()
        } else if isSourceExhausted {
            close()
        }
        return produced
    }

    /// Release the file and its descriptor. Idempotent, and safe to call while chunks are still
    /// scheduled — the player node holds the PCM, not the file.
    func close() {
        if file != nil { Self.adjustLiveFiles(-1) }
        file = nil
        isClosed = true
    }

    deinit {
        if file != nil { Self.adjustLiveFiles(-1) }
        file = nil
    }
}
