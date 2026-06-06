import XCTest
@testable import Vibrdrome

/// Unit tests for the SPSC `FloatRingBuffer`. All data is synthetic and
/// in-memory — no audio hardware, no AVFoundation, no tap involvement.
final class FloatRingBufferTests: XCTestCase {

    /// Write interleaved frames from a flat `[Float]` (length must be a multiple
    /// of the buffer's channel count).
    private func write(_ buffer: FloatRingBuffer, _ samples: [Float]) {
        samples.withUnsafeBufferPointer { ptr in
            buffer.writeInterleaved(ptr.baseAddress!, frameCount: samples.count / buffer.channelCount)
        }
    }

    /// Read up to `maxFrames` and return the interleaved samples actually read.
    private func read(_ buffer: FloatRingBuffer, maxFrames: Int) -> [Float] {
        var out = [Float](repeating: -999, count: maxFrames * buffer.channelCount)
        let frames = out.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, maxFrames: maxFrames)
        }
        return Array(out.prefix(frames * buffer.channelCount))
    }

    func testEmptyReadReturnsZero() {
        let buffer = FloatRingBuffer(frameCapacity: 8, channelCount: 2)
        XCTAssertEqual(read(buffer, maxFrames: 4).count, 0)
        XCTAssertEqual(buffer.stats.underrunReads, 1)
    }

    func testBasicWriteRead() {
        let buffer = FloatRingBuffer(frameCapacity: 8, channelCount: 2)
        write(buffer, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(read(buffer, maxFrames: 3), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(buffer.stats.fillFrames, 0)
    }

    func testWraparound() {
        let buffer = FloatRingBuffer(frameCapacity: 4, channelCount: 2)
        write(buffer, [1, 1, 2, 2, 3, 3])
        _ = read(buffer, maxFrames: 3)
        write(buffer, [4, 4, 5, 5, 6, 6])
        XCTAssertEqual(read(buffer, maxFrames: 3), [4, 4, 5, 5, 6, 6])
    }

    func testOverflowDropsOldest() {
        let buffer = FloatRingBuffer(frameCapacity: 4, channelCount: 2)
        write(buffer, [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6]) // 6 frames into a 4-frame buffer
        XCTAssertEqual(buffer.stats.overflowFrames, 2)
        XCTAssertEqual(read(buffer, maxFrames: 4), [3, 3, 4, 4, 5, 5, 6, 6]) // last 4 retained
    }

    func testUnderrunCount() {
        let buffer = FloatRingBuffer(frameCapacity: 8, channelCount: 2)
        write(buffer, [1, 2, 3, 4]) // 2 frames
        XCTAssertEqual(read(buffer, maxFrames: 5).count, 4) // got 2 frames
        XCTAssertEqual(buffer.stats.underrunReads, 1)
    }

    func testStereoInterleaveOrder() {
        let buffer = FloatRingBuffer(frameCapacity: 8, channelCount: 2)
        let left: [Float] = [10, 11, 12]
        let right: [Float] = [20, 21, 22]
        left.withUnsafeBufferPointer { leftPtr in
            right.withUnsafeBufferPointer { rightPtr in
                buffer.writePlanarStereo(left: leftPtr.baseAddress!, right: rightPtr.baseAddress!, frameCount: 3)
            }
        }
        XCTAssertEqual(read(buffer, maxFrames: 3), [10, 20, 11, 21, 12, 22])
    }

    func testMonoDuplication() {
        let buffer = FloatRingBuffer(frameCapacity: 8, channelCount: 2)
        let mono: [Float] = [7, 8, 9]
        mono.withUnsafeBufferPointer { ptr in
            buffer.writePlanarStereo(left: ptr.baseAddress!, right: ptr.baseAddress!, frameCount: 3)
        }
        XCTAssertEqual(read(buffer, maxFrames: 3), [7, 7, 8, 8, 9, 9])
    }

    func testReset() {
        let buffer = FloatRingBuffer(frameCapacity: 8, channelCount: 2)
        write(buffer, [1, 2, 3, 4])
        buffer.reset()
        XCTAssertEqual(buffer.stats.fillFrames, 0)
        XCTAssertEqual(buffer.stats.overflowFrames, 0)
        XCTAssertEqual(buffer.stats.underrunReads, 0)
        XCTAssertEqual(read(buffer, maxFrames: 4).count, 0)
    }

    func testCapacityRoundsUpToPowerOfTwo() {
        let buffer = FloatRingBuffer(frameCapacity: 5000, channelCount: 2)
        XCTAssertEqual(buffer.frameCapacity, 8192)
    }
}
