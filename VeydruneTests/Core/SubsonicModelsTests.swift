import Testing
import Foundation
@testable import Veydrune

struct SubsonicModelsTests {

    // MARK: - Song Decoding

    @Test func songMinimalFields() throws {
        let json = """
        {"id":"1","title":"Test Song"}
        """.data(using: .utf8)!
        let song = try JSONDecoder().decode(Song.self, from: json)
        #expect(song.id == "1")
        #expect(song.title == "Test Song")
        #expect(song.artist == nil)
        #expect(song.album == nil)
        #expect(song.track == nil)
        #expect(song.duration == nil)
        #expect(song.starred == nil)
    }

    @Test func songAllFields() throws {
        let json = """
        {
            "id": "42",
            "parent": "10",
            "title": "Starlight",
            "album": "Black Holes",
            "artist": "Muse",
            "albumId": "al-1",
            "artistId": "ar-1",
            "track": 3,
            "year": 2006,
            "genre": "Alternative Rock",
            "coverArt": "cov-42",
            "size": 8675309,
            "contentType": "audio/flac",
            "suffix": "flac",
            "duration": 240,
            "bitRate": 320,
            "path": "Muse/Black Holes/03 - Starlight.flac",
            "discNumber": 1,
            "created": "2024-01-15T10:30:00.000Z",
            "starred": "2024-06-01T12:00:00.000Z",
            "bpm": 120,
            "musicBrainzId": "mbid-abc-123",
            "replayGain": {
                "trackGain": -6.5,
                "albumGain": -7.2,
                "trackPeak": 0.98,
                "albumPeak": 1.0,
                "baseGain": 0.0
            }
        }
        """.data(using: .utf8)!
        let song = try JSONDecoder().decode(Song.self, from: json)
        #expect(song.id == "42")
        #expect(song.parent == "10")
        #expect(song.title == "Starlight")
        #expect(song.album == "Black Holes")
        #expect(song.artist == "Muse")
        #expect(song.albumId == "al-1")
        #expect(song.artistId == "ar-1")
        #expect(song.track == 3)
        #expect(song.year == 2006)
        #expect(song.genre == "Alternative Rock")
        #expect(song.coverArt == "cov-42")
        #expect(song.size == 8675309)
        #expect(song.contentType == "audio/flac")
        #expect(song.suffix == "flac")
        #expect(song.duration == 240)
        #expect(song.bitRate == 320)
        #expect(song.path == "Muse/Black Holes/03 - Starlight.flac")
        #expect(song.discNumber == 1)
        #expect(song.created == "2024-01-15T10:30:00.000Z")
        #expect(song.starred == "2024-06-01T12:00:00.000Z")
        #expect(song.bpm == 120)
        #expect(song.musicBrainzId == "mbid-abc-123")
        #expect(song.replayGain != nil)
        #expect(song.replayGain?.trackGain == -6.5)
        #expect(song.replayGain?.albumGain == -7.2)
        #expect(song.replayGain?.trackPeak == 0.98)
        #expect(song.replayGain?.albumPeak == 1.0)
        #expect(song.replayGain?.baseGain == 0.0)
    }

    @Test func songEmptyStringFields() throws {
        let json = """
        {"id":"1","title":"","artist":"","album":"","genre":""}
        """.data(using: .utf8)!
        let song = try JSONDecoder().decode(Song.self, from: json)
        #expect(song.id == "1")
        #expect(song.title == "")
        #expect(song.artist == "")
        #expect(song.album == "")
        #expect(song.genre == "")
    }

    @Test func songIdentifiable() throws {
        let json = """
        {"id":"unique-id-99","title":"Track"}
        """.data(using: .utf8)!
        let song = try JSONDecoder().decode(Song.self, from: json)
        #expect(song.id == "unique-id-99")
    }

    // MARK: - Album Decoding

