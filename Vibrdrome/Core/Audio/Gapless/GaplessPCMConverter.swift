import AVFoundation
import Foundation
import os.log

/// Why a conversion could not be performed. Kept separate from `GaplessChunkSourceError` so a
/// conversion failure is never reported as a decode failure — they have different causes, different
/// recovery, and different capability meaning for the queue.
enum GaplessConversionError: Error, LocalizedError, Equatable {
    /// `AVAudioConverter` refused the format pair outright.
    case converterUnavailable(source: String, destination: String)
    /// More than two source channels. Deliberately **not** silently downmixed — see
    /// `GaplessChannelPolicy`.
    case unsupportedChannelCount(AVAudioChannelCount)
    /// The source declares a channel layout the policy does not cover.
    case unsupportedChannelLayout(String)
    case conversionFailed(String)
    /// The tail this conversion belonged to was superseded while it was running.
    case cancelled

    var errorDescription: String? {
        switch self {
        case .converterUnavailable(let source, let destination):
            return "No converter from \(source) to \(destination)"
        case .unsupportedChannelCount(let channels):
            return "\(channels)-channel sources are not supported by the current channel policy"
        case .unsupportedChannelLayout(let layout):
            return "Unsupported channel layout: \(layout)"
        case .conversionFailed(let reason): return "Conversion failed: \(reason)"
        case .cancelled: return "Conversion cancelled"
        }
    }
}

/// What the engine does with a source's channel count.
///
/// Stated as policy rather than left to `AVAudioConverter`'s defaults, because "what happens to a
/// 5.1 source" is a product decision, not an implementation detail. Silently dropping channels
/// would lose audio the user paid for without ever saying so.
enum GaplessChannelPolicy {
    /// Mono up-mixes to stereo. This does **not** change the frame count, so gapless accounting is
    /// unaffected: the same sample is written to both channels.
    /// Stereo passes through. Anything above stereo is refused with an explicit capability result,
    /// pending a product decision on downmix.
    static func validate(sourceChannels: AVAudioChannelCount) throws {
        switch sourceChannels {
        case 1, 2: return
        default: throw GaplessConversionError.unsupportedChannelCount(sourceChannels)
        }
    }

    /// Whether a source can be played at all under this policy.
    static func supports(sourceChannels: AVAudioChannelCount) -> Bool {
        sourceChannels == 1 || sourceChannels == 2
    }
}

#if DEBUG
/// Where a test may force a conversion to fail. DEBUG only — there is no production path that sets
/// it, and the checks compile out of release builds entirely.
enum GaplessConversionFailurePoint: Equatable, Sendable {
    /// Refuse to build the converter at all.
    case creation
    /// Fail before a single output frame has been produced.
    case beforeFirstOutput
    /// Fail after this many successful chunks.
    case afterChunks(Int)
    /// Fail during the final flush.
    case flush
}
#endif

/// Converts decoded source PCM into the persistent graph format, in bounded pieces.
///
/// **Why this exists as its own stage.** Before the buffer substrate, `AVAudioPlayerNode` converted
/// source rates during rendering, so there was no conversion boundary to get wrong. Scheduling PCM
/// buffers moves that responsibility here, where it becomes independently fallible — a converter can
/// refuse a format pair, fail partway, or produce a different number of frames than arithmetic
/// predicts. All three are now representable instead of hidden.
///
/// **Frames are counted, never computed.** `input × 44100 / 48000` is an estimate for planning only.
/// A resampler primes, and flushes a tail, so the authoritative output length is what `convert`
/// actually produced — which is what this reports and what the timeline is built from.
///
/// Never runs on the render thread: conversion happens in the scheduler's pump, ahead of playback.
final class GaplessPCMConverter {
    /// Live converters anywhere in the process, so "bounded by the preparation window" is a
    /// measurement rather than a claim.
    private static let liveLock = NSLock()
    nonisolated(unsafe) private static var liveStorage = 0
    nonisolated(unsafe) private static var createdStorage = 0

    static var liveCount: Int {
        liveLock.lock(); defer { liveLock.unlock() }
        return liveStorage
    }

    /// Total converters ever built — the reset/rebuild count for the lifecycle comparison.
    static var createdCount: Int {
        liveLock.lock(); defer { liveLock.unlock() }
        return createdStorage
    }

    static func resetCreatedCount() {
        liveLock.lock(); createdStorage = 0; liveLock.unlock()
    }

    #if DEBUG
    private static let injectionLock = NSLock()
    nonisolated(unsafe) private static var injectedStorage: GaplessConversionFailurePoint?

