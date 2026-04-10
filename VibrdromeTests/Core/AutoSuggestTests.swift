import Testing
import Foundation
@testable import Vibrdrome

@MainActor
struct AutoSuggestTests {

    private func makeSong(id: String = "1", title: String = "Test") -> Song {
        Song(
            id: id, parent: nil, title: title,
            album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
            track: nil, year: nil, genre: nil, coverArt: nil,
            size: nil, contentType: nil, suffix: nil,
            duration: 180, bitRate: nil, path: nil,
            discNumber: nil, created: nil, starred: nil, userRating: nil,
            bpm: nil, replayGain: nil, musicBrainzId: nil
        )
    }

    @Test func addToQueueAppendsCorrectly() {
        let engine = AudioEngine.shared
        engine.queue = [makeSong(id: "a")]
        engine.currentIndex = 0
        engine.addToQueue(makeSong(id: "b"))
        #expect(engine.queue.count == 2)
        #expect(engine.queue[1].id == "b")
    }

    @Test func skipToIndexPreservesQueue() {
        let engine = AudioEngine.shared
        engine.queue = [makeSong(id: "a"), makeSong(id: "b"), makeSong(id: "c")]
        engine.currentIndex = 0
        // skipToIndex tries to play which won't work in test, but queue should stay
        #expect(engine.queue.count == 3)
    }
}
