import Testing
import Foundation
@testable import Vibrdrome

struct SubsonicEndpointsTests {

    // MARK: - Helpers

    private func findQueryItem(_ items: [URLQueryItem], name: String) -> String? {
        items.first(where: { $0.name == name })?.value
    }

    private func queryItemValues(_ items: [URLQueryItem], name: String) -> [String] {
        items.filter { $0.name == name }.compactMap(\.value)
    }

    // MARK: - Path Tests

    @Test func pingPath() {
        #expect(SubsonicEndpoint.ping.path == "/rest/ping")
    }

    @Test func getArtistsPath() {
        #expect(SubsonicEndpoint.getArtists().path == "/rest/getArtists")
    }

    @Test func getArtistPath() {
        #expect(SubsonicEndpoint.getArtist(id: "abc").path == "/rest/getArtist")
    }

    @Test func getAlbumPath() {
        #expect(SubsonicEndpoint.getAlbum(id: "99").path == "/rest/getAlbum")
    }

    @Test func search3Path() {
        #expect(SubsonicEndpoint.search3(query: "test").path == "/rest/search3")
    }

    @Test func streamPath() {
        #expect(SubsonicEndpoint.stream(id: "1").path == "/rest/stream")
    }

    @Test func getCoverArtPath() {
        #expect(SubsonicEndpoint.getCoverArt(id: "1").path == "/rest/getCoverArt")
    }

    @Test func getPlaylistsPath() {
        #expect(SubsonicEndpoint.getPlaylists.path == "/rest/getPlaylists")
    }

    @Test func getSimilarSongs2Path() {
        #expect(SubsonicEndpoint.getSimilarSongs2(id: "1").path == "/rest/getSimilarSongs2")
    }

    @Test func getTopSongsPath() {
        #expect(SubsonicEndpoint.getTopSongs(artist: "Muse").path == "/rest/getTopSongs")
    }

    @Test func getMusicFoldersPath() {
        #expect(SubsonicEndpoint.getMusicFolders.path == "/rest/getMusicFolders")
    }

    @Test func getMusicDirectoryPath() {
        #expect(SubsonicEndpoint.getMusicDirectory(id: "5").path == "/rest/getMusicDirectory")
    }

    @Test func allPathsStartWithRest() {
        let endpoints: [SubsonicEndpoint] = [
            .ping,
            .getArtists(),
            .getArtist(id: "1"),
            .getAlbum(id: "1"),
            .getSong(id: "1"),
            .search3(query: "x"),
            .getAlbumList2(type: .random),
            .getRandomSongs(),
            .getStarred2(),
            .getGenres,
            .star(id: "1"),
            .unstar(id: "1"),
            .setRating(id: "1", rating: 3),
            .scrobble(id: "1"),
            .getPlaylists,
            .getPlaylist(id: "1"),
            .createPlaylist(name: "p", songIds: []),
            .updatePlaylist(id: "1"),
            .deletePlaylist(id: "1"),
            .stream(id: "1"),
            .download(id: "1"),
            .getCoverArt(id: "1"),
            .getLyricsBySongId(id: "1"),
            .getInternetRadioStations,
            .createInternetRadioStation(streamUrl: "http://x", name: "n"),
            .deleteInternetRadioStation(id: "1"),
            .getPlayQueue,
            .savePlayQueue(ids: ["1"]),
            .getBookmarks,
            .createBookmark(id: "1", position: 0),
            .deleteBookmark(id: "1"),
            .getSimilarSongs2(id: "1"),
            .getTopSongs(artist: "a"),
            .getMusicFolders,
            .getMusicDirectory(id: "1"),
        ]
        for endpoint in endpoints {
            #expect(endpoint.path.hasPrefix("/rest/"), "Path '\(endpoint.path)' should start with /rest/")
        }
    }

    // MARK: - Query Item Tests: Simple Endpoints

    @Test func pingHasNoQueryItems() {
        #expect(SubsonicEndpoint.ping.queryItems.isEmpty)
    }

    @Test func getArtistsWithNilMusicFolderIdHasEmptyItems() {
        let items = SubsonicEndpoint.getArtists(musicFolderId: nil).queryItems
        #expect(items.isEmpty)
    }

