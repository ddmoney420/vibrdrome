import XCTest
@testable import Vibrdrome

/// Unit tests for `VisualizerPCMSource`. Synthetic, in-memory; no audio tap.
final class VisualizerPCMSourceTests: XCTestCase {

    func testDefaultConfiguration() {
        let source = VisualizerPCMSource()
        XCTAssertEqual(source.stats.capacityFrames, 16384)
        XCTAssertEqual(source.stats.channelCount, 2)
        XCTAssertEqual(source.stats.fillFrames, 0)
    }

    func testIngestStereoRoundTrip() {
        let source = VisualizerPCMSource(frameCapacity: 64)
        let frames: [Float] = [1, 2, 3, 4, 5, 6]
        frames.withUnsafeBufferPointer { ptr in
            source.ingestStereo(ptr.baseAddress!, frameCount: 3)
        }
        var out = [Float](repeating: 0, count: 6)
        let read = out.withUnsafeMutableBufferPointer { ptr in
            source.read(into: ptr.baseAddress!, maxFrames: 3)
        }
        XCTAssertEqual(read, 3)
        XCTAssertEqual(out, [1, 2, 3, 4, 5, 6])
    }

    func testIngestPlanarStereoInterleaves() {
        let source = VisualizerPCMSource(frameCapacity: 64)
        let left: [Float] = [1, 2]
        let right: [Float] = [3, 4]
        left.withUnsafeBufferPointer { leftPtr in
            right.withUnsafeBufferPointer { rightPtr in
                source.ingestPlanarStereo(left: leftPtr.baseAddress!, right: rightPtr.baseAddress!, frameCount: 2)
            }
        }
        var out = [Float](repeating: 0, count: 4)
        let read = out.withUnsafeMutableBufferPointer { ptr in
            source.read(into: ptr.baseAddress!, maxFrames: 2)
        }
        XCTAssertEqual(read, 2)
        XCTAssertEqual(out, [1, 3, 2, 4])
    }

    func testIngestMonoDuplicates() {
        let source = VisualizerPCMSource(frameCapacity: 64)
        let mono: [Float] = [9, 8]
        mono.withUnsafeBufferPointer { ptr in
            source.ingestMono(ptr.baseAddress!, frameCount: 2)
        }
        var out = [Float](repeating: 0, count: 4)
        let read = out.withUnsafeMutableBufferPointer { ptr in
            source.read(into: ptr.baseAddress!, maxFrames: 2)
        }
        XCTAssertEqual(read, 2)
        XCTAssertEqual(out, [9, 9, 8, 8])
    }

    func testSampleRateAndChannelMetadata() {
        let source = VisualizerPCMSource(frameCapacity: 64)
        source.sampleRate = 44100
        source.sourceChannelCount = 1
        XCTAssertEqual(source.sampleRate, 44100)
        XCTAssertEqual(source.sourceChannelCount, 1)
    }

    func testResetClears() {
        let source = VisualizerPCMSource(frameCapacity: 64)
        let frames: [Float] = [1, 2, 3, 4]
        frames.withUnsafeBufferPointer { ptr in
            source.ingestStereo(ptr.baseAddress!, frameCount: 2)
        }
        source.reset()
        XCTAssertEqual(source.stats.fillFrames, 0)
    }

    /// Phase 1B: `active` defaults false; a caller that honors it (like the EQ
    /// tap) writes nothing while inactive and writes once enabled.
    func testActiveFlagGatesWrites() {
        let source = VisualizerPCMSource(frameCapacity: 64)
        XCTAssertFalse(source.active)
        let frames: [Float] = [1, 2, 3, 4]

        if source.active {
            frames.withUnsafeBufferPointer { source.ingestStereo($0.baseAddress!, frameCount: 2) }
        }
        XCTAssertEqual(source.stats.producedFrames, 0) // inactive → no writes

        source.setActiveForTesting(true)
        XCTAssertTrue(source.active)
        if source.active {
            frames.withUnsafeBufferPointer { source.ingestStereo($0.baseAddress!, frameCount: 2) }
        }
        XCTAssertEqual(source.stats.producedFrames, 2) // active → writes flow
    }
}
