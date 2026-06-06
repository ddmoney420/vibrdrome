import XCTest
@testable import Vibrdrome

/// Phase 2C: pure gating logic for the Classic/MilkDrop mode picker. MilkDrop is
/// suppressed by Reduce Motion, Disable Visualizer, and the iOS simulator; the
/// effective mode falls back to Classic whenever MilkDrop is selected but not
/// currently selectable.
final class VisualizerModeResolverTests: XCTestCase {

    // MARK: - milkdropSelectable

    func testSelectableWhenAllClear() {
        XCTAssertTrue(VisualizerModeResolver.milkdropSelectable(
            reduceMotion: false, disableVisualizer: false, isSimulator: false))
    }

    func testNotSelectableUnderReduceMotion() {
        XCTAssertFalse(VisualizerModeResolver.milkdropSelectable(
            reduceMotion: true, disableVisualizer: false, isSimulator: false))
    }

    func testNotSelectableWhenVisualizerDisabled() {
        XCTAssertFalse(VisualizerModeResolver.milkdropSelectable(
            reduceMotion: false, disableVisualizer: true, isSimulator: false))
    }

    func testNotSelectableOnSimulator() {
        XCTAssertFalse(VisualizerModeResolver.milkdropSelectable(
            reduceMotion: false, disableVisualizer: false, isSimulator: true))
    }

    func testSimulatorGateBeatsOtherwiseClear() {
        // Simulator hard-gate wins even with everything else permitting.
        XCTAssertFalse(VisualizerModeResolver.milkdropSelectable(
            reduceMotion: false, disableVisualizer: false, isSimulator: true))
    }

    // MARK: - effectiveMode

    func testEffectiveMilkdropWhenSelectedAndClear() {
        XCTAssertEqual(VisualizerModeResolver.effectiveMode(
            selected: .milkdrop, reduceMotion: false, disableVisualizer: false, isSimulator: false), .milkdrop)
    }

    func testEffectiveFallsBackUnderReduceMotion() {
        XCTAssertEqual(VisualizerModeResolver.effectiveMode(
            selected: .milkdrop, reduceMotion: true, disableVisualizer: false, isSimulator: false), .classic)
    }

    func testEffectiveFallsBackOnSimulator() {
        XCTAssertEqual(VisualizerModeResolver.effectiveMode(
            selected: .milkdrop, reduceMotion: false, disableVisualizer: false, isSimulator: true), .classic)
    }

    func testEffectiveFallsBackWhenVisualizerDisabled() {
        XCTAssertEqual(VisualizerModeResolver.effectiveMode(
            selected: .milkdrop, reduceMotion: false, disableVisualizer: true, isSimulator: false), .classic)
    }

    func testEffectiveClassicAlwaysClassic() {
        // Classic selection is unaffected by any gate.
        XCTAssertEqual(VisualizerModeResolver.effectiveMode(
            selected: .classic, reduceMotion: true, disableVisualizer: true, isSimulator: true), .classic)
        XCTAssertEqual(VisualizerModeResolver.effectiveMode(
            selected: .classic, reduceMotion: false, disableVisualizer: false, isSimulator: false), .classic)
    }
}
