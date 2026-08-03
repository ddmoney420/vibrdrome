import AVFoundation
import Foundation

/// Which frames of a decoded file the persistent gapless engine should actually schedule.
///
/// Most formats need no trim — but MP3 does, and getting this wrong is an audible gap on every
/// join. Measured with `spike/gapless-formats/main.swift` against independently-encoded parts of one
/// continuous tone (the same shape as a real gapless album):
///
/// | source                      | `AVAudioFile.length` vs true length | verdict            |
/// |-----------------------------|-------------------------------------|--------------------|
/// | WAV / FLAC                  | exact                               | schedule whole file |
/// | ALAC / AAC (m4a)            | exact — Apple applies `iTunSMPB`    | schedule whole file |
/// | Opus                        | exact (decodes at 48 kHz)           | schedule whole file |
/// | MP3                         | **+1368 frames** (delay 576 + pad 792) | must trim       |
///
/// `AVAudioFile` hands back MP3 encoder delay *and* padding as ordinary audio — it does not apply
/// the Xing/LAME gapless header the way it applies `iTunSMPB` for m4a. Scheduling the whole file
/// therefore injects ~31 ms of encoder junk at every MP3 boundary (124 ms across a 4-track album).
/// Trimming to `[encoderDelay, length - padding)` restored exact frame continuity in the matrix.
struct GaplessTrim: Equatable, Sendable {
    /// First frame of the decoded file to schedule.
    let startFrame: AVAudioFramePosition
    /// Number of frames to schedule from `startFrame`.
    let frameCount: AVAudioFrameCount
    /// Why this range was chosen — surfaced in logs and diagnostics rather than inferred.
    let reason: Reason

    enum Reason: String, Equatable, Sendable {
        /// Decoder already reports the true audio length (WAV, FLAC, ALAC, AAC, Opus).
        case wholeFile
        /// Encoder delay + padding removed using the file's Xing/LAME gapless header.
        case lameGaplessHeader
        /// An MP3 carrying no *trustworthy* gapless metadata, so the exact encoder delay and final
        /// padding are unknown to the client and no reliable trim exists. Covers a missing header, a
        /// truncated or malformed one, and values that contradict the decoded length.
        ///
        /// This is a statement about **this response**, not about MP3 or live streams in general: a
        /// server could supply the same information by another mechanism, or spool the encode to a
        /// complete file before delivering it, and such a source would trim normally.
        case mp3WithoutGaplessMetadata
    }

    var endFrame: AVAudioFramePosition { startFrame + AVAudioFramePosition(frameCount) }
    /// True when the whole decoded file is scheduled unmodified.
    var isWholeFile: Bool { startFrame == 0 && reason == .wholeFile }
}

/// Encoder delay and padding declared by an MP3's Xing/Info + LAME header.
struct MP3GaplessHeader: Equatable {
    /// Frames of encoder priming at the start of the decoded stream.
    let encoderDelay: Int
    /// Frames of padding appended to fill the final MPEG frame.
    let padding: Int
}

/// What the trim policy parsed and why it decided as it did. Kept as a first-class value rather
/// than a log line so tests can assert on the *reasoning*, not just the outcome — a trim that lands
/// on the right range for the wrong reason is a latent bug.
struct GaplessTrimDiagnostics: Equatable, Sendable {
    let fileExtension: String
    let decodedLength: AVAudioFramePosition
    /// Values exactly as parsed from the file, before any validation.
    let rawEncoderDelay: Int?
    let rawPadding: Int?
    let validation: Validation
    /// The range actually handed to the player node.
    let selectedStartFrame: AVAudioFramePosition
    let selectedFrameCount: AVAudioFrameCount

    enum Validation: String, Equatable, Sendable {
        /// Not an MP3 — the decoder already reports the true length.
        case notMP3
        /// No Xing/Info + LAME header found.
        case metadataAbsent
        /// A header was found but could not be parsed into usable values.
        case metadataMalformed
        /// Values parsed, but they contradict the decoded length (delay + padding would consume the
        /// file, or exceed it). Trusting them would produce an invalid schedule range.
        case rangeInconsistentWithDecodedLength
        /// Values parsed and validated; the trim was applied.
        case accepted
    }
}