    @Test func albumWithSongs() throws {
        let json = """
        {
            "id": "al-1",
            "name": "OK Computer",
            "artist": "Radiohead",
            "artistId": "ar-2",
            "coverArt": "cov-al-1",
            "songCount": 2,
            "duration": 600,
            "year": 1997,
            "genre": "Alternative",
            "starred": "2024-03-01T00:00:00Z",
            "created": "2023-12-25T00:00:00Z",
            "song": [
                {"id":"s1","title":"Airbag"},
                {"id":"s2","title":"Paranoid Android"}
            ]
        }
        """.data(using: .utf8)!
        let album = try JSONDecoder().decode(Album.self, from: json)
        #expect(album.id == "al-1")
        #expect(album.name == "OK Computer")
        #expect(album.artist == "Radiohead")
        #expect(album.artistId == "ar-2")
        #expect(album.coverArt == "cov-al-1")
        #expect(album.songCount == 2)
        #expect(album.duration == 600)
        #expect(album.year == 1997)
        #expect(album.genre == "Alternative")
        #expect(album.starred == "2024-03-01T00:00:00Z")
        #expect(album.created == "2023-12-25T00:00:00Z")
        #expect(album.song?.count == 2)
        #expect(album.song?[0].title == "Airbag")
        #expect(album.song?[1].title == "Paranoid Android")
    }

    @Test func albumWithSongArrayOmitted() throws {
        // Critical: Subsonic omits arrays rather than sending empty arrays
        let json = """
        {"id":"al-2","name":"Empty Album"}
        """.data(using: .utf8)!
        let album = try JSONDecoder().decode(Album.self, from: json)
        #expect(album.id == "al-2")
        #expect(album.name == "Empty Album")
        #expect(album.song == nil)
        #expect(album.artist == nil)
        #expect(album.songCount == nil)
    }

    @Test func albumMinimalFields() throws {
        let json = """
        {"id":"al-min","name":"Minimal"}
        """.data(using: .utf8)!
        let album = try JSONDecoder().decode(Album.self, from: json)
        #expect(album.id == "al-min")
        #expect(album.name == "Minimal")
        #expect(album.replayGain == nil)
    }

    // MARK: - Artist Decoding

    @Test func artistWithAlbums() throws {
        let json = """
        {
            "id": "ar-1",
            "name": "Pink Floyd",
            "coverArt": "cov-ar-1",
            "albumCount": 1,
            "starred": "2024-05-01T00:00:00Z",
            "album": [
                {"id":"al-10","name":"The Wall","songCount":26}
            ]
        }
        """.data(using: .utf8)!
        let artist = try JSONDecoder().decode(Artist.self, from: json)
        #expect(artist.id == "ar-1")
        #expect(artist.name == "Pink Floyd")
        #expect(artist.coverArt == "cov-ar-1")
        #expect(artist.albumCount == 1)
        #expect(artist.starred == "2024-05-01T00:00:00Z")
        #expect(artist.album?.count == 1)
        #expect(artist.album?[0].name == "The Wall")
    }

    @Test func artistWithoutAlbums() throws {
        // Albums array omitted when artist has no albums returned
        let json = """
        {"id":"ar-2","name":"Unknown Artist"}
        """.data(using: .utf8)!
        let artist = try JSONDecoder().decode(Artist.self, from: json)
        #expect(artist.id == "ar-2")
        #expect(artist.name == "Unknown Artist")
        #expect(artist.album == nil)
        #expect(artist.albumCount == nil)
        #expect(artist.coverArt == nil)
        #expect(artist.starred == nil)
    }

    // MARK: - Playlist Decoding

    @Test func playlistIsPublicMapping() throws {
        // CodingKey: "public" -> isPublic
        let json = """
        {
            "id": "pl-1",
            "name": "My Favorites",
            "songCount": 10,
            "duration": 3600,
            "public": true,
            "owner": "admin",
            "entry": [
                {"id":"s1","title":"Song One"}
            ]
        }
        """.data(using: .utf8)!
        let playlist = try JSONDecoder().decode(Playlist.self, from: json)
        #expect(playlist.id == "pl-1")
        #expect(playlist.name == "My Favorites")
        #expect(playlist.isPublic == true)
        #expect(playlist.owner == "admin")
        #expect(playlist.songCount == 10)
        #expect(playlist.duration == 3600)
        #expect(playlist.entry?.count == 1)
    }

    @Test func playlistPrivate() throws {
        let json = """
        {"id":"pl-2","name":"Private List","public":false}
        """.data(using: .utf8)!
        let playlist = try JSONDecoder().decode(Playlist.self, from: json)
        #expect(playlist.isPublic == false)
    }