    /// Set by tests to force a failure at a chosen point. Always cleared in the test's `defer`.
    static var injectedFailure: GaplessConversionFailurePoint? {
        get { injectionLock.lock(); defer { injectionLock.unlock() }; return injectedStorage }
        set { injectionLock.lock(); injectedStorage = newValue; injectionLock.unlock() }
    }
    #endif

    let sourceFormat: AVAudioFormat
    let destinationFormat: AVAudioFormat
    private let converter: AVAudioConverter
    /// Bounded staging buffer for decoded source PCM. Sized once from the format ratio; never grows.
    private let inputBuffer: AVAudioPCMBuffer
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessConvert")

    /// Source frames handed to the converter.
    private(set) var consumedInputFrames: AVAudioFramePosition = 0
    /// Output frames the converter actually produced — the authoritative count.
    private(set) var producedOutputFrames: AVAudioFramePosition = 0
    private(set) var conversionCalls = 0
    /// True once the converter has reported end of stream and drained its tail.
    private(set) var isFinished = false
    /// Set when the owning tail is superseded; further conversion is refused.
    private(set) var isCancelled = false

    /// Frames the converter emitted *after* its input ended — the resampler tail.
    private(set) var flushFrames: AVAudioFramePosition = 0
    private var inputEnded = false
    private var chunksProduced = 0

