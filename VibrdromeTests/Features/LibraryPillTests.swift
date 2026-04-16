import Testing
import Foundation
@testable import Vibrdrome

struct LibraryPillTests {

    @Test func playHistoryPillExists() {
        #expect(LibraryPill.playHistory.title == "Play History")
        #expect(LibraryPill.playHistory.icon == "clock.arrow.circlepath")
        #expect(LibraryPill.playHistory.color == "purple")
    }

    @Test func allPillsCount() {
        // 14 original + 1 playHistory + 1 smartPlaylists + 1 jukebox = 17
        #expect(LibraryPill.allCases.count == 17)
    }

    @Test func allCarouselsCount() {
        #expect(LibraryCarousel.allCases.count == 6)
    }

    @Test func defaultConfigIncludesAllPills() {
        let config = LibraryLayoutConfig.default
        #expect(config.visiblePills.count == LibraryPill.allCases.count)
        #expect(config.hiddenPills.isEmpty)
    }

    @Test func hidingPillShowsInHidden() {
        var config = LibraryLayoutConfig.default
        config.visiblePills.removeAll { $0 == .playHistory }
        #expect(config.hiddenPills.contains(.playHistory))
        #expect(!config.visiblePills.contains(.playHistory))
    }

    @Test func reorderingPreserved() throws {
        var config = LibraryLayoutConfig.default
        let first = config.visiblePills[0]
        let second = config.visiblePills[1]
        config.visiblePills.swapAt(0, 1)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(LibraryLayoutConfig.self, from: data)
        #expect(decoded.visiblePills[0] == second)
        #expect(decoded.visiblePills[1] == first)
    }
}