    @Test func getArtistsWithMusicFolderIdHasItem() {
        let items = SubsonicEndpoint.getArtists(musicFolderId: "7").queryItems
        #expect(findQueryItem(items, name: "musicFolderId") == "7")
    }

    @Test func getArtistIdQueryItem() {
        let items = SubsonicEndpoint.getArtist(id: "123").queryItems
        #expect(findQueryItem(items, name: "id") == "123")
        #expect(items.count == 1)
    }

    @Test func getAlbumIdQueryItem() {
        let items = SubsonicEndpoint.getAlbum(id: "456").queryItems
        #expect(findQueryItem(items, name: "id") == "456")
        #expect(items.count == 1)
    }

    @Test func getSongIdQueryItem() {
        let items = SubsonicEndpoint.getSong(id: "789").queryItems
        #expect(findQueryItem(items, name: "id") == "789")
        #expect(items.count == 1)
    }

    // MARK: - Query Item Tests: search3

    @Test func search3DefaultsHaveBaseItems() {
        let items = SubsonicEndpoint.search3(query: "hello").queryItems
        #expect(findQueryItem(items, name: "query") == "hello")
        #expect(findQueryItem(items, name: "artistCount") == "20")
        #expect(findQueryItem(items, name: "albumCount") == "20")
        #expect(findQueryItem(items, name: "songCount") == "20")
    }

    @Test func search3ZeroOffsetsNotIncluded() {
        let items = SubsonicEndpoint.search3(
            query: "test", artistOffset: 0, albumOffset: 0, songOffset: 0
        ).queryItems
        #expect(findQueryItem(items, name: "artistOffset") == nil)
        #expect(findQueryItem(items, name: "albumOffset") == nil)
        #expect(findQueryItem(items, name: "songOffset") == nil)
    }

    @Test func search3NonZeroOffsetsIncluded() {
        let items = SubsonicEndpoint.search3(
            query: "rock", artistCount: 10, albumCount: 15, songCount: 25,
            artistOffset: 5, albumOffset: 10, songOffset: 20
        ).queryItems
        #expect(findQueryItem(items, name: "artistOffset") == "5")
        #expect(findQueryItem(items, name: "albumOffset") == "10")
        #expect(findQueryItem(items, name: "songOffset") == "20")
        #expect(findQueryItem(items, name: "artistCount") == "10")
        #expect(findQueryItem(items, name: "albumCount") == "15")
        #expect(findQueryItem(items, name: "songCount") == "25")
    }

    // MARK: - Query Item Tests: getAlbumList2

    @Test func getAlbumList2BasicItems() {
        let items = SubsonicEndpoint.getAlbumList2(type: .newest, size: 50).queryItems
        #expect(findQueryItem(items, name: "type") == "newest")
        #expect(findQueryItem(items, name: "size") == "50")
    }

    @Test func getAlbumList2ZeroOffsetNotIncluded() {
        let items = SubsonicEndpoint.getAlbumList2(type: .random, size: 20, offset: 0).queryItems
        #expect(findQueryItem(items, name: "offset") == nil)
    }

    @Test func getAlbumList2NonZeroOffsetIncluded() {
        let items = SubsonicEndpoint.getAlbumList2(type: .random, size: 20, offset: 40).queryItems
        #expect(findQueryItem(items, name: "offset") == "40")
    }

    @Test func getAlbumList2OptionalYearAndGenre() {
        let items = SubsonicEndpoint.getAlbumList2(
            type: .byYear, size: 10, fromYear: 2000, toYear: 2020, genre: "Rock"
        ).queryItems
        #expect(findQueryItem(items, name: "fromYear") == "2000")
        #expect(findQueryItem(items, name: "toYear") == "2020")
        #expect(findQueryItem(items, name: "genre") == "Rock")
    }

    @Test func getAlbumList2NilOptionalsOmitted() {
        let items = SubsonicEndpoint.getAlbumList2(type: .frequent, size: 10).queryItems
        #expect(findQueryItem(items, name: "fromYear") == nil)
        #expect(findQueryItem(items, name: "toYear") == nil)
        #expect(findQueryItem(items, name: "genre") == nil)
    }

    // MARK: - Query Item Tests: getRandomSongs

