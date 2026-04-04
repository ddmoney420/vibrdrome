import Testing
import Foundation
@testable import Vibrdrome

struct WidgetStateTests {

    @Test func encodeAndDecode() throws {
        let state = NowPlayingState(
            title: "Test Song", artist: "Test Artist", album: "Test Album",
            isPlaying: true, coverArtId: "art123", serverURL: "https://example.com",
            timestamp: Date(timeIntervalSince1970: 1000)
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NowPlayingState.self, from: data)
        #expect(decoded.title == "Test Song")
        #expect(decoded.artist == "Test Artist")
        #expect(decoded.album == "Test Album")
        #expect(decoded.isPlaying == true)
        #expect(decoded.coverArtId == "art123")
        #expect(decoded.serverURL == "https://example.com")
    }

    @Test func encodeWithNilFields() throws {
        let state = NowPlayingState(
            title: "Song", artist: "", album: "",
            isPlaying: false, coverArtId: nil, serverURL: nil,
            timestamp: .now
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NowPlayingState.self, from: data)
        #expect(decoded.coverArtId == nil)
        #expect(decoded.serverURL == nil)
        #expect(decoded.isPlaying == false)
    }

    @Test func titlePreservedExactly() throws {
        let state = NowPlayingState(
            title: "Ünïcödé Tëst 🎵", artist: "Artïst", album: "",
            isPlaying: true, coverArtId: nil, serverURL: nil,
            timestamp: .now
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NowPlayingState.self, from: data)
        #expect(decoded.title == "Ünïcödé Tëst 🎵")
    }

    @Test func timestampPreserved() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        let state = NowPlayingState(
            title: "T", artist: "A", album: "B",
            isPlaying: false, coverArtId: nil, serverURL: nil,
            timestamp: date
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NowPlayingState.self, from: data)
        #expect(abs(decoded.timestamp.timeIntervalSince(date)) < 1)
    }
}