    /// - Parameter destinationChunkFrames: the largest output chunk that will be requested, used to
    ///   size the bounded input buffer.
    init(sourceFormat: AVAudioFormat, destinationFormat: AVAudioFormat,
         destinationChunkFrames: AVAudioFrameCount) throws {
        try GaplessChannelPolicy.validate(sourceChannels: sourceFormat.channelCount)
        #if DEBUG
        if Self.injectedFailure == .creation {
            throw GaplessConversionError.converterUnavailable(
                source: "\(sourceFormat.sampleRate)/\(sourceFormat.channelCount)",
                destination: "\(destinationFormat.sampleRate)/\(destinationFormat.channelCount)")
        }
        #endif
        guard let built = AVAudioConverter(from: sourceFormat, to: destinationFormat) else {
            throw GaplessConversionError.converterUnavailable(
                source: "\(sourceFormat.sampleRate)/\(sourceFormat.channelCount)",
                destination: "\(destinationFormat.sampleRate)/\(destinationFormat.channelCount)")
        }
        self.sourceFormat = sourceFormat
        self.destinationFormat = destinationFormat
        converter = built

        // Enough source frames to satisfy one output chunk, plus slack for resampler priming. The
        // converter asks for what it needs and is called again if it needs more, so this is a
        // staging bound rather than a requirement to be exact.
        let ratio = sourceFormat.sampleRate / destinationFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(destinationChunkFrames) * ratio).rounded(.up)) + 2_048
        guard let staging = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: capacity) else {
            throw GaplessConversionError.converterUnavailable(
                source: sourceFormat.description, destination: destinationFormat.description)
        }
        inputBuffer = staging

        Self.liveLock.lock()
        Self.liveStorage += 1
        Self.createdStorage += 1
        Self.liveLock.unlock()
    }

    deinit {
        Self.liveLock.lock()
        Self.liveStorage -= 1
        Self.liveLock.unlock()
    }

    /// Bytes held by this converter's staging buffer — constant for its lifetime.
    var stagingBytes: Int {
        Int(inputBuffer.frameCapacity) * Int(sourceFormat.channelCount) * MemoryLayout<Float>.size
    }

    /// Refuse any further output. Used when the tail this conversion belongs to is superseded, so a
    /// conversion already in progress cannot write into a buffer that now belongs to another track.
    func cancel() { isCancelled = true }

    /// Clear the resampler and the counters so this object can serve the next track.
    ///
    /// **Only valid when no other track holds this converter.** Two tracks converting through one
    /// `AVAudioConverter` at the same time would interleave their input into a single resampler
    /// state, which is why the scheduler checks liveness before reusing rather than reusing by
    /// format alone.
    ///
    /// Resetting deliberately does *not* preserve state across the boundary: a clean resampler is
    /// what makes each track's produced output exactly attributable to that track, which is what the
    /// timeline records are built from.
    func prepareForReuse() {
        converter.reset()
        consumedInputFrames = 0
        producedOutputFrames = 0
        conversionCalls = 0
        flushFrames = 0
        chunksProduced = 0
        inputEnded = false
        isFinished = false
    }

    /// Convert into `destination`, pulling source PCM from `provider` as the converter asks for it.
    ///
    /// `provider` fills the staging buffer and returns how many source frames it wrote; returning 0
    /// signals end of source, after which the converter is allowed to flush its tail.
    ///
    /// Returns the frames actually written to `destination` — 0 once the stream is fully drained.
    @discardableResult
    func convert(into destination: AVAudioPCMBuffer,
                 provider: (AVAudioPCMBuffer) throws -> AVAudioFrameCount) throws -> AVAudioFrameCount {
        guard !isCancelled else { throw GaplessConversionError.cancelled }
        guard !isFinished else { return 0 }

        try checkInjectedFailure()
        destination.frameLength = 0

        // `AVAudioConverterInputBlock` is escaping and `@Sendable`, but it is only ever invoked
        // synchronously from inside the `convert` call below — on this thread, before it returns.
        // Passing the reader through a box makes that explicit and keeps the block from capturing
        // either `self` or a non-Sendable closure, rather than silencing the checker at the call.
        final class Context: @unchecked Sendable {
            /// Optional so it can be cleared before `withoutActuallyEscaping` returns. Holding the
            /// borrowed closure past that scope is exactly the contract violation the runtime traps
            /// on, so the box must not outlive it *holding* the closure.
            var provider: ((AVAudioPCMBuffer) throws -> AVAudioFrameCount)?
            let buffer: AVAudioPCMBuffer
            var inputEnded: Bool
            var error: Error?
            var consumed: AVAudioFramePosition = 0
            init(buffer: AVAudioPCMBuffer, inputEnded: Bool) {
                self.buffer = buffer
                self.inputEnded = inputEnded
            }
        }

        var status: AVAudioConverterOutputStatus = .haveData
        var conversionError: NSError?
        let context = Context(buffer: inputBuffer, inputEnded: inputEnded)
        withoutActuallyEscaping(provider) { escaping in
            context.provider = escaping
            defer { context.provider = nil }
            status = converter.convert(to: destination, error: &conversionError) { _, outStatus in
                guard !context.inputEnded, let provider = context.provider else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    let written = try provider(context.buffer)
                    if written == 0 {
                        context.inputEnded = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    context.buffer.frameLength = written
                    context.consumed += AVAudioFramePosition(written)
                    outStatus.pointee = .haveData
                    return context.buffer
                } catch {
                    context.error = error
                    outStatus.pointee = .endOfStream
                    return nil
                }
            }
        }

        inputEnded = context.inputEnded
        consumedInputFrames += context.consumed

        // Rethrown as-is: a decode failure that surfaced through the input block is still a decode
        // failure, and relabelling it as a conversion failure would misdirect the recovery.
        if let providerError = context.error { throw providerError }
        if let conversionError {
            throw GaplessConversionError.conversionFailed(conversionError.localizedDescription)
        }

        conversionCalls += 1
        let produced = destination.frameLength
        producedOutputFrames += AVAudioFramePosition(produced)
        if inputEnded { flushFrames += AVAudioFramePosition(produced) }
        if produced > 0 { chunksProduced += 1 }

        try applyStatus(status, produced: produced)
        return produced
    }

    /// DEBUG-only failure injection, kept out of `convert` so the conversion path reads as one
    /// sequence rather than a sequence interleaved with test scaffolding.
    private func checkInjectedFailure() throws {
        #if DEBUG
        switch Self.injectedFailure {
        case .beforeFirstOutput where producedOutputFrames == 0:
            throw GaplessConversionError.conversionFailed("injected: before first output")
        case .afterChunks(let count) where chunksProduced >= count:
            throw GaplessConversionError.conversionFailed("injected: after \(count) chunks")
        case .flush where inputEnded:
            throw GaplessConversionError.conversionFailed("injected: flush")
        default: break
        }
        #endif
    }

    private func applyStatus(_ status: AVAudioConverterOutputStatus,
                             produced: AVAudioFrameCount) throws {
        switch status {
        case .endOfStream:
            isFinished = true
        case .error:
            throw GaplessConversionError.conversionFailed("converter reported .error")
        case .haveData, .inputRanDry:
            // `inputRanDry` with the source ended means the tail has been drained.
            if inputEnded, produced == 0 { isFinished = true }
        @unknown default:
            break
        }
    }

    /// Frames this converter would be *expected* to produce for a given input length. Planning only
    /// — never used as the authoritative timeline length.
    func estimatedOutputFrames(forInputFrames input: AVAudioFramePosition) -> AVAudioFramePosition {
        AVAudioFramePosition((Double(input) * destinationFormat.sampleRate
                              / sourceFormat.sampleRate).rounded())
    }
}