    @Test func playlistWithoutEntries() throws {
        // entry array omitted when playlist has no songs
        let json = """
        {"id":"pl-3","name":"Empty Playlist"}
        """.data(using: .utf8)!
        let playlist = try JSONDecoder().decode(Playlist.self, from: json)
        #expect(playlist.id == "pl-3")
        #expect(playlist.entry == nil)
        #expect(playlist.isPublic == nil)
    }

    @Test func playlistWithTimestamps() throws {
        let json = """
        {
            "id": "pl-4",
            "name": "Timed",
            "created": "2024-01-01T00:00:00Z",
            "changed": "2024-06-15T12:30:00Z",
            "coverArt": "pl-cov-4"
        }
        """.data(using: .utf8)!
        let playlist = try JSONDecoder().decode(Playlist.self, from: json)
        #expect(playlist.created == "2024-01-01T00:00:00Z")
        #expect(playlist.changed == "2024-06-15T12:30:00Z")
        #expect(playlist.coverArt == "pl-cov-4")
    }

    // MARK: - SearchResult3 Decoding

    @Test func searchResult3AllPresent() throws {
        let json = """
        {
            "artist": [{"id":"ar-1","name":"Artist One"}],
            "album": [{"id":"al-1","name":"Album One"}],
            "song": [{"id":"s-1","title":"Song One"}]
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(SearchResult3.self, from: json)
        #expect(result.artist?.count == 1)
        #expect(result.album?.count == 1)
        #expect(result.song?.count == 1)
        #expect(result.artist?[0].name == "Artist One")
        #expect(result.album?[0].name == "Album One")
        #expect(result.song?[0].title == "Song One")
    }

    @Test func searchResult3AllOmitted() throws {
        // All arrays omitted when search returns nothing
        let json = """
        {}
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(SearchResult3.self, from: json)
        #expect(result.artist == nil)
        #expect(result.album == nil)
        #expect(result.song == nil)
    }

