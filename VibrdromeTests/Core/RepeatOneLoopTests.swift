import Testing
import Foundation
@testable import Vibrdrome

/// Repeat One should loop the current item indefinitely (fix/repeat-one-loops-current) — until the
/// mode changes, the user navigates, or the queue is replaced. Previously it replayed once then
/// advanced ("Track 1 x2, then Track 2 x2"). These drive AudioEngine.shared through the real
/// play()/handleTrackEnd path; assertions read the synchronously-updated queue/index state.
@MainActor
struct RepeatOneLoopTests {

    private func makeSongs(_ n: Int) -> [Song] {
        (0..<n).map { Song(id: "song\($0)", title: "Track \($0)", artist: "Artist", duration: 180) }
    }

    private func reset() {
        let e = AudioEngine.shared
        e.queue = []
        e.currentIndex = 0
        e.currentSong = nil
        e.isPlaying = false
        e.shuffleEnabled = false
        e.repeatMode = .off
        e.isRadioMode = false
        e.currentRadioStation = nil
    }

    // 1 & 2: repeated automatic endings keep the SAME index — no toggle into advancement.
    @Test func repeatOneKeepsSameItemAcrossEndings() {
        reset()
        let e = AudioEngine.shared
        e.play(song: makeSongs(3)[1], from: makeSongs(3), at: 1)
        e.repeatMode = .one
        e.isPlaying = true

        for _ in 0..<4 {
            e.handleTrackEnd()
            #expect(e.currentSong?.id == "song1")
            #expect(e.currentIndex == 1)
        }
    }

    // 3: manual Next overrides Repeat One and selects the next item.
    @Test func manualNextOverridesRepeatOne() {
        reset()
        let e = AudioEngine.shared
        let songs = makeSongs(3)
        e.play(song: songs[0], from: songs, at: 0)
        e.repeatMode = .one
        e.isPlaying = true

        e.next()
        #expect(e.currentSong?.id == "song1")
        #expect(e.currentIndex == 1)
    }

    // 6: switching Repeat One -> Off restores normal advancement on the next ending.
    @Test func repeatOneToOffAdvances() {
        reset()
        let e = AudioEngine.shared
        let songs = makeSongs(3)
        e.play(song: songs[0], from: songs, at: 0)
        e.repeatMode = .one
        e.isPlaying = true

        e.handleTrackEnd()                       // Repeat One: stays on song0
        #expect(e.currentSong?.id == "song0")
        e.repeatMode = .off
        e.handleTrackEnd()                       // Off: advances to song1
        #expect(e.currentSong?.id == "song1")
    }

    // 8: one-item queue remains stable (keeps replaying the only item).
    @Test func repeatOneOneItemQueueStable() {
        reset()
        let e = AudioEngine.shared
        let songs = makeSongs(1)
        e.play(song: songs[0], from: songs, at: 0)
        e.repeatMode = .one
        e.isPlaying = true

        for _ in 0..<3 {
            e.handleTrackEnd()
            #expect(e.currentSong?.id == "song0")
            #expect(e.currentIndex == 0)
        }
    }

    // Queue replacement while Repeat One is active must load the new selection normally.
    @Test func queueReplacementWhileRepeatOne() {
        reset()
        let e = AudioEngine.shared
        e.play(song: makeSongs(3)[0], from: makeSongs(3), at: 0)
        e.repeatMode = .one
        e.isPlaying = true
        e.handleTrackEnd()                       // looping song0

        let fresh = [Song(id: "new0", title: "New", artist: "A", duration: 120)]
        e.play(song: fresh[0], from: fresh, at: 0)
        #expect(e.currentSong?.id == "new0")
        #expect(e.queue.map(\.id) == ["new0"])
    }
}
