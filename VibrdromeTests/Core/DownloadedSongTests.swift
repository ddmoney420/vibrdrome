import Testing
import Foundation
@testable import Vibrdrome

struct DownloadedSongTests {

    @Test func toSongPreservesId() {
        let dl = DownloadedSong(
            songId: "song-123", songTitle: "Test Song", artistName: "Test Artist",
            albumName: "Test Album", coverArtId: "cover-1", duration: 240,
            localFilePath: "/path/to/file.mp3", category: ""
        )
        let song = dl.toSong()
        #expect(song.id == "song-123")
    }

    @Test func toSongPreservesTitle() {
        let dl = DownloadedSong(
            songId: "1", songTitle: "My Song", artistName: nil,
            albumName: nil, coverArtId: nil, duration: nil,
            localFilePath: "/path", category: ""
        )
        let song = dl.toSong()
        #expect(song.title == "My Song")
    }

    @Test func toSongPreservesArtistAndAlbum() {
        let dl = DownloadedSong(
            songId: "1", songTitle: "Title", artistName: "Artist",
            albumName: "Album", coverArtId: nil, duration: nil,
            localFilePath: "/path", category: ""
        )
        let song = dl.toSong()
        #expect(song.artist == "Artist")
        #expect(song.album == "Album")
    }

    @Test func toSongHandlesNilFields() {
        let dl = DownloadedSong(
            songId: "1", songTitle: "Title", artistName: nil,
            albumName: nil, coverArtId: nil, duration: nil,
            localFilePath: "/path", category: ""
        )
        let song = dl.toSong()
        #expect(song.artist == nil)
        #expect(song.album == nil)
        #expect(song.coverArt == nil)
        #expect(song.duration == nil)
    }

    @Test func toSongPreservesDuration() {
        let dl = DownloadedSong(
            songId: "1", songTitle: "Title", artistName: nil,
            albumName: nil, coverArtId: nil, duration: 300,
            localFilePath: "/path", category: ""
        )
        let song = dl.toSong()
        #expect(song.duration == 300)
    }

    @Test func toSongPreservesCoverArt() {
        let dl = DownloadedSong(
            songId: "1", songTitle: "Title", artistName: nil,
            albumName: nil, coverArtId: "art-456", duration: nil,
            localFilePath: "/path", category: ""
        )
        let song = dl.toSong()
        #expect(song.coverArt == "art-456")
    }
}
