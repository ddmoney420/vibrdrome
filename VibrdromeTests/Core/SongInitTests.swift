import Testing
import Foundation
@testable import Vibrdrome

struct SongInitTests {

    @Test func minimalInit() {
        let song = Song(id: "123", title: "Test Song")
        #expect(song.id == "123")
        #expect(song.title == "Test Song")
        #expect(song.artist == nil)
        #expect(song.album == nil)
        #expect(song.albumArtist == nil)
        #expect(song.duration == nil)
        #expect(song.parent == nil)
        #expect(song.coverArt == nil)
        #expect(song.bitRate == nil)
        #expect(song.replayGain == nil)
    }

    @Test func initWithMetadata() {
        let song = Song(
            id: "456", title: "With Metadata",
            album: "Test Album", artist: "Test Artist",
            albumArtist: "Album Artist", duration: 240
        )
        #expect(song.id == "456")
        #expect(song.title == "With Metadata")
        #expect(song.album == "Test Album")
        #expect(song.artist == "Test Artist")
        #expect(song.albumArtist == "Album Artist")
        #expect(song.duration == 240)
    }

    @Test func fullInit() {
        let song = Song(
            id: "789", parent: "parent1", title: "Full Song",
            album: "Album", artist: "Artist", albumArtist: "AA",
            albumId: "alb1", artistId: "art1",
            track: 3, year: 2024, genre: "Rock",
            coverArt: "cov1", size: 5_000_000,
            contentType: "audio/flac", suffix: "flac",
            duration: 300, bitRate: 1411, path: "/music/song.flac",
            discNumber: 1, created: "2024-01-01",
            starred: "2024-06-01", userRating: 5,
            bpm: 120, replayGain: nil, musicBrainzId: "mb-id"
        )
        #expect(song.track == 3)
        #expect(song.year == 2024)
        #expect(song.genre == "Rock")
        #expect(song.suffix == "flac")
        #expect(song.discNumber == 1)
        #expect(song.userRating == 5)
        #expect(song.bpm == 120)
        #expect(song.musicBrainzId == "mb-id")
    }
}
