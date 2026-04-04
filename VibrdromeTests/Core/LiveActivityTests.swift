#if os(iOS)
import Testing
import Foundation
@testable import Vibrdrome

struct LiveActivityTests {

    @Test func attributesEncoding() throws {
        let state = NowPlayingAttributes.ContentState(
            title: "Test Song", artist: "Test Artist", isPlaying: true
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NowPlayingAttributes.ContentState.self, from: data)
        #expect(decoded.title == "Test Song")
        #expect(decoded.artist == "Test Artist")
        #expect(decoded.isPlaying == true)
    }

    @Test func attributesAlbumName() throws {
        let attrs = NowPlayingAttributes(albumName: "Test Album")
        let data = try JSONEncoder().encode(attrs)
        let decoded = try JSONDecoder().decode(NowPlayingAttributes.self, from: data)
        #expect(decoded.albumName == "Test Album")
    }

    @Test func contentStateHashable() {
        let a = NowPlayingAttributes.ContentState(title: "A", artist: "B", isPlaying: true)
        let b = NowPlayingAttributes.ContentState(title: "A", artist: "B", isPlaying: true)
        let c = NowPlayingAttributes.ContentState(title: "C", artist: "D", isPlaying: false)
        #expect(a == b)
        #expect(a != c)
    }
}
#endif
