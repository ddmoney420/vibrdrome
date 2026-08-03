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
    let sourceFrameCount: AVAudioFrameCount
    /// Frame on the engine's render timeline this chunk starts at.
    let timelineStartFrame: AVAudioFramePosition
    /// Frames contributed to the render timeline. Equal to `sourceFrameCount` while no sample-rate
    /// conversion is in the path; kept separate so it stays correct once one is.
    let timelineFrameCount: AVAudioFrameCount

    let chunkIndex: Int
    let isFirstChunk: Bool
    let isFinalChunk: Bool

    var timelineEndFrame: AVAudioFramePosition {
        timelineStartFrame + AVAudioFramePosition(timelineFrameCount)
    }
}

enum GaplessChunkSourceError: Error, LocalizedError {
    /// The decoded format does not match the render graph. Explicit rather than silently coerced:
    /// this is exactly the case an explicit converter has to own.
    case formatMismatch(trackID: String, sourceRate: Double, sourceChannels: AVAudioChannelCount)
    case readFailed(trackID: String, underlying: Error)
    case seekFailed(trackID: String)

    var errorDescription: String? {
        switch self {
        case .formatMismatch(let id, let rate, let channels):
            return "Track \(id) decodes to \(rate) Hz / \(channels)ch, which the render graph cannot take directly"
        case .readFailed(let id, let error):
            return "Track \(id) could not be read: \(error.localizedDescription)"
        case .seekFailed(let id):
            return "Track \(id) could not seek to its trimmed start"
        }
    }
}

/// Streams one track's trimmed audio as bounded PCM chunks, then lets go of the file.
///
/// The file is opened here, read here, and closed here — it is never handed to the player node.
/// That is the whole point: in the tested persistent `AVAudioPlayerNode` configuration,
/// `scheduleSegment` retains each supplied `AVAudioFile` and its descriptor until the node is
/// stopped, so a long session grows without bound in both. A chunk source holds its file only while
/// there is still audio to read from it, which bounds open files by the preparation window rather
/// than by the number of tracks played.
///
/// Trim is applied before any chunk is produced, so encoder delay and end padding are never decoded
/// as music and never reach the graph.
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

    private var file: AVAudioFile?
    /// Frames of the trimmed range already read.
    private(set) var framesRead: AVAudioFrameCount = 0
    private(set) var chunksProduced = 0
    private(set) var isClosed = false

    /// True once every trimmed frame has been read and the file has been released.
    var isExhausted: Bool { framesRead >= track.trim.frameCount }
    var framesRemaining: AVAudioFrameCount { track.trim.frameCount - min(framesRead, track.trim.frameCount) }
    /// Whether this source is still holding an open file (and therefore a descriptor).
    var holdsOpenFile: Bool { file != nil }

    /// Opens the file and seeks to the trimmed start. `startFrameOffset` lets a seek begin partway
    /// into the track without changing the trim policy.
    init(track: GaplessPreparedTrack, itemID: GaplessQueueItemID,
         playInstance: GaplessPlayInstanceID, generation: UInt64,
         renderFormat: AVAudioFormat, startFrameOffset: AVAudioFrameCount = 0) throws {
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
        let format = opened.processingFormat
        // `read(into:)` fills at the file's processing format. Anything else has to be converted,
        // and that conversion is a separate, independently fallible stage — not something to paper
        // over here by handing the graph a buffer it cannot mix.
        guard format.sampleRate == renderFormat.sampleRate,
              format.channelCount == renderFormat.channelCount else {
            throw GaplessChunkSourceError.formatMismatch(trackID: track.trackID,
                                                         sourceRate: format.sampleRate,
                                                         sourceChannels: format.channelCount)
        }
        framesRead = min(startFrameOffset, track.trim.frameCount)
        opened.framePosition = track.trim.startFrame + AVAudioFramePosition(framesRead)
        guard opened.framePosition == track.trim.startFrame + AVAudioFramePosition(framesRead) else {
            throw GaplessChunkSourceError.seekFailed(trackID: track.trackID)
        }
        file = opened
        Self.adjustLiveFiles(1)
    }

    /// Read the next chunk into a pooled buffer. Returns the frames written, or 0 when the trimmed
    /// range is finished — at which point the file is already closed.
    ///
    /// Never reads past the trimmed range, so end padding cannot leak into the last chunk of a
    /// track and become audible at a boundary.
    @discardableResult
    func readChunk(into buffer: AVAudioPCMBuffer, maxFrames: AVAudioFrameCount) throws -> AVAudioFrameCount {
        guard !isExhausted, let file else {
            close()
            return 0
        }
        let wanted = min(maxFrames, min(buffer.frameCapacity, framesRemaining))
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
        chunksProduced += 1
        // A short read means the decoder has no more audio, whatever the container claimed. Closing
        // now keeps the descriptor bound tight rather than waiting for an exhaustion check that a
        // truncated file would never satisfy.
        if produced < wanted || isExhausted { close() }
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