enum GaplessTrimPolicy {
    /// Bytes to inspect after any ID3v2 tag — the first MPEG frame (and so the Xing/LAME header)
    /// always begins here, and is far smaller than this.
    private static let headerProbeBytes = 4_096

    /// The frame range to schedule for a decoded file.
    ///
    /// When an MP3 carries no trustworthy gapless metadata, the exact encoder delay and final
    /// padding are unknown to the client, so no reliable trim exists. The whole file is scheduled
    /// and the join keeps the codec's inserted frames — reported as `.mp3WithoutGaplessMetadata`
    /// rather than presented as gapless.
    ///
    /// No fallback constant is ever applied. A fixed 576/792 guess is right only for one encoder at
    /// one setting; applied to anything else it deletes real audio or leaves padding in place, and
    /// either way it silently converts an honest "unsupported" into a wrong answer.
    static func trim(forFileAt url: URL, decodedLength: AVAudioFramePosition) -> GaplessTrim {
        evaluate(forFileAt: url, decodedLength: decodedLength).trim
    }

    /// The trim plus the reasoning behind it. Used by DEBUG diagnostics and by the trim tests.
    static func diagnostics(forFileAt url: URL,
                            decodedLength: AVAudioFramePosition) -> GaplessTrimDiagnostics {
        evaluate(forFileAt: url, decodedLength: decodedLength).diagnostics
    }

    /// Single source of truth for both the decision and the explanation, so they cannot diverge.
    private static func evaluate(forFileAt url: URL, decodedLength: AVAudioFramePosition)
        -> (trim: GaplessTrim, diagnostics: GaplessTrimDiagnostics) {
        let ext = url.pathExtension.lowercased()
        let safeLength = max(0, decodedLength)

        func wholeFile(_ reason: GaplessTrim.Reason,
                       _ validation: GaplessTrimDiagnostics.Validation,
                       delay: Int? = nil, padding: Int? = nil)
            -> (GaplessTrim, GaplessTrimDiagnostics) {
            let trim = GaplessTrim(startFrame: 0, frameCount: AVAudioFrameCount(safeLength),
                                   reason: reason)
            return (trim, GaplessTrimDiagnostics(
                fileExtension: ext, decodedLength: decodedLength, rawEncoderDelay: delay,
                rawPadding: padding, validation: validation,
                selectedStartFrame: 0, selectedFrameCount: AVAudioFrameCount(safeLength)))
        }

        guard ext == "mp3" else { return wholeFile(.wholeFile, .notMP3) }
        guard let header = mp3GaplessHeader(atFileURL: url) else {
            return wholeFile(.mp3WithoutGaplessMetadata, .metadataAbsent)
        }

        let delay = header.encoderDelay
        let padding = header.padding
        // Reject anything that cannot describe a real segment of this file: negative values, a
        // padding larger than the file, or a delay+padding pair that would consume all of it.
        // Arithmetic is done in Int64 so an absurd pair cannot overflow into a plausible range.
        let start = AVAudioFramePosition(delay)
        let remaining = safeLength - start - AVAudioFramePosition(padding)
        guard delay >= 0, padding >= 0, start < safeLength, remaining > 0 else {
            return wholeFile(.mp3WithoutGaplessMetadata, .rangeInconsistentWithDecodedLength,
                             delay: delay, padding: padding)
        }

        let trim = GaplessTrim(startFrame: start, frameCount: AVAudioFrameCount(remaining),
                               reason: .lameGaplessHeader)
        return (trim, GaplessTrimDiagnostics(
            fileExtension: ext, decodedLength: decodedLength, rawEncoderDelay: delay,
            rawPadding: padding, validation: .accepted,
            selectedStartFrame: start, selectedFrameCount: AVAudioFrameCount(remaining)))
    }

