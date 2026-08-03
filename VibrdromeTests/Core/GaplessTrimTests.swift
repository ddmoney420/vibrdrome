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
        #expect(trim.reason == .mp3WithoutGaplessHeader)
        #expect(!trim.isWholeFile)                   // not a clean whole-file source
    }

    /// A header claiming to trim away everything is corrupt; keeping the audio beats silence.
    @Test func refusesATrimThatWouldConsumeTheEntireFile() throws {
        let url = try Self.writeMP3Fixture(encoderDelay: 576, padding: 792, id3Bytes: 0)
        defer { try? FileManager.default.removeItem(at: url) }

        let trim = GaplessTrimPolicy.trim(forFileAt: url, decodedLength: 1_000)

        #expect(trim.frameCount == 1_000)
        #expect(trim.reason == .mp3WithoutGaplessHeader)
    }

    // MARK: - Fixtures

    /// A byte-accurate MPEG1 Layer III mono frame carrying an Info(CBR)/LAME header.
    static func makeXingFrame(encoderDelay: Int, padding: Int) -> Data {
        var bytes: [UInt8] = [0xFF, 0xFB, 0xE0, 0xC0]        // MPEG1 Layer III, single channel
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 17))   // side info (MPEG1 mono)
        bytes.append(contentsOf: Array("Info".utf8))
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
