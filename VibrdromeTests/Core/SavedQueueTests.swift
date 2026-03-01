import Testing
import Foundation
@testable import Vibrdrome

/// Tests for SavedQueue SwiftData model.
struct SavedQueueTests {

    // MARK: - Default Initialization

    @Test func defaultIdIsCurrent() {
        let queue = SavedQueue()
        #expect(queue.id == "current")
    }

    @Test func defaultSongIdsEmpty() {
        let queue = SavedQueue()
        #expect(queue.songIds.isEmpty)
    }

    @Test func defaultCurrentIndexIsZero() {
        let queue = SavedQueue()
        #expect(queue.currentIndex == 0)
    }

    @Test func defaultCurrentTimeIsZero() {
        let queue = SavedQueue()
        #expect(queue.currentTime == 0)
    }

    @Test func defaultShuffleDisabled() {
        let queue = SavedQueue()
        #expect(queue.shuffleEnabled == false)
    }

    @Test func defaultRepeatModeIsOff() {
        let queue = SavedQueue()
        #expect(queue.repeatMode == "off")
    }

    @Test func defaultSavedAtIsNow() {
        let before = Date()
        let queue = SavedQueue()
        let after = Date()
        #expect(queue.savedAt >= before)
        #expect(queue.savedAt <= after)
    }

    // MARK: - Custom Initialization

    @Test func customInitSetsAllFields() {
        let songIds = ["song1", "song2", "song3"]
        let date = Date(timeIntervalSince1970: 1000)
        let queue = SavedQueue(
            id: "custom",
            songIds: songIds,
            currentIndex: 2,
            currentTime: 45.5,
            shuffleEnabled: true,
            repeatMode: "all",
            savedAt: date
        )

        #expect(queue.id == "custom")
        #expect(queue.songIds == songIds)
        #expect(queue.currentIndex == 2)
        #expect(queue.currentTime == 45.5)
        #expect(queue.shuffleEnabled == true)
        #expect(queue.repeatMode == "all")
        #expect(queue.savedAt == date)
    }

    // MARK: - Mutable Fields

    @Test func songIdsAreMutable() {
        let queue = SavedQueue()
        queue.songIds = ["a", "b"]
        #expect(queue.songIds == ["a", "b"])
    }

    @Test func currentIndexIsMutable() {
        let queue = SavedQueue()
        queue.currentIndex = 5
        #expect(queue.currentIndex == 5)
    }

    @Test func currentTimeIsMutable() {
        let queue = SavedQueue()
        queue.currentTime = 123.456
        #expect(queue.currentTime == 123.456)
    }

    @Test func shuffleEnabledIsMutable() {
        let queue = SavedQueue()
        queue.shuffleEnabled = true
        #expect(queue.shuffleEnabled == true)
    }

    @Test func repeatModeIsMutable() {
        let queue = SavedQueue()
        queue.repeatMode = "one"
        #expect(queue.repeatMode == "one")
    }

    // MARK: - RepeatMode String Values

    @Test func repeatModeValidValues() {
        let validModes = ["off", "all", "one"]
        for mode in validModes {
            let queue = SavedQueue(repeatMode: mode)
            #expect(queue.repeatMode == mode)
        }
    }

    // MARK: - Edge Cases

    @Test func emptySongIds() {
        let queue = SavedQueue(songIds: [])
        #expect(queue.songIds.isEmpty)
    }

    @Test func largeSongIdsList() {
        let ids = (0..<1000).map { "song_\($0)" }
        let queue = SavedQueue(songIds: ids)
        #expect(queue.songIds.count == 1000)
    }

    @Test func zeroCurrentTime() {
        let queue = SavedQueue(currentTime: 0)
        #expect(queue.currentTime == 0)
    }

    @Test func largeCurrentTime() {
        let queue = SavedQueue(currentTime: 3600.0)
        #expect(queue.currentTime == 3600.0)
    }
}
