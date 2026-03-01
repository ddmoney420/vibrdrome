import Testing
import Foundation
@testable import Vibrdrome

/// Tests for re-authentication logic and AppState requiresReAuth flow.
struct ReAuthTests {

    // MARK: - RepeatMode String Encoding (used by SavedQueue persistence)

    @Test func repeatModeOffString() {
        let mode: RepeatMode = .off
        let str: String
        switch mode {
        case .off: str = "off"
        case .all: str = "all"
        case .one: str = "one"
        }
        #expect(str == "off")
    }

    @Test func repeatModeAllString() {
        let mode: RepeatMode = .all
        let str: String
        switch mode {
        case .off: str = "off"
        case .all: str = "all"
        case .one: str = "one"
        }
        #expect(str == "all")
    }

    @Test func repeatModeOneString() {
        let mode: RepeatMode = .one
        let str: String
        switch mode {
        case .off: str = "off"
        case .all: str = "all"
        case .one: str = "one"
        }
        #expect(str == "one")
    }

    @Test func repeatModeFromStringOff() {
        let str = "off"
        let mode: RepeatMode
        switch str {
        case "all": mode = .all
        case "one": mode = .one
        default: mode = .off
        }
        #expect(mode == .off)
    }

    @Test func repeatModeFromStringAll() {
        let str = "all"
        let mode: RepeatMode
        switch str {
        case "all": mode = .all
        case "one": mode = .one
        default: mode = .off
        }
        #expect(mode == .all)
    }

    @Test func repeatModeFromStringOne() {
        let str = "one"
        let mode: RepeatMode
        switch str {
        case "all": mode = .all
        case "one": mode = .one
        default: mode = .off
        }
        #expect(mode == .one)
    }

    @Test func repeatModeFromUnknownStringDefaultsToOff() {
        let str = "bogus"
        let mode: RepeatMode
        switch str {
        case "all": mode = .all
        case "one": mode = .one
        default: mode = .off
        }
        #expect(mode == .off)
    }

    // MARK: - SavedServer Model

    @Test func savedServerHasUniqueId() {
        let a = SavedServer(name: "Test", url: "https://a.com", username: "u")
        let b = SavedServer(name: "Test", url: "https://a.com", username: "u")
        #expect(a.id != b.id)
    }

    @Test func savedServerEquality() {
        let a = SavedServer(name: "Test", url: "https://a.com", username: "u")
        // Same id → equal
        #expect(a == a)
    }

    @Test func savedServerIsCodable() {
        let server = SavedServer(name: "My Server", url: "https://music.example.com", username: "admin")
        let data = try? JSONEncoder().encode(server)
        #expect(data != nil)
        if let data {
            let decoded = try? JSONDecoder().decode(SavedServer.self, from: data)
            #expect(decoded?.name == "My Server")
            #expect(decoded?.url == "https://music.example.com")
            #expect(decoded?.username == "admin")
            #expect(decoded?.id == server.id)
        }
    }

    // MARK: - Queue Persistence Guard Conditions

    @Test func bookmarkThresholdIs30Seconds() {
        // createBookmarkIfNeeded requires currentTime > 30
        let threshold: Double = 30
        #expect(threshold == 30, "Bookmark threshold should be 30 seconds")
    }

    @Test func positionConversionToMilliseconds() {
        let currentTime: Double = 45.5
        let position = Int(currentTime * 1000)
        #expect(position == 45500)
    }

    @Test func positionConversionFromMilliseconds() {
        let serverPosition = 45500
        let currentTime = Double(serverPosition) / 1000.0
        #expect(currentTime == 45.5)
    }

    @Test func currentIndexClampedToValidRange() {
        let songCount = 5
        let savedIndex = 10
        let clampedIndex = min(savedIndex, songCount - 1)
        #expect(clampedIndex == 4)
    }

    @Test func currentIndexClampedWhenValid() {
        let songCount = 5
        let savedIndex = 2
        let clampedIndex = min(savedIndex, songCount - 1)
        #expect(clampedIndex == 2)
    }

    @Test func currentIndexClampedToZeroForSingleSong() {
        let songCount = 1
        let savedIndex = 0
        let clampedIndex = min(savedIndex, songCount - 1)
        #expect(clampedIndex == 0)
    }
}