    @Test func getRandomSongsWithGenre() {
        let items = SubsonicEndpoint.getRandomSongs(size: 30, genre: "Jazz").queryItems
        #expect(findQueryItem(items, name: "size") == "30")
        #expect(findQueryItem(items, name: "genre") == "Jazz")
    }

    @Test func getRandomSongsWithoutGenre() {
        let items = SubsonicEndpoint.getRandomSongs(size: 20).queryItems
        #expect(findQueryItem(items, name: "size") == "20")
        #expect(findQueryItem(items, name: "genre") == nil)
    }

    @Test func getRandomSongsWithYearRange() {
        let items = SubsonicEndpoint.getRandomSongs(
            size: 10, fromYear: 1990, toYear: 1999
        ).queryItems
        #expect(findQueryItem(items, name: "fromYear") == "1990")
        #expect(findQueryItem(items, name: "toYear") == "1999")
    }

    // MARK: - Query Item Tests: star / unstar

    @Test func starWithSongIdOnly() {
        let items = SubsonicEndpoint.star(id: "s1").queryItems
        #expect(findQueryItem(items, name: "id") == "s1")
        #expect(findQueryItem(items, name: "albumId") == nil)
        #expect(findQueryItem(items, name: "artistId") == nil)
    }

    @Test func starWithAlbumIdOnly() {
        let items = SubsonicEndpoint.star(albumId: "a1").queryItems
        #expect(findQueryItem(items, name: "id") == nil)
        #expect(findQueryItem(items, name: "albumId") == "a1")
        #expect(findQueryItem(items, name: "artistId") == nil)
    }

    @Test func unstarWithArtistIdOnly() {
        let items = SubsonicEndpoint.unstar(artistId: "ar1").queryItems
        #expect(findQueryItem(items, name: "id") == nil)
        #expect(findQueryItem(items, name: "albumId") == nil)
        #expect(findQueryItem(items, name: "artistId") == "ar1")
    }

    @Test func unstarWithMultipleIds() {
        let items = SubsonicEndpoint.unstar(id: "s1", albumId: "a1", artistId: "ar1").queryItems
        #expect(findQueryItem(items, name: "id") == "s1")
        #expect(findQueryItem(items, name: "albumId") == "a1")
        #expect(findQueryItem(items, name: "artistId") == "ar1")
    }

    @Test func starAllNilReturnsEmpty() {
        let items = SubsonicEndpoint.star().queryItems
        #expect(items.isEmpty)
    }

    // MARK: - Query Item Tests: scrobble

    @Test func scrobbleIdAndSubmissionAlwaysPresent() {
        let items = SubsonicEndpoint.scrobble(id: "song42").queryItems
        #expect(findQueryItem(items, name: "id") == "song42")
        #expect(findQueryItem(items, name: "submission") == "true")
        #expect(findQueryItem(items, name: "time") == nil)
    }

    @Test func scrobbleWithTimeIncludesTime() {
        let items = SubsonicEndpoint.scrobble(id: "s1", time: 1700000000, submission: false).queryItems
        #expect(findQueryItem(items, name: "id") == "s1")
        #expect(findQueryItem(items, name: "submission") == "false")
        #expect(findQueryItem(items, name: "time") == "1700000000")
    }

    // MARK: - Query Item Tests: createPlaylist

    @Test func createPlaylistNameAndMultipleSongIds() {
        let items = SubsonicEndpoint.createPlaylist(
            name: "My Playlist", songIds: ["a", "b", "c"]
        ).queryItems
        #expect(findQueryItem(items, name: "name") == "My Playlist")
        let songIds = queryItemValues(items, name: "songId")
        #expect(songIds == ["a", "b", "c"])
    }

    @Test func createPlaylistEmptySongIds() {
        let items = SubsonicEndpoint.createPlaylist(name: "Empty", songIds: []).queryItems
        #expect(findQueryItem(items, name: "name") == "Empty")
        #expect(queryItemValues(items, name: "songId").isEmpty)
    }

    // MARK: - Query Item Tests: updatePlaylist

