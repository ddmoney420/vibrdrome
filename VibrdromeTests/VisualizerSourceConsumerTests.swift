#if DEBUG
import XCTest
@testable import Vibrdrome

/// A visualizer render consumer owns `VisualizerPCMSource` activation, and the
/// DEBUG PCM overlay must defer to it — stats-only, with NO second drain on the
/// single-producer/single-consumer ring. These tests exercise that coordination
/// through the public API (`active` / `hasActiveConsumer`); the overlay's private
/// `owningActivation` is verified by its observable effect (it does not flip the
/// renderer's activation).
final class VisualizerSourceConsumerTests: XCTestCase {

    override func tearDown() {
        // Leave the shared singleton inert so other tests start clean.
        VisualizerPCMSource.shared.endRenderConsumer()
        super.tearDown()
    }

    func testBeginEndRenderConsumerTogglesActivation() {
        let source = VisualizerPCMSource.shared
        source.endRenderConsumer()
        XCTAssertFalse(source.hasActiveConsumer)
        XCTAssertFalse(source.active)

        source.beginRenderConsumer()
        XCTAssertTrue(source.hasActiveConsumer)
        XCTAssertTrue(source.active)            // EQ tap write enabled

        source.endRenderConsumer()
        XCTAssertFalse(source.hasActiveConsumer)
        XCTAssertFalse(source.active)
    }

    /// With a renderer attached, the overlay must not take ownership or deactivate.
    @MainActor
    func testOverlayDefersToRenderConsumer() {
        let source = VisualizerPCMSource.shared
        source.beginRenderConsumer()            // renderer is the consumer
        let monitor = PCMDebugMonitor()

        monitor.start()
        XCTAssertTrue(source.hasActiveConsumer)
        XCTAssertTrue(source.active)

        monitor.stop()
        XCTAssertTrue(source.active, "overlay stop must not clear the renderer's active flag")

        source.endRenderConsumer()
        XCTAssertFalse(source.active)
    }

    /// With no renderer, the overlay keeps the legacy 1D behavior: it owns
    /// activation for its own lifetime.
    @MainActor
    func testOverlayOwnsActivationWhenNoConsumer() {
        let source = VisualizerPCMSource.shared
        source.endRenderConsumer()
        XCTAssertFalse(source.active)

        let monitor = PCMDebugMonitor()
        monitor.start()
        XCTAssertTrue(source.active)            // overlay owns activation (1D)
        monitor.stop()
        XCTAssertFalse(source.active)           // and releases it
    }
}
#endif
