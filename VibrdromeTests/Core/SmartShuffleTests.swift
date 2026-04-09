import Testing
import Foundation
@testable import Vibrdrome

@MainActor
struct SmartShuffleTests {

    private func makeSong(id: String, artist: String? = nil, suffix: String? = nil) -> Song {
        Song(
            id: id, parent: nil, title: "Song \(id)",
            album: nil, artist: artist, albumId: nil, artistId: nil,
            track: nil, year: nil, genre: nil, coverArt: nil,
            size: nil, contentType: nil, suffix: suffix,
            duration: 180, bitRate: nil, path: nil,
            discNumber: nil, created: nil, starred: nil, userRating: nil,
            bpm: nil, replayGain: nil, musicBrainzId: nil
        )
    }

    @Test func preservesAllSongs() {
        let songs = (1...10).map { makeSong(id: "\($0)", artist: "Artist \($0 % 3)") }
        let result = AudioEngine.shared.smartShuffle(songs)
        #expect(result.count == songs.count)
        let originalIds = Set(songs.map(\.id))
        let resultIds = Set(result.map(\.id))
        #expect(originalIds == resultIds)
    }

    @Test func avoidsConsecutiveSameArtist() {
        // 5 by Artist A, 5 by Artist B
        var songs: [Song] = []
        for idx in 0..<5 { songs.append(makeSong(id: "a\(idx)", artist: "Artist A")) }
        for idx in 0..<5 { songs.append(makeSong(id: "b\(idx)", artist: "Artist B")) }

        let result = AudioEngine.shared.smartShuffle(songs)

        var consecutiveCount = 0
        for idx in 1..<result.count where result[idx].artist == result[idx - 1].artist {
            consecutiveCount += 1
        }
        // Should have zero or very few consecutive same-artist pairs
        #expect(consecutiveCount <= 1,
                "Expected at most 1 consecutive same-artist pair, got \(consecutiveCount)")
    }

    @Test func singleSongReturnsItself() {
        let songs = [makeSong(id: "only")]
        let result = AudioEngine.shared.smartShuffle(songs)
        #expect(result.count == 1)
        #expect(result[0].id == "only")
    }

    @Test func emptyArrayReturnsEmpty() {
        let result = AudioEngine.shared.smartShuffle([])
        #expect(result.isEmpty)
    }

    @Test func allSameArtistStillShuffles() {
        let songs = (1...5).map { makeSong(id: "\($0)", artist: "Same Artist") }
        let result = AudioEngine.shared.smartShuffle(songs)
        #expect(result.count == 5)
        let resultIds = Set(result.map(\.id))
        let originalIds = Set(songs.map(\.id))
        #expect(resultIds == originalIds)
    }
}