    @Test func updatePlaylistMinimal() {
        let items = SubsonicEndpoint.updatePlaylist(id: "pl1").queryItems
        #expect(findQueryItem(items, name: "playlistId") == "pl1")
        #expect(findQueryItem(items, name: "name") == nil)
        #expect(findQueryItem(items, name: "comment") == nil)
        #expect(findQueryItem(items, name: "public") == nil)
        #expect(queryItemValues(items, name: "songIdToAdd").isEmpty)
        #expect(queryItemValues(items, name: "songIndexToRemove").isEmpty)
    }

    @Test func updatePlaylistFull() {
        let items = SubsonicEndpoint.updatePlaylist(
            id: "pl1", name: "Renamed", comment: "Great mix", isPublic: true,
            songIdsToAdd: ["s1", "s2"], songIndexesToRemove: [0, 3]
        ).queryItems
        #expect(findQueryItem(items, name: "playlistId") == "pl1")
        #expect(findQueryItem(items, name: "name") == "Renamed")
        #expect(findQueryItem(items, name: "comment") == "Great mix")
        #expect(findQueryItem(items, name: "public") == "true")
        #expect(queryItemValues(items, name: "songIdToAdd") == ["s1", "s2"])
        #expect(queryItemValues(items, name: "songIndexToRemove") == ["0", "3"])
    }

    @Test func updatePlaylistPublicFalse() {
        let items = SubsonicEndpoint.updatePlaylist(id: "pl2", isPublic: false).queryItems
        #expect(findQueryItem(items, name: "public") == "false")
    }

    // MARK: - Query Item Tests: stream

    @Test func streamIdOnly() {
        let items = SubsonicEndpoint.stream(id: "track1").queryItems
        #expect(findQueryItem(items, name: "id") == "track1")
        #expect(findQueryItem(items, name: "maxBitRate") == nil)
        #expect(findQueryItem(items, name: "format") == nil)
    }

    @Test func streamWithBitRateAndFormat() {
        let items = SubsonicEndpoint.stream(id: "track1", maxBitRate: 320, format: "mp3").queryItems
        #expect(findQueryItem(items, name: "id") == "track1")
        #expect(findQueryItem(items, name: "maxBitRate") == "320")
        #expect(findQueryItem(items, name: "format") == "mp3")
    }

    // MARK: - Query Item Tests: getCoverArt

    @Test func getCoverArtIdOnly() {
        let items = SubsonicEndpoint.getCoverArt(id: "al-5").queryItems
        #expect(findQueryItem(items, name: "id") == "al-5")
        #expect(findQueryItem(items, name: "size") == nil)
    }

    @Test func getCoverArtWithSize() {
        let items = SubsonicEndpoint.getCoverArt(id: "al-5", size: 300).queryItems
        #expect(findQueryItem(items, name: "id") == "al-5")
        #expect(findQueryItem(items, name: "size") == "300")
    }

    // MARK: - Query Item Tests: savePlayQueue

    @Test func savePlayQueueMultipleIds() {
        let items = SubsonicEndpoint.savePlayQueue(ids: ["x", "y", "z"]).queryItems
        let ids = queryItemValues(items, name: "id")
        #expect(ids == ["x", "y", "z"])
        #expect(findQueryItem(items, name: "current") == nil)
        #expect(findQueryItem(items, name: "position") == nil)
    }

    @Test func savePlayQueueWithCurrentAndPosition() {
        let items = SubsonicEndpoint.savePlayQueue(
            ids: ["a", "b"], current: "a", position: 45000
        ).queryItems
        let ids = queryItemValues(items, name: "id")
        #expect(ids == ["a", "b"])
        #expect(findQueryItem(items, name: "current") == "a")
        #expect(findQueryItem(items, name: "position") == "45000")
    }

    // MARK: - Query Item Tests: createBookmark

    @Test func createBookmarkIdAndPositionAlwaysPresent() {
        let items = SubsonicEndpoint.createBookmark(id: "bk1", position: 120000).queryItems
        #expect(findQueryItem(items, name: "id") == "bk1")
        #expect(findQueryItem(items, name: "position") == "120000")
        #expect(findQueryItem(items, name: "comment") == nil)
    }

    @Test func createBookmarkWithComment() {
        let items = SubsonicEndpoint.createBookmark(
            id: "bk1", position: 60000, comment: "Left off here"
        ).queryItems
        #expect(findQueryItem(items, name: "id") == "bk1")
        #expect(findQueryItem(items, name: "position") == "60000")
        #expect(findQueryItem(items, name: "comment") == "Left off here")
    }

