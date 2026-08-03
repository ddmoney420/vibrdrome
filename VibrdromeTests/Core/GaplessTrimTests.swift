import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Tests for the per-format schedulable-range policy.
///
/// The MP3 case is the one that matters: `AVAudioFile` reports MP3 encoder delay and padding as
/// ordinary audio (measured: +1368 frames per track for a LAME 320 encode), so scheduling the whole
/// file injects ~31 ms of encoder junk at every join. These tests pin the parsing that removes it.
struct GaplessTrimTests {

    // MARK: - Non-MP3 sources are scheduled whole

    @Test(arguments: ["flac", "m4a", "wav", "opus"])
    func nonMP3SourcesScheduleTheWholeFile(ext: String) {
        let url = URL(fileURLWithPath: "/tmp/track.\(ext)")
        let trim = GaplessTrimPolicy.trim(forFileAt: url, decodedLength: 441_000)

        #expect(trim.startFrame == 0)
        #expect(trim.frameCount == 441_000)
        #expect(trim.reason == .wholeFile)
        #expect(trim.isWholeFile)
    }

    // MARK: - Xing / LAME header parsing

    @Test func parsesEncoderDelayAndPaddingFromLAMEHeader() throws {
        let frame = Self.makeXingFrame(encoderDelay: 576, padding: 792)
        let header = try #require(GaplessTrimPolicy.mp3GaplessHeader(inFirstFrame: frame))

        #expect(header.encoderDelay == 576)
        #expect(header.padding == 792)
    }

    /// The two values are packed as 12-bit fields across three bytes; an off-by-a-nibble parse still
    /// yields plausible-looking numbers, so check a pair that would not survive one.
    @Test func parsesTwelveBitPackedDelayAndPadding() throws {
        let frame = Self.makeXingFrame(encoderDelay: 0xABC, padding: 0x123)
        let header = try #require(GaplessTrimPolicy.mp3GaplessHeader(inFirstFrame: frame))

        #expect(header.encoderDelay == 0xABC)
        #expect(header.padding == 0x123)
    }

    @Test func rejectsBytesThatAreNotAnMPEGFrame() {
        #expect(GaplessTrimPolicy.mp3GaplessHeader(inFirstFrame: Data(repeating: 0, count: 512)) == nil)
    }

