import XCTest
@testable import Vibrdrome

/// Phase 2D: Swift-managed preset ordering. Pure logic — exercised with injected
/// preset lists (no bundle, GL, or UIKit).
final class ProjectMPresetLibraryTests: XCTestCase {

    private func preset(_ id: String) -> ProjectMPreset {
        ProjectMPreset(id: id, url: URL(fileURLWithPath: "/tmp/\(id).milk"))
    }

    private func library(_ ids: [String]) -> ProjectMPresetLibrary {
        ProjectMPresetLibrary(presets: ids.map(preset))
    }

    // MARK: - displayName

    func testDisplayNameStripsPrefixAndCapitalizes() {
        XCTAssertEqual(preset("vibrdrome_plasma").displayName, "Plasma")
        XCTAssertEqual(preset("vibrdrome_kaleidoscope").displayName, "Kaleidoscope")
        XCTAssertEqual(preset("vibrdrome_tunnel").displayName, "Tunnel")
    }

    func testDisplayNameWithoutPrefix() {
        XCTAssertEqual(preset("neon_tunnel").displayName, "Neon Tunnel")
    }

    // MARK: - next / previous (wrap)

    func testNextWraps() {
        let lib = library(["a", "b", "c"])
        XCTAssertEqual(lib.next(after: "a")?.id, "b")
        XCTAssertEqual(lib.next(after: "c")?.id, "a")        // wrap
        XCTAssertEqual(lib.next(after: nil)?.id, "a")        // nil → first
        XCTAssertEqual(lib.next(after: "missing")?.id, "a")  // unknown → first
    }

    func testPreviousWraps() {
        let lib = library(["a", "b", "c"])
        XCTAssertEqual(lib.previous(before: "b")?.id, "a")
        XCTAssertEqual(lib.previous(before: "a")?.id, "c")   // wrap
    }

    // MARK: - random

    func testRandomNeverReturnsCurrentWhenMultiple() {
        let lib = library(["a", "b", "c"])
        for _ in 0..<50 {
            XCTAssertNotEqual(lib.random(excluding: "a")?.id, "a")
        }
    }

    func testRandomReturnsSinglePreset() {
        let lib = library(["only"])
        XCTAssertEqual(lib.random(excluding: "only")?.id, "only")
    }

    // MARK: - edges

    func testEmptyLibrary() {
        let lib = library([])
        XCTAssertTrue(lib.isEmpty)
        XCTAssertNil(lib.next(after: nil))
        XCTAssertNil(lib.previous(before: nil))
        XCTAssertNil(lib.random(excluding: nil))
        XCTAssertNil(lib.preset(id: "a"))
    }

    func testSinglePresetNextPreviousReturnItself() {
        let lib = library(["only"])
        XCTAssertEqual(lib.next(after: "only")?.id, "only")
        XCTAssertEqual(lib.previous(before: "only")?.id, "only")
    }

    func testPresetLookup() {
        let lib = library(["a", "b"])
        XCTAssertEqual(lib.preset(id: "b")?.id, "b")
        XCTAssertNil(lib.preset(id: nil))
        XCTAssertNil(lib.preset(id: "x"))
    }
}