    /// Read an MP3's Xing/LAME gapless header, reading only the file's leading bytes.
    static func mp3GaplessHeader(atFileURL url: URL) -> MP3GaplessHeader? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 10), prefix.count == 10 else { return nil }

        // An ID3v2 tag can carry embedded artwork, so skip it by its declared size rather than
        // reading a large speculative chunk.
        var audioStart = 0
        if prefix[0] == 0x49, prefix[1] == 0x44, prefix[2] == 0x33 {           // "ID3"
            let size = (Int(prefix[6]) << 21) | (Int(prefix[7]) << 14)
                | (Int(prefix[8]) << 7) | Int(prefix[9])
            audioStart = 10 + size
            if prefix[5] & 0x10 != 0 { audioStart += 10 }                      // footer present
        }
        try? handle.seek(toOffset: UInt64(audioStart))
        guard let data = try? handle.read(upToCount: headerProbeBytes) else { return nil }
        return mp3GaplessHeader(inFirstFrame: data)
    }

    /// Parse a Xing/Info + LAME header from bytes starting at the first MPEG audio frame.
    /// Pure and self-contained so it can be unit-tested without a fixture file.
    static func mp3GaplessHeader(inFirstFrame data: Data) -> MP3GaplessHeader? {
        let bytes = [UInt8](data)
        guard bytes.count > 4 else { return nil }
        // MPEG audio frame sync: 11 set bits.
        guard bytes[0] == 0xFF, bytes[1] & 0xE0 == 0xE0 else { return nil }

        let isMPEG1 = (bytes[1] >> 3) & 0x03 == 0x03      // 0b11 = MPEG1, 0b10 = MPEG2, 0b00 = 2.5
        let isMono = (bytes[3] >> 6) & 0x03 == 0x03       // 0b11 = single channel
        // The Xing tag sits after the frame header's side-information block, whose size depends on
        // MPEG version and channel mode.
        let sideInfoSize: Int
        switch (isMPEG1, isMono) {
        case (true, true): sideInfoSize = 17
        case (true, false): sideInfoSize = 32
        case (false, true): sideInfoSize = 9
        case (false, false): sideInfoSize = 17
        }

        var pos = 4 + sideInfoSize
        guard pos + 8 <= bytes.count else { return nil }
        let tag = String(bytes: bytes[pos..<(pos + 4)], encoding: .ascii)
        guard tag == "Xing" || tag == "Info" else { return nil }   // Xing = VBR, Info = CBR
        pos += 4

        let flags = (Int(bytes[pos]) << 24) | (Int(bytes[pos + 1]) << 16)
            | (Int(bytes[pos + 2]) << 8) | Int(bytes[pos + 3])
        pos += 4
        if flags & 0x01 != 0 { pos += 4 }                  // frame count
        if flags & 0x02 != 0 { pos += 4 }                  // byte count
        if flags & 0x04 != 0 { pos += 100 }                // seek table
        if flags & 0x08 != 0 { pos += 4 }                  // VBR quality

        // LAME extension: 9-byte encoder string, then fixed fields; delay/padding are packed as
        // two 12-bit values across 3 bytes at offset 21.
        guard pos + 24 <= bytes.count else { return nil }
        guard let encoder = String(bytes: bytes[pos..<(pos + 4)], encoding: .ascii),
              encoder == "LAME" || encoder == "Lavc" || encoder == "Lavf" else { return nil }
        let high = Int(bytes[pos + 21]), mid = Int(bytes[pos + 22]), low = Int(bytes[pos + 23])
        // Both fields are 12-bit, so they are inherently bounded (0...4095) and need no range check
        // here. The guard that matters is against the file's real length, applied in `trim(...)`:
        // a header that would trim away everything is rejected there.
        let delay = (high << 4) | (mid >> 4)
        let padding = ((mid & 0x0F) << 8) | low
        return MP3GaplessHeader(encoderDelay: delay, padding: padding)
    }
}
