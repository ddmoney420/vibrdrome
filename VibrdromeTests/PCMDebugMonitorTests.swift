#if DEBUG
import XCTest
@testable import Vibrdrome

/// Unit tests for the DEBUG-only PCM debug monitor's rate + over-production math.
/// Exercises `ingestSample(...)` directly with synthetic counters — no timer,
/// ring, or playback.
@MainActor
final class PCMDebugMonitorTests: XCTestCase {

    func testProducedAndConsumedRate() {
        let monitor = PCMDebugMonitor()
        monitor.ingestSample(produced: 0, consumed: 0, sampleRate: 44_100, at: 0)
        monitor.ingestSample(produced: 44_100, consumed: 44_000, sampleRate: 44_100, at: 1.0)
        XCTAssertEqual(monitor.producedRate, 44_100, accuracy: 0.5)
        XCTAssertEqual(monitor.consumedRate, 44_000, accuracy: 0.5)
        XCTAssertFalse(monitor.overProductionWarning)
    }

    func testFirstSampleHasNoRate() {
        let monitor = PCMDebugMonitor()
        monitor.ingestSample(produced: 1_000, consumed: 0, sampleRate: 44_100, at: 5.0)
        XCTAssertEqual(monitor.producedRate, 0) // needs two samples
    }

    func testRateUsesElapsedTime() {
        let monitor = PCMDebugMonitor()
        monitor.ingestSample(produced: 0, consumed: 0, sampleRate: 44_100, at: 10.0)
        monitor.ingestSample(produced: 22_050, consumed: 22_050, sampleRate: 44_100, at: 10.5) // 0.5s
        XCTAssertEqual(monitor.producedRate, 44_100, accuracy: 0.5) // 22050 / 0.5s
    }

    func testOverProductionWarningTrips() {
        let monitor = PCMDebugMonitor()
        monitor.ingestSample(produced: 0, consumed: 0, sampleRate: 44_100, at: 0)
        monitor.ingestSample(produced: 88_200, consumed: 88_200, sampleRate: 44_100, at: 1.0) // 2x
        XCTAssertTrue(monitor.overProductionWarning)
    }

    func testWarningClearsWhenRateNormalizes() {
        let monitor = PCMDebugMonitor()
        monitor.ingestSample(produced: 0, consumed: 0, sampleRate: 44_100, at: 0)
        monitor.ingestSample(produced: 88_200, consumed: 88_200, sampleRate: 44_100, at: 1.0)
        XCTAssertTrue(monitor.overProductionWarning)
        monitor.ingestSample(produced: 132_300, consumed: 132_300, sampleRate: 44_100, at: 2.0) // +44100 = 1x
        XCTAssertFalse(monitor.overProductionWarning)
    }

    func testOneXRateNoWarning() {
        let monitor = PCMDebugMonitor()
        monitor.ingestSample(produced: 0, consumed: 0, sampleRate: 48_000, at: 0)
        monitor.ingestSample(produced: 48_000, consumed: 48_000, sampleRate: 48_000, at: 1.0)
        XCTAssertFalse(monitor.overProductionWarning) // 1x, not >1.5x
    }

    func testNoWarningWhenSampleRateUnknown() {
        let monitor = PCMDebugMonitor()
        monitor.ingestSample(produced: 0, consumed: 0, sampleRate: 0, at: 0)
        monitor.ingestSample(produced: 1_000_000, consumed: 0, sampleRate: 0, at: 1.0)
        XCTAssertFalse(monitor.overProductionWarning) // unknown rate -> no warning
    }
}
#endif
