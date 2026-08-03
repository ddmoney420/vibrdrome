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
        /// An MP3 with no usable gapless header — cannot be trimmed exactly. See
        /// `GaplessTrimPolicy.trim(forFileAt:decodedLength:)` for what this costs.
        case mp3WithoutGaplessHeader
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

enum GaplessTrimPolicy {
    /// Bytes to inspect after any ID3v2 tag — the first MPEG frame (and so the Xing/LAME header)
    /// always begins here, and is far smaller than this.
    private static let headerProbeBytes = 4_096

    /// The frame range to schedule for a decoded file.
    ///
    /// For an MP3 with no gapless header — notably a **live server-side transcode**, where the
    /// encoder writes to a non-seekable stream and so cannot go back and fill in the header
    /// (verified: ffmpeg to a pipe emits no Xing/Info tag at all) — no exact trim exists. The whole
    /// file is scheduled and the join keeps the codec's inserted frames; the returned
    /// `.mp3WithoutGaplessHeader` reason makes that visible instead of silently lossy.
    static func trim(forFileAt url: URL, decodedLength: AVAudioFramePosition) -> GaplessTrim {
        guard url.pathExtension.lowercased() == "mp3" else {
            return GaplessTrim(startFrame: 0, frameCount: AVAudioFrameCount(max(0, decodedLength)),
                               reason: .wholeFile)
        }
        guard let header = mp3GaplessHeader(atFileURL: url) else {
            return GaplessTrim(startFrame: 0, frameCount: AVAudioFrameCount(max(0, decodedLength)),
                               reason: .mp3WithoutGaplessHeader)
        }
        let start = AVAudioFramePosition(header.encoderDelay)
        let trimmed = decodedLength - start - AVAudioFramePosition(header.padding)
        // A header that would trim away the entire file is not trustworthy — keep the whole file.
        guard trimmed > 0 else {
            return GaplessTrim(startFrame: 0, frameCount: AVAudioFrameCount(max(0, decodedLength)),
                               reason: .mp3WithoutGaplessHeader)
        }
        return GaplessTrim(startFrame: start, frameCount: AVAudioFrameCount(trimmed),
                           reason: .lameGaplessHeader)
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
