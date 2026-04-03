import Testing
import Foundation
@testable import Vibrdrome

struct LibraryLayoutConfigTests {

    // MARK: - Default Config

    @Test func defaultConfigHasAllPills() {
        let config = LibraryLayoutConfig.default
        #expect(config.visiblePills.count == LibraryPill.allCases.count)
    }

    @Test func defaultConfigHasAllCarousels() {
        let config = LibraryLayoutConfig.default
        #expect(config.visibleCarousels.count == LibraryCarousel.allCases.count)
    }

    @Test func defaultConfigHasNoHiddenItems() {
        let config = LibraryLayoutConfig.default
        #expect(config.hiddenPills.isEmpty)
        #expect(config.hiddenCarousels.isEmpty)
    }

    // MARK: - Hiding Items

    @Test func hidingPillMovesToHidden() {
        var config = LibraryLayoutConfig.default
        config.visiblePills.removeAll { $0 == .favorites }
        #expect(!config.visiblePills.contains(.favorites))
        #expect(config.hiddenPills.contains(.favorites))
    }

    @Test func hidingCarouselMovesToHidden() {
        var config = LibraryLayoutConfig.default
        config.visibleCarousels.removeAll { $0 == .rediscover }
        #expect(!config.visibleCarousels.contains(.rediscover))
        #expect(config.hiddenCarousels.contains(.rediscover))
    }

    // MARK: - Encoding / Decoding

    @Test func encodingAndDecodingPreservesConfig() throws {
        var config = LibraryLayoutConfig.default
        config.visiblePills = [.favorites, .artists, .albums]
        config.visibleCarousels = [.recentlyAdded, .randomPicks]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(LibraryLayoutConfig.self, from: data)

        #expect(decoded.visiblePills == [.favorites, .artists, .albums])
        #expect(decoded.visibleCarousels == [.recentlyAdded, .randomPicks])
    }

    // MARK: - Pill Properties

    @Test func allPillsHaveTitles() {
        for pill in LibraryPill.allCases {
            #expect(!pill.title.isEmpty)
        }
    }

    @Test func allPillsHaveIcons() {
        for pill in LibraryPill.allCases {
            #expect(!pill.icon.isEmpty)
        }
    }

    @Test func allCarouselsHaveTitles() {
        for carousel in LibraryCarousel.allCases {
            #expect(!carousel.title.isEmpty)
        }
    }
}