    // MARK: - Query Item Tests: getSimilarSongs2

    @Test func getSimilarSongs2IdAndCount() {
        let items = SubsonicEndpoint.getSimilarSongs2(id: "sim1", count: 30).queryItems
        #expect(findQueryItem(items, name: "id") == "sim1")
        #expect(findQueryItem(items, name: "count") == "30")
        #expect(items.count == 2)
    }

    // MARK: - Query Item Tests: getTopSongs

    @Test func getTopSongsArtistAndCount() {
        let items = SubsonicEndpoint.getTopSongs(artist: "Radiohead", count: 25).queryItems
        #expect(findQueryItem(items, name: "artist") == "Radiohead")
        #expect(findQueryItem(items, name: "count") == "25")
        #expect(items.count == 2)
    }

    // MARK: - Query Item Tests: setRating

    @Test func setRatingIdAndRating() {
        let items = SubsonicEndpoint.setRating(id: "r1", rating: 5).queryItems
        #expect(findQueryItem(items, name: "id") == "r1")
        #expect(findQueryItem(items, name: "rating") == "5")
        #expect(items.count == 2)
    }

    // MARK: - AlbumListType rawValue Tests

    @Test func albumListTypeRawValues() {
        #expect(AlbumListType.random.rawValue == "random")
        #expect(AlbumListType.newest.rawValue == "newest")
        #expect(AlbumListType.frequent.rawValue == "frequent")
        #expect(AlbumListType.recent.rawValue == "recent")
        #expect(AlbumListType.starred.rawValue == "starred")
        #expect(AlbumListType.alphabeticalByName.rawValue == "alphabeticalByName")
        #expect(AlbumListType.alphabeticalByArtist.rawValue == "alphabeticalByArtist")
        #expect(AlbumListType.byYear.rawValue == "byYear")
        #expect(AlbumListType.byGenre.rawValue == "byGenre")
    }

    // MARK: - No Query Items Endpoints

    @Test func noQueryItemEndpoints() {
        let emptyQueryEndpoints: [SubsonicEndpoint] = [
            .ping,
            .getStarred2(),
            .getGenres,
            .getPlaylists,
            .getInternetRadioStations,
            .getPlayQueue,
            .getBookmarks,
            .getMusicFolders,
        ]
        for endpoint in emptyQueryEndpoints {
            #expect(endpoint.queryItems.isEmpty, "\(endpoint) should have no query items")
        }
    }

    // MARK: - musicFolderId on New Endpoints

    @Test func getAlbumList2WithMusicFolderId() {
        let items = SubsonicEndpoint.getAlbumList2(
            type: .newest, size: 10, musicFolderId: "3"
        ).queryItems
        #expect(findQueryItem(items, name: "musicFolderId") == "3")
    }

    @Test func getAlbumList2WithoutMusicFolderId() {
        let items = SubsonicEndpoint.getAlbumList2(type: .newest, size: 10).queryItems
        #expect(findQueryItem(items, name: "musicFolderId") == nil)
    }

    @Test func getRandomSongsWithMusicFolderId() {
        let items = SubsonicEndpoint.getRandomSongs(size: 20, musicFolderId: "5").queryItems
        #expect(findQueryItem(items, name: "musicFolderId") == "5")
    }

    @Test func getStarred2WithMusicFolderId() {
        let items = SubsonicEndpoint.getStarred2(musicFolderId: "2").queryItems
        #expect(findQueryItem(items, name: "musicFolderId") == "2")
    }

    @Test func getStarred2WithoutMusicFolderId() {
        let items = SubsonicEndpoint.getStarred2().queryItems
        #expect(items.isEmpty)
    }

    @Test func search3WithMusicFolderId() {
        let items = SubsonicEndpoint.search3(query: "test", musicFolderId: "4").queryItems
        #expect(findQueryItem(items, name: "musicFolderId") == "4")
    }

    @Test func search3WithoutMusicFolderId() {
        let items = SubsonicEndpoint.search3(query: "test").queryItems
        #expect(findQueryItem(items, name: "musicFolderId") == nil)
    }
}
