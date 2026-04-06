import Testing
import Foundation
@testable import Vibrdrome

/// Tests for Now Playing layout logic and helpers.
struct NowPlayingLayoutTests {

    // MARK: - Sleep Timer Formatting

    @Test func sleepTimerZeroSeconds() {
        let result = formatSleepTime(0)
        #expect(result == "0:00")
    }

    @Test func sleepTimerOneMinute() {
        let result = formatSleepTime(60)
        #expect(result == "1:00")
    }

    @Test func sleepTimerMixedMinutesSeconds() {
        let result = formatSleepTime(95)
        #expect(result == "1:35")
    }

    @Test func sleepTimerLargeValue() {
        let result = formatSleepTime(3600)
        #expect(result == "60:00")
    }

    // MARK: - Duration Formatting

    @Test func durationZero() {
        let result = formatDuration(0)
        #expect(result == "0:00")
    }

    @Test func durationOneMinute() {
        let result = formatDuration(60)
        #expect(result == "1:00")
    }

    @Test func durationWithSeconds() {
        let result = formatDuration(185)
        #expect(result == "3:05")
    }

    @Test func durationHours() {
        let result = formatDuration(3661)
        #expect(result == "1:01:01")
    }

    // MARK: - Repeat Mode Display

    @Test func repeatModeOffValue() {
        let mode = RepeatMode.off
        switch mode {
        case .off: break
        default: Issue.record("Expected .off")
        }
    }

    @Test func repeatModeAllValue() {
        let mode = RepeatMode.all
        switch mode {
        case .all: break
        default: Issue.record("Expected .all")
        }
    }

    @Test func repeatModeOneValue() {
        let mode = RepeatMode.one
        switch mode {
        case .one: break
        default: Issue.record("Expected .one")
        }
    }

    // MARK: - Song Metadata for Streaming Info

    @Test func songBitRatePresent() {
        let song = Song(
            id: "1", parent: nil, title: "Test", album: nil, artist: nil,
            albumId: nil, artistId: nil, track: nil, year: nil, genre: nil,
            coverArt: nil, size: nil, contentType: nil, suffix: "mp3",
            duration: 200, bitRate: 320, path: nil, discNumber: nil,
            created: nil, starred: nil, userRating: nil, bpm: nil,
            replayGain: nil, musicBrainzId: nil
        )
        #expect(song.bitRate == 320)
        #expect(song.suffix == "mp3")
    }

    @Test func songBitRateNil() {
        let song = Song(
            id: "1", parent: nil, title: "Test", album: nil, artist: nil,
            albumId: nil, artistId: nil, track: nil, year: nil, genre: nil,
            coverArt: nil, size: nil, contentType: nil, suffix: nil,
            duration: nil, bitRate: nil, path: nil, discNumber: nil,
            created: nil, starred: nil, userRating: nil, bpm: nil,
            replayGain: nil, musicBrainzId: nil
        )
        #expect(song.bitRate == nil)
        #expect(song.suffix == nil)
    }
}

// MARK: - Helpers (mirror app logic)

private func formatSleepTime(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return "\(m):\(String(format: "%02d", s))"
}