    @Test func searchResult3Mixed() throws {
        // Only some arrays present — others omitted (not empty)
        let json = """
        {
            "song": [{"id":"s-1","title":"Found Song"}]
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(SearchResult3.self, from: json)
        #expect(result.artist == nil)
        #expect(result.album == nil)
        #expect(result.song?.count == 1)
    }

    // MARK: - Genre Decoding

    @Test func genreBasic() throws {
        let json = """
        {"songCount":150,"albumCount":12,"value":"Rock"}
        """.data(using: .utf8)!
        let genre = try JSONDecoder().decode(Genre.self, from: json)
        #expect(genre.value == "Rock")
        #expect(genre.songCount == 150)
        #expect(genre.albumCount == 12)
        #expect(genre.id == "Rock")
    }

    @Test func genreMinimal() throws {
        let json = """
        {"value":"Electronic"}
        """.data(using: .utf8)!
        let genre = try JSONDecoder().decode(Genre.self, from: json)
        #expect(genre.value == "Electronic")
        #expect(genre.songCount == nil)
        #expect(genre.albumCount == nil)
    }

    // MARK: - InternetRadioStation Decoding

    @Test func radioStationWithHomePage() throws {
        let json = """
        {
            "id": "radio-1",
            "name": "Jazz FM",
            "streamUrl": "https://stream.jazzfm.com/live",
            "homePageUrl": "https://www.jazzfm.com"
        }
        """.data(using: .utf8)!
        let station = try JSONDecoder().decode(InternetRadioStation.self, from: json)
        #expect(station.id == "radio-1")
        #expect(station.name == "Jazz FM")
        #expect(station.streamUrl == "https://stream.jazzfm.com/live")
        #expect(station.homePageUrl == "https://www.jazzfm.com")
    }

    @Test func radioStationWithoutHomePage() throws {
        let json = """
        {"id":"radio-2","name":"Lo-Fi Beats","streamUrl":"https://lofi.stream/play"}
        """.data(using: .utf8)!
        let station = try JSONDecoder().decode(InternetRadioStation.self, from: json)
        #expect(station.id == "radio-2")
        #expect(station.name == "Lo-Fi Beats")
        #expect(station.streamUrl == "https://lofi.stream/play")
        #expect(station.homePageUrl == nil)
    }

    // MARK: - PlayQueue Decoding

    @Test func playQueueWithEntries() throws {
        let json = """
        {
            "current": "s-5",
            "position": 45000,
            "changed": "2024-08-01T12:00:00Z",
            "changedBy": "veydrune",
            "entry": [
                {"id":"s-4","title":"Previous"},
                {"id":"s-5","title":"Current"},
                {"id":"s-6","title":"Next"}
            ]
        }
        """.data(using: .utf8)!
        let pq = try JSONDecoder().decode(PlayQueue.self, from: json)
        #expect(pq.current == "s-5")
        #expect(pq.position == 45000)
        #expect(pq.changed == "2024-08-01T12:00:00Z")
        #expect(pq.changedBy == "veydrune")
        #expect(pq.entry?.count == 3)
        #expect(pq.entry?[1].title == "Current")
    }

    @Test func playQueueEmpty() throws {
        // Entries omitted when queue is empty
        let json = """
        {}
        """.data(using: .utf8)!
        let pq = try JSONDecoder().decode(PlayQueue.self, from: json)
        #expect(pq.current == nil)
        #expect(pq.position == nil)
        #expect(pq.entry == nil)
        #expect(pq.changed == nil)
        #expect(pq.changedBy == nil)
    }

    // MARK: - Bookmark Decoding

    @Test func bookmarkFull() throws {
        let json = """
        {
            "position": 120000,
            "username": "admin",
            "comment": "Left off here",
            "created": "2024-07-01T10:00:00Z",
            "changed": "2024-07-02T10:00:00Z",
            "entry": {"id":"s-99","title":"Long Track"}
        }
        """.data(using: .utf8)!
        let bookmark = try JSONDecoder().decode(Bookmark.self, from: json)
        #expect(bookmark.position == 120000)
        #expect(bookmark.username == "admin")
        #expect(bookmark.comment == "Left off here")
        #expect(bookmark.created == "2024-07-01T10:00:00Z")
        #expect(bookmark.changed == "2024-07-02T10:00:00Z")
        #expect(bookmark.entry?.id == "s-99")
        #expect(bookmark.entry?.title == "Long Track")
    }

    @Test func bookmarkWithoutComment() throws {
        let json = """
        {
            "position": 5000,
            "username": "user1",
            "created": "2024-08-01T00:00:00Z",
            "changed": "2024-08-01T00:00:00Z",
            "entry": {"id":"s-50","title":"Short Track"}
        }
        """.data(using: .utf8)!
        let bookmark = try JSONDecoder().decode(Bookmark.self, from: json)
        #expect(bookmark.comment == nil)
        #expect(bookmark.entry != nil)
    }

    @Test func bookmarkWithoutEntry() throws {
        let json = """
        {
            "position": 0,
            "username": "user2",
            "created": "2024-08-01T00:00:00Z",
            "changed": "2024-08-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let bookmark = try JSONDecoder().decode(Bookmark.self, from: json)
        #expect(bookmark.position == 0)
        #expect(bookmark.entry == nil)
        #expect(bookmark.comment == nil)
    }

    // MARK: - LyricsList / StructuredLyrics / LyricLine Decoding

    @Test func lyricsListSynced() throws {
        let json = """
        {
            "structuredLyrics": [
                {
                    "lang": "en",
                    "synced": true,
                    "displayArtist": "Test Artist",
                    "displayTitle": "Test Song",
                    "offset": -100,
                    "line": [
                        {"start": 0, "value": "First line"},
                        {"start": 5000, "value": "Second line"},
                        {"start": 10000, "value": "Third line"}
                    ]
                }
            ]
        }
        """.data(using: .utf8)!
        let lyrics = try JSONDecoder().decode(LyricsList.self, from: json)
        #expect(lyrics.structuredLyrics?.count == 1)
        let sl = try #require(lyrics.structuredLyrics?[0])
        #expect(sl.lang == "en")
        #expect(sl.synced == true)
        #expect(sl.displayArtist == "Test Artist")
        #expect(sl.displayTitle == "Test Song")
        #expect(sl.offset == -100)
        #expect(sl.line?.count == 3)
        #expect(sl.line?[0].start == 0)
        #expect(sl.line?[0].value == "First line")
        #expect(sl.line?[2].start == 10000)
    }

    @Test func lyricsListUnsynced() throws {
        let json = """
        {
            "structuredLyrics": [
                {
                    "lang": "ja",
                    "synced": false,
                    "line": [
                        {"value": "Line without timing"}
                    ]
                }
            ]
        }
        """.data(using: .utf8)!
        let lyrics = try JSONDecoder().decode(LyricsList.self, from: json)
        let sl = try #require(lyrics.structuredLyrics?[0])
        #expect(sl.lang == "ja")
        #expect(sl.synced == false)
        #expect(sl.offset == nil)
        #expect(sl.displayArtist == nil)
        #expect(sl.displayTitle == nil)
        #expect(sl.line?.count == 1)
        #expect(sl.line?[0].start == nil)
        #expect(sl.line?[0].value == "Line without timing")
    }

    @Test func lyricsListEmpty() throws {
        let json = """
        {}
        """.data(using: .utf8)!
        let lyrics = try JSONDecoder().decode(LyricsList.self, from: json)
        #expect(lyrics.structuredLyrics == nil)
    }

    @Test func lyricLineIdentifiable() throws {
        let json = """
        {"start":1000,"value":"Hello"}
        """.data(using: .utf8)!
        let line1 = try JSONDecoder().decode(LyricLine.self, from: json)
        let line2 = try JSONDecoder().decode(LyricLine.self, from: json)
        // Each decoded instance should have a unique UUID
        #expect(line1.id != line2.id)
    }

    // MARK: - SubsonicResponse / SubsonicResponseBody

    @Test func subsonicResponseHyphenatedKey() throws {
        // Top-level key is "subsonic-response" with a hyphen
        let json = """
        {
            "subsonic-response": {
                "status": "ok",
                "version": "1.16.1"
            }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SubsonicResponse.self, from: json)
        #expect(response.subsonicResponse.status == "ok")
        #expect(response.subsonicResponse.version == "1.16.1")
    }

    @Test func subsonicResponseOkStatus() throws {
        let json = """
        {
            "subsonic-response": {
                "status": "ok",
                "version": "1.16.1",
                "type": "navidrome",
                "serverVersion": "0.52.5",
                "openSubsonic": true
            }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SubsonicResponse.self, from: json)
        let body = response.subsonicResponse
        #expect(body.status == "ok")
        #expect(body.version == "1.16.1")
        #expect(body.type == "navidrome")
        #expect(body.serverVersion == "0.52.5")
        #expect(body.openSubsonic == true)
        #expect(body.error == nil)
    }

    @Test func subsonicResponseErrorStatus() throws {
        // Status is "failed" with error object — check != "ok"
        let json = """
        {
            "subsonic-response": {
                "status": "failed",
                "version": "1.16.1",
                "error": {
                    "code": 40,
                    "message": "Wrong username or password"
                }
            }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SubsonicResponse.self, from: json)
        let body = response.subsonicResponse
        #expect(body.status != "ok")
        #expect(body.status == "failed")
        #expect(body.error != nil)
        #expect(body.error?.code == 40)
        #expect(body.error?.message == "Wrong username or password")
    }

    @Test func subsonicResponseEmptyPayload() throws {
        // Only status and version — all payload keys should be nil
        let json = """
        {
            "subsonic-response": {
                "status": "ok",
                "version": "1.16.1"
            }
        }
        """.data(using: .utf8)!
        let body = try JSONDecoder().decode(SubsonicResponse.self, from: json).subsonicResponse
        #expect(body.status == "ok")
        #expect(body.artists == nil)
        #expect(body.artist == nil)
        #expect(body.album == nil)
        #expect(body.song == nil)
        #expect(body.searchResult3 == nil)
        #expect(body.playlists == nil)
        #expect(body.playlist == nil)
        #expect(body.genres == nil)
        #expect(body.starred2 == nil)
        #expect(body.albumList2 == nil)
        #expect(body.randomSongs == nil)
        #expect(body.internetRadioStations == nil)
        #expect(body.lyricsList == nil)
        #expect(body.playQueue == nil)
        #expect(body.bookmarks == nil)
        #expect(body.similarSongs2 == nil)
        #expect(body.topSongs == nil)
        #expect(body.error == nil)
    }

    @Test func subsonicResponseWithSongPayload() throws {
        let json = """
        {
            "subsonic-response": {
                "status": "ok",
                "version": "1.16.1",
                "song": {"id":"s-1","title":"Payload Song"}
            }
        }
        """.data(using: .utf8)!
        let body = try JSONDecoder().decode(SubsonicResponse.self, from: json).subsonicResponse
        #expect(body.song?.id == "s-1")
        #expect(body.song?.title == "Payload Song")
        #expect(body.album == nil)
    }

    @Test func subsonicResponseWithSearchResult3() throws {
        let json = """
        {
            "subsonic-response": {
                "status": "ok",
                "version": "1.16.1",
                "searchResult3": {
                    "artist": [{"id":"ar-1","name":"Found Artist"}],
                    "song": [{"id":"s-1","title":"Found Song"}]
                }
            }
        }
        """.data(using: .utf8)!
        let body = try JSONDecoder().decode(SubsonicResponse.self, from: json).subsonicResponse
        #expect(body.searchResult3 != nil)
        #expect(body.searchResult3?.artist?.count == 1)
        #expect(body.searchResult3?.song?.count == 1)
        #expect(body.searchResult3?.album == nil)
    }

    // MARK: - Wrapper Types

    @Test func playlistsWrapperDecoding() throws {
        let json = """
        {"playlist":[{"id":"pl-1","name":"Playlist One"},{"id":"pl-2","name":"Playlist Two"}]}
        """.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(PlaylistsWrapper.self, from: json)
        #expect(wrapper.playlist?.count == 2)
    }

    @Test func playlistsWrapperOmitted() throws {
        let json = """
        {}
        """.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(PlaylistsWrapper.self, from: json)
        #expect(wrapper.playlist == nil)
    }

    @Test func genresWrapperDecoding() throws {
        let json = """
        {"genre":[{"value":"Rock","songCount":100},{"value":"Jazz","albumCount":5}]}
        """.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(GenresWrapper.self, from: json)
        #expect(wrapper.genre?.count == 2)
        #expect(wrapper.genre?[0].value == "Rock")
        #expect(wrapper.genre?[1].value == "Jazz")
    }

    @Test func bookmarksWrapperDecoding() throws {
        let json = """
        {
            "bookmark": [
                {"position":1000,"username":"u1","created":"2024-01-01T00:00:00Z","changed":"2024-01-01T00:00:00Z"},
                {"position":2000,"username":"u2","created":"2024-01-02T00:00:00Z","changed":"2024-01-02T00:00:00Z"}
            ]
        }
        """.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(BookmarksWrapper.self, from: json)
        #expect(wrapper.bookmark?.count == 2)
        #expect(wrapper.bookmark?[0].position == 1000)
        #expect(wrapper.bookmark?[1].username == "u2")
    }

    @Test func bookmarksWrapperOmitted() throws {
        let json = """
        {}
        """.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(BookmarksWrapper.self, from: json)
        #expect(wrapper.bookmark == nil)
    }

    @Test func internetRadioStationsWrapperDecoding() throws {
        let json = """
        {"internetRadioStation":[{"id":"r1","name":"Station A","streamUrl":"https://a.stream"}]}
        """.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(InternetRadioStationsWrapper.self, from: json)
        #expect(wrapper.internetRadioStation?.count == 1)
    }

    // MARK: - Starred2

    @Test func starred2AllPresent() throws {
        let json = """
        {
            "artist": [{"id":"ar-1","name":"Starred Artist"}],
            "album": [{"id":"al-1","name":"Starred Album"}],
            "song": [{"id":"s-1","title":"Starred Song"}]
        }
        """.data(using: .utf8)!
        let starred = try JSONDecoder().decode(Starred2.self, from: json)
        #expect(starred.artist?.count == 1)
        #expect(starred.album?.count == 1)
        #expect(starred.song?.count == 1)
    }

    @Test func starred2AllOmitted() throws {
        let json = """
        {}
        """.data(using: .utf8)!
        let starred = try JSONDecoder().decode(Starred2.self, from: json)
        #expect(starred.artist == nil)
        #expect(starred.album == nil)
        #expect(starred.song == nil)
    }

    // MARK: - ArtistIndex / ArtistsResponse

    @Test func artistsResponseDecoding() throws {
        let json = """
        {
            "ignoredArticles": "The El La",
            "index": [
                {
                    "name": "A",
                    "artist": [{"id":"ar-1","name":"ABBA"},{"id":"ar-2","name":"AC/DC"}]
                },
                {
                    "name": "B",
                    "artist": [{"id":"ar-3","name":"Beatles"}]
                }
            ]
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ArtistsResponse.self, from: json)
        #expect(response.ignoredArticles == "The El La")
        #expect(response.index?.count == 2)
        let indexA = try #require(response.index?[0])
        #expect(indexA.name == "A")
        #expect(indexA.id == "A")
        #expect(indexA.artist?.count == 2)
        #expect(indexA.artist?[0].name == "ABBA")
    }

    @Test func artistIndexOmittedArtists() throws {
        let json = """
        {"name":"Z"}
        """.data(using: .utf8)!
        let index = try JSONDecoder().decode(ArtistIndex.self, from: json)
        #expect(index.name == "Z")
        #expect(index.artist == nil)
    }

    // MARK: - ReplayGain

    @Test func replayGainPartial() throws {
        let json = """
        {"trackGain": -3.5, "trackPeak": 0.95}
        """.data(using: .utf8)!
        let rg = try JSONDecoder().decode(ReplayGain.self, from: json)
        #expect(rg.trackGain == -3.5)
        #expect(rg.trackPeak == 0.95)
        #expect(rg.albumGain == nil)
        #expect(rg.albumPeak == nil)
        #expect(rg.baseGain == nil)
    }

    // MARK: - Additional Response Types

    @Test func albumList2ResponseDecoding() throws {
        let json = """
        {"album":[{"id":"al-1","name":"Album A"},{"id":"al-2","name":"Album B"}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(AlbumList2Response.self, from: json)
        #expect(response.album?.count == 2)
    }

    @Test func albumList2ResponseOmitted() throws {
        let json = """
        {}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(AlbumList2Response.self, from: json)
        #expect(response.album == nil)
    }

    @Test func randomSongsResponseDecoding() throws {
        let json = """
        {"song":[{"id":"s-1","title":"Random 1"},{"id":"s-2","title":"Random 2"}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(RandomSongsResponse.self, from: json)
        #expect(response.song?.count == 2)
    }

    @Test func similarSongs2ResponseDecoding() throws {
        let json = """
        {"song":[{"id":"s-10","title":"Similar Track"}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SimilarSongs2Response.self, from: json)
        #expect(response.song?.count == 1)
        #expect(response.song?[0].title == "Similar Track")
    }

    @Test func topSongsResponseDecoding() throws {
        let json = """
        {"song":[{"id":"s-top","title":"Hit Song"}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(TopSongsResponse.self, from: json)
        #expect(response.song?.count == 1)
    }

    // MARK: - Edge Cases

    @Test func largeIntegerValues() throws {
        let json = """
        {"id":"big","title":"Big File","size":2147483647,"duration":999999,"bitRate":9999}
        """.data(using: .utf8)!
        let song = try JSONDecoder().decode(Song.self, from: json)
        #expect(song.size == 2_147_483_647)
        #expect(song.duration == 999_999)
        #expect(song.bitRate == 9999)
    }

    @Test func unicodeStringFields() throws {
        let json = """
        {"id":"uni","title":"\\u304a\\u306f\\u3088\\u3046","artist":"\\u00c9milie"}
        """.data(using: .utf8)!
        let song = try JSONDecoder().decode(Song.self, from: json)
        #expect(song.title == "\u{304a}\u{306f}\u{3088}\u{3046}")
        #expect(song.artist == "\u{00c9}milie")
    }

    @Test func subsonicAPIErrorDecoding() throws {
        let json = """
        {"code":70,"message":"The requested data was not found"}
        """.data(using: .utf8)!
        let err = try JSONDecoder().decode(SubsonicAPIError.self, from: json)
        #expect(err.code == 70)
        #expect(err.message == "The requested data was not found")
    }

    @Test func fullResponseWithPlaylistPayload() throws {
        // End-to-end: full response wrapping a playlist with public mapping
        let json = """
        {
            "subsonic-response": {
                "status": "ok",
                "version": "1.16.1",
                "type": "navidrome",
                "serverVersion": "0.52.5",
                "openSubsonic": true,
                "playlist": {
                    "id": "pl-full",
                    "name": "Full Test",
                    "songCount": 1,
                    "duration": 300,
                    "public": true,
                    "owner": "testuser",
                    "entry": [
                        {"id":"s-1","title":"Entry Song","duration":300}
                    ]
                }
            }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SubsonicResponse.self, from: json)
        let body = response.subsonicResponse
        #expect(body.status == "ok")
        let pl = try #require(body.playlist)
        #expect(pl.id == "pl-full")
        #expect(pl.isPublic == true)
        #expect(pl.entry?.count == 1)
        #expect(pl.entry?[0].duration == 300)
    }
}
