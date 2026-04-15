import Testing
@testable import Vibrdrome

struct LibraryFilterTests {

    // MARK: - TriState

    @Test func triStateAllCases() {
        #expect(TriState.allCases == [.none, .yes, .no])
    }

    @Test func triStateRawValues() {
        #expect(TriState.none.rawValue == "none")
        #expect(TriState.yes.rawValue == "yes")
        #expect(TriState.no.rawValue == "no")
    }

    // MARK: - LibraryFilter initial state

    @Test func initialStateIsInactive() {
        let filter = LibraryFilter()
        #expect(!filter.isActive)
        #expect(filter.activeFilterCount == 0)
        #expect(filter.isFavorited == .none)
        #expect(filter.isRated == .none)
        #expect(!filter.isRecentlyPlayed)
        #expect(filter.selectedArtistIds.isEmpty)
        #expect(filter.selectedGenres.isEmpty)
        #expect(filter.selectedLabels.isEmpty)
        #expect(filter.year == nil)
    }

    // MARK: - isActive detection

    @Test func isActiveWhenFavoritedSet() {
        let filter = LibraryFilter()
        filter.isFavorited = .yes
        #expect(filter.isActive)
        #expect(filter.activeFilterCount == 1)
    }

    @Test func isActiveWhenRatedSet() {
        let filter = LibraryFilter()
        filter.isRated = .no
        #expect(filter.isActive)
        #expect(filter.activeFilterCount == 1)
    }

    @Test func isActiveWhenRecentlyPlayedSet() {
        let filter = LibraryFilter()
        filter.isRecentlyPlayed = true
        #expect(filter.isActive)
        #expect(filter.activeFilterCount == 1)
    }

    @Test func isActiveWhenArtistsSelected() {
        let filter = LibraryFilter()
        filter.selectedArtistIds = ["artist-1"]
        #expect(filter.isActive)
        #expect(filter.activeFilterCount == 1)
    }

    @Test func isActiveWhenGenresSelected() {
        let filter = LibraryFilter()
        filter.selectedGenres = ["Electronic", "Jazz"]
        #expect(filter.isActive)
        #expect(filter.activeFilterCount == 1)
    }

    @Test func isActiveWhenLabelsSelected() {
        let filter = LibraryFilter()
        filter.selectedLabels = ["Sony Music"]
        #expect(filter.isActive)
        #expect(filter.activeFilterCount == 1)
    }

    @Test func isActiveWhenYearSet() {
        let filter = LibraryFilter()
        filter.year = 2024
        #expect(filter.isActive)
        #expect(filter.activeFilterCount == 1)
    }

    // MARK: - activeFilterCount with multiple filters

    @Test func multipleFiltersCountCorrectly() {
        let filter = LibraryFilter()
        filter.isFavorited = .yes
        filter.isRated = .yes
        filter.isRecentlyPlayed = true
        filter.selectedArtistIds = ["a1"]
        filter.selectedGenres = ["Rock"]
        filter.selectedLabels = ["Atlantic"]
        filter.year = 2020
        #expect(filter.activeFilterCount == 7)
    }

    // MARK: - Reset

    @Test func resetClearsAllFilters() {
        let filter = LibraryFilter()
        filter.isFavorited = .yes
        filter.isRated = .no
        filter.isRecentlyPlayed = true
        filter.selectedArtistIds = ["a1", "a2"]
        filter.selectedGenres = ["Rock"]
        filter.selectedLabels = ["Def Jam"]
        filter.year = 1997

        filter.reset()

        #expect(!filter.isActive)
        #expect(filter.activeFilterCount == 0)
        #expect(filter.isFavorited == .none)
        #expect(filter.isRated == .none)
        #expect(!filter.isRecentlyPlayed)
        #expect(filter.selectedArtistIds.isEmpty)
        #expect(filter.selectedGenres.isEmpty)
        #expect(filter.selectedLabels.isEmpty)
        #expect(filter.year == nil)
    }

    // MARK: - TriState none does not count as active

    @Test func triStateNoneIsNotActive() {
        let filter = LibraryFilter()
        filter.isFavorited = .none
        filter.isRated = .none
        #expect(!filter.isActive)
        #expect(filter.activeFilterCount == 0)
    }
}
