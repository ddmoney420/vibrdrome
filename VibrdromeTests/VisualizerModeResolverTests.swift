import XCTest
@testable import Vibrdrome

/// Pure gating logic for the Classic/Native mode picker. Native is suppressed by
/// Reduce Motion and Disable Visualizer (it runs on both device and simulator); the
/// effective mode falls back to Classic whenever Native is selected but not currently
/// selectable.
final class VisualizerModeResolverTests: XCTestCase {

    // MARK: - nativeSelectable

    func testSelectableWhenAllClear() {
        XCTAssertTrue(VisualizerModeResolver.nativeSelectable(
            reduceMotion: false, disableVisualizer: false))
    }

    func testNotSelectableUnderReduceMotion() {
        XCTAssertFalse(VisualizerModeResolver.nativeSelectable(
            reduceMotion: true, disableVisualizer: false))
    }

    func testNotSelectableWhenVisualizerDisabled() {
        XCTAssertFalse(VisualizerModeResolver.nativeSelectable(
            reduceMotion: false, disableVisualizer: true))
    }

    func testBothGatesSuppress() {
        XCTAssertFalse(VisualizerModeResolver.nativeSelectable(
            reduceMotion: true, disableVisualizer: true))
    }

    // MARK: - effectiveMode

    func testEffectiveNativeWhenSelectedAndClear() {
        XCTAssertEqual(VisualizerModeResolver.effectiveMode(
            selected: .native, reduceMotion: false, disableVisualizer: false), .native)
    }

    func testEffectiveFallsBackUnderReduceMotion() {
        XCTAssertEqual(VisualizerModeResolver.effectiveMode(
            selected: .native, reduceMotion: true, disableVisualizer: false), .classic)
    }

    func testEffectiveFallsBackWhenVisualizerDisabled() {
        XCTAssertEqual(VisualizerModeResolver.effectiveMode(
            selected: .native, reduceMotion: false, disableVisualizer: true), .classic)
    }

    func testEffectiveClassicAlwaysClassic() {
        // Classic selection is unaffected by any gate.
        XCTAssertEqual(VisualizerModeResolver.effectiveMode(
            selected: .classic, reduceMotion: true, disableVisualizer: true), .classic)
        XCTAssertEqual(VisualizerModeResolver.effectiveMode(
            selected: .classic, reduceMotion: false, disableVisualizer: false), .classic)
    }
}