    @Test func rejectsAnMPEGFrameWithNoXingTag() {
        var bytes: [UInt8] = [0xFF, 0xFB, 0xE0, 0xC0]
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 512))
        #expect(GaplessTrimPolicy.mp3GaplessHeader(inFirstFrame: Data(bytes)) == nil)
    }

    /// Delay and padding are 12-bit fields, so they are inherently bounded and the parser needs no
    /// range check of its own. The guard that matters is against the file's real length, covered by
    /// `refusesATrimThatWouldConsumeTheEntireFile`.
    @Test func parsesTheFullTwelveBitRange() throws {
        let frame = Self.makeXingFrame(encoderDelay: 4_095, padding: 4_095)
        let header = try #require(GaplessTrimPolicy.mp3GaplessHeader(inFirstFrame: frame))

        #expect(header.encoderDelay == 4_095)
        #expect(header.padding == 4_095)
    }

    // MARK: - Trim applied to a real file on disk

    @Test func trimsMP3ByItsGaplessHeader() throws {
        let url = try Self.writeMP3Fixture(encoderDelay: 576, padding: 792, id3Bytes: 0)
        defer { try? FileManager.default.removeItem(at: url) }

        // 441000 frames of audio, as LAME would decode it: delay + audio + padding.
        let trim = GaplessTrimPolicy.trim(forFileAt: url, decodedLength: 442_368)

        #expect(trim.startFrame == 576)
        #expect(trim.frameCount == 441_000)          // exactly the true source length
        #expect(trim.reason == .lameGaplessHeader)
    }

    /// Real MP3s carry an ID3v2 tag (often with embedded art) before the first audio frame.
    @Test func findsGaplessHeaderPastAnID3v2Tag() throws {
        let url = try Self.writeMP3Fixture(encoderDelay: 576, padding: 792, id3Bytes: 4_096)
        defer { try? FileManager.default.removeItem(at: url) }

        let trim = GaplessTrimPolicy.trim(forFileAt: url, decodedLength: 442_368)

        #expect(trim.startFrame == 576)
        #expect(trim.frameCount == 441_000)
        #expect(trim.reason == .lameGaplessHeader)
    }

    /// A live server-side transcode writes to a non-seekable stream, so the encoder never fills in
    /// the gapless header. There is no exact trim — but the engine must say so, not pretend.
    @Test func reportsMP3WithNoGaplessHeaderInsteadOfGuessing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gtrim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("stream.mp3")
        var bytes: [UInt8] = [0xFF, 0xFB, 0xE0, 0xC0]
        bytes.append(contentsOf: [UInt8](repeating: 0x5A, count: 2_048))
        try Data(bytes).write(to: url)

        let trim = GaplessTrimPolicy.trim(forFileAt: url, decodedLength: 442_368)

        #expect(trim.startFrame == 0)
        #expect(trim.frameCount == 442_368)          // whole file — the join keeps codec padding
        #expect(trim.reason == .mp3WithoutGaplessMetadata)
        #expect(!trim.isWholeFile)                   // not a clean whole-file source
    }

    /// A header claiming to trim away everything is corrupt; keeping the audio beats silence.
    @Test func refusesATrimThatWouldConsumeTheEntireFile() throws {
        let url = try Self.writeMP3Fixture(encoderDelay: 576, padding: 792, id3Bytes: 0)
        defer { try? FileManager.default.removeItem(at: url) }

        let trim = GaplessTrimPolicy.trim(forFileAt: url, decodedLength: 1_000)

        #expect(trim.frameCount == 1_000)
        #expect(trim.reason == .mp3WithoutGaplessMetadata)
    }

    // MARK: - Hardening: layout variants a naive parser gets wrong

    /// The Xing tag's offset moves with MPEG version and channel mode. A parser that assumes one
    /// layout reads garbage from the others — and garbage that still *looks* like plausible
    /// delay/padding numbers is the dangerous case, because it produces a wrong trim silently.
    @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
    func parsesEveryMPEGVersionAndChannelLayout(variant: (mpeg1: Bool, mono: Bool)) throws {
        let frame = Self.makeXingFrame(encoderDelay: 576, padding: 792,
                                       mpeg1: variant.mpeg1, mono: variant.mono)
        let header = try #require(GaplessTrimPolicy.mp3GaplessHeader(inFirstFrame: frame),
                                  "mpeg1=\(variant.mpeg1) mono=\(variant.mono)")

        #expect(header.encoderDelay == 576)
        #expect(header.padding == 792)
    }

    /// VBR files carry "Xing", CBR files carry "Info". Both are valid and both must parse.
    @Test(arguments: [true, false])
    func parsesBothVBRAndCBRTagVariants(vbr: Bool) throws {
        let frame = Self.makeXingFrame(encoderDelay: 1_105, padding: 1_051, vbr: vbr)
        let header = try #require(GaplessTrimPolicy.mp3GaplessHeader(inFirstFrame: frame))

        #expect(header.encoderDelay == 1_105)
        #expect(header.padding == 1_051)
    }

    /// The sample-rate index lives in the frame header but does not move the Xing tag, so parsing
    /// must be indifferent to it.
    @Test(arguments: [UInt8(0x00), UInt8(0x01), UInt8(0x02)])
    func parsingIsIndependentOfSampleRate(sampleRateBits: UInt8) throws {
        let frame = Self.makeXingFrame(encoderDelay: 576, padding: 792,
                                       sampleRateBits: sampleRateBits)
        let header = try #require(GaplessTrimPolicy.mp3GaplessHeader(inFirstFrame: frame))

        #expect(header.encoderDelay == 576)
    }

    /// A response cut short mid-header must be refused, not read past its end.
    @Test(arguments: [30, 60, 100, 140])
    func truncatedHeaderIsRefusedRatherThanReadPastTheEnd(truncateAfter: Int) {
        let frame = Self.makeXingFrame(encoderDelay: 576, padding: 792, truncateAfter: truncateAfter)

        // Either it parses cleanly or it refuses — but it must never crash or read out of bounds.
        let header = GaplessTrimPolicy.mp3GaplessHeader(inFirstFrame: frame)
        if let header {
            #expect(header.encoderDelay >= 0)
            #expect(header.padding >= 0)
        }
    }

    // MARK: - Hardening: values that cannot describe a real segment

    /// Padding larger than the whole file, a delay past the end, or a pair that consumes everything:
    /// each must fall back to an untrimmed classification rather than produce an invalid range.
    @Test(arguments: [
        (delay: 576, padding: 4_000, decoded: 3_000),      // padding exceeds the file
        (delay: 4_000, padding: 0, decoded: 3_000),        // delay past the end
        (delay: 2_000, padding: 2_000, decoded: 4_000),    // consumes exactly everything
        (delay: 2_000, padding: 3_000, decoded: 4_000),    // negative remainder
        (delay: 0, padding: 0, decoded: 0)                 // empty file
    ])
    func inconsistentMetadataYieldsASafeUntrimmedRange(scenario: (delay: Int, padding: Int, decoded: Int)) throws {
        let url = try Self.writeMP3Fixture(encoderDelay: scenario.delay, padding: scenario.padding,
                                           id3Bytes: 0)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = AVAudioFramePosition(scenario.decoded)

        let trim = GaplessTrimPolicy.trim(forFileAt: url, decodedLength: decoded)
        let diagnostics = GaplessTrimPolicy.diagnostics(forFileAt: url, decodedLength: decoded)

        // Never an invalid schedule range.
        #expect(trim.startFrame == 0)
        #expect(trim.frameCount == AVAudioFrameCount(max(0, decoded)))
        #expect(trim.reason == .mp3WithoutGaplessMetadata)
        #expect(diagnostics.validation == .rangeInconsistentWithDecodedLength)
        // The raw values stay visible so the rejection can be explained, not just observed.
        #expect(diagnostics.rawEncoderDelay == scenario.delay)
        #expect(diagnostics.rawPadding == scenario.padding)
    }

    // MARK: - Diagnostics

    @Test func diagnosticsRecordTheAcceptedTrimAndItsInputs() throws {
        let url = try Self.writeMP3Fixture(encoderDelay: 576, padding: 792, id3Bytes: 0)
        defer { try? FileManager.default.removeItem(at: url) }

        let diagnostics = GaplessTrimPolicy.diagnostics(forFileAt: url, decodedLength: 442_368)

        #expect(diagnostics.fileExtension == "mp3")
        #expect(diagnostics.decodedLength == 442_368)
        #expect(diagnostics.rawEncoderDelay == 576)
        #expect(diagnostics.rawPadding == 792)
        #expect(diagnostics.validation == .accepted)
        #expect(diagnostics.selectedStartFrame == 576)
        #expect(diagnostics.selectedFrameCount == 441_000)
    }

    @Test func diagnosticsDistinguishAbsentMetadataFromInconsistentMetadata() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gtrim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("stream.mp3")
        try Data([0xFF, 0xFB, 0xE0, 0xC0] + [UInt8](repeating: 0x5A, count: 2_048)).write(to: url)

        let diagnostics = GaplessTrimPolicy.diagnostics(forFileAt: url, decodedLength: 442_368)

        #expect(diagnostics.validation == .metadataAbsent)
        #expect(diagnostics.rawEncoderDelay == nil)
        #expect(diagnostics.rawPadding == nil)
    }

    @Test func nonMP3FilesAreDiagnosedAsNotMP3RatherThanAsMissingMetadata() {
        let diagnostics = GaplessTrimPolicy.diagnostics(forFileAt: URL(fileURLWithPath: "/tmp/a.flac"),
                                                        decodedLength: 441_000)

        #expect(diagnostics.validation == .notMP3)
        #expect(diagnostics.selectedFrameCount == 441_000)
    }

    // MARK: - Fixtures

    /// A byte-accurate MPEG Layer III frame carrying a Xing(VBR) or Info(CBR) + LAME header.
    ///
    /// The Xing tag's position depends on the side-information block, whose size varies with MPEG
    /// version and channel mode — so these knobs are exactly the ones that break a naive parser.
    static func makeXingFrame(encoderDelay: Int, padding: Int, mpeg1: Bool = true,
                              mono: Bool = true, vbr: Bool = false,
                              sampleRateBits: UInt8 = 0x00, truncateAfter: Int? = nil) -> Data {
        // byte1 = 111 VV LL P  (VV: 11 = MPEG1, 10 = MPEG2; LL: 01 = Layer III)
        let versionByte: UInt8 = mpeg1 ? 0xFB : 0xF3
        // byte2 carries bitrate and sample-rate index; neither shifts the Xing offset.
        let rateByte: UInt8 = 0xE0 | (sampleRateBits << 2)
        let modeByte: UInt8 = mono ? 0xC0 : 0x00
        var bytes: [UInt8] = [0xFF, versionByte, rateByte, modeByte]

        let sideInfo: Int
        switch (mpeg1, mono) {
        case (true, true): sideInfo = 17
        case (true, false): sideInfo = 32
        case (false, true): sideInfo = 9
        case (false, false): sideInfo = 17
        }
        bytes.append(contentsOf: [UInt8](repeating: 0, count: sideInfo))
        bytes.append(contentsOf: Array((vbr ? "Xing" : "Info").utf8))
        bytes.append(contentsOf: [0x00, 0x00, 0x00, 0x0F])   // all four optional fields present
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 4))    // frame count
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 4))    // byte count
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 100))  // seek table
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 4))    // VBR quality
        bytes.append(contentsOf: Array("LAME3.100".utf8))             // encoder string (9 bytes)
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 12))    // fields up to offset 21
        bytes.append(UInt8((encoderDelay >> 4) & 0xFF))
        bytes.append(UInt8(((encoderDelay & 0x0F) << 4) | ((padding >> 8) & 0x0F)))
        bytes.append(UInt8(padding & 0xFF))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 64))    // frame remainder
        if let truncateAfter { bytes = Array(bytes.prefix(truncateAfter)) }
        return Data(bytes)
    }

    /// Writes a file whose leading bytes are a real Xing/LAME header, optionally behind an ID3v2 tag
    /// of `id3Bytes` payload bytes.
    static func writeMP3Fixture(encoderDelay: Int, padding: Int, id3Bytes: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gtrim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("track.mp3")

        var data = Data()
        if id3Bytes > 0 {
            // "ID3" + version + flags + 7-bit-per-byte syncsafe size.
            data.append(contentsOf: Array("ID3".utf8))
            data.append(contentsOf: [0x04, 0x00, 0x00])
            data.append(contentsOf: [UInt8((id3Bytes >> 21) & 0x7F), UInt8((id3Bytes >> 14) & 0x7F),
                                     UInt8((id3Bytes >> 7) & 0x7F), UInt8(id3Bytes & 0x7F)])
            data.append(contentsOf: [UInt8](repeating: 0x41, count: id3Bytes))
        }
        data.append(makeXingFrame(encoderDelay: encoderDelay, padding: padding))
        try data.write(to: url)
        return url
    }
}
