import Testing
import Foundation
@testable import Vibrdrome

/// Focused regression tests for the "Search in Albums" list-driving fix.
///
/// Bug: typing in the Albums search bar fetched results into `searchResults`, but the
/// list/grid kept rendering `indexedAlbums`, so search appeared to do nothing. The fix
/// routes the displayed list through `displayedIndexedAlbums`, which returns
/// `searchResults` while a query is active and the browsed list otherwise.
@MainActor
struct AlbumsSearchDisplayTests {

    private func makeAlbum(id: String, name: String = "Album") -> Album {
        Album(
            id: id, name: name, artist: nil, artistId: nil,
            artists: nil, displayArtist: nil,
            coverArt: nil, songCount: nil, duration: nil, playCount: nil,
            year: nil, genre: nil, genres: nil, starred: nil, played: nil,
            created: nil, userRating: nil, song: nil, replayGain: nil,
            musicBrainzId: nil, recordLabels: nil,
            version: nil, releaseTypes: nil, moods: nil, sortName: nil,
            originalReleaseDate: nil, releaseDate: nil,
            isCompilation: nil, explicitStatus: nil, discTitles: nil
        )
    }

    private func makeModel() -> AlbumsViewModel {
        AlbumsViewModel(listType: .alphabeticalByName)
    }

    @Test func showsBrowseListWhenNoSearch() {
        let model = makeModel()
        model.indexedAlbums = [(0, makeAlbum(id: "a")), (1, makeAlbum(id: "b"))]
        model.searchResults = [makeAlbum(id: "z")]  // stale — must be ignored when not searching
        #expect(model.isSearchActive == false)
        #expect(model.displayedIndexedAlbums.map(\.element.id) == ["a", "b"])
    }

    @Test func showsSearchResultsWhenActive() {
        let model = makeModel()
        model.indexedAlbums = [(0, makeAlbum(id: "a")), (1, makeAlbum(id: "b"))]
        model.searchResults = [makeAlbum(id: "s1"), makeAlbum(id: "s2")]
        model.searchQuery = "ab"
        #expect(model.isSearchActive == true)
        #expect(model.displayedIndexedAlbums.map(\.element.id) == ["s1", "s2"])
    }

    @Test func searchResultsAreReindexedFromZero() {
        let model = makeModel()
        model.searchResults = [makeAlbum(id: "s1"), makeAlbum(id: "s2"), makeAlbum(id: "s3")]
        model.searchQuery = "query"
        #expect(model.displayedIndexedAlbums.map(\.offset) == [0, 1, 2])
    }

    @Test func shortOrWhitespaceQueryIsNotActive() {
        let model = makeModel()
        model.searchQuery = ""
        #expect(model.isSearchActive == false)
        model.searchQuery = "a"
        #expect(model.isSearchActive == false)
        model.searchQuery = "   "
        #expect(model.isSearchActive == false)
        model.searchQuery = "ab"
        #expect(model.isSearchActive == true)
    }

    @Test func emptyResultsWhileActiveShowsEmptyList() {
        let model = makeModel()
        model.indexedAlbums = [(0, makeAlbum(id: "a"))]
        model.searchQuery = "zzz"
        model.searchResults = []
        #expect(model.isSearchActive == true)
        #expect(model.displayedIndexedAlbums.isEmpty)
    }
}
