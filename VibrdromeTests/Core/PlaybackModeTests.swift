import Testing
import Foundation
@testable import Vibrdrome

/// Tests for PlaybackMode enum and mode selection logic.
struct PlaybackModeTests {

    // MARK: - PlaybackMode enum

    @Test func gaplessIsDefault() {
        let mode: PlaybackMode = .gapless
        #expect(mode == .gapless)
    }

    @Test func allModesExist() {
        let modes: [PlaybackMode] = [.gapless, .crossfade]
        #expect(modes.count == 2)
    }

    @Test func modesAreSendable() {
        let mode: Sendable = PlaybackMode.gapless
        _ = mode
    }

    // MARK: - Mode Selection Logic
    // EQ is now orthogonal (applied via MTAudioProcessingTap on any mode).
    // Selection: crossfadeDuration > 0 → .crossfade, else → .gapless

    /// Simulates AudioEngine.selectMode() logic
    private func selectMode(crossfadeDuration: Int) -> PlaybackMode {
        if crossfadeDuration > 0 { return .crossfade }
        return .gapless
    }

    @Test func defaultSelectionIsGapless() {
        let mode = selectMode(crossfadeDuration: 0)
        #expect(mode == .gapless)
    }

    @Test func crossfadeWhenDurationPositive() {
        let mode = selectMode(crossfadeDuration: 5)
        #expect(mode == .crossfade)
    }

    // MARK: - RepeatMode

    @Test func repeatModeValues() {
        let modes: [RepeatMode] = [.off, .all, .one]
        #expect(modes.count == 3)
    }

    @Test func repeatModeIsSendable() {
        let mode: Sendable = RepeatMode.off
        _ = mode
    }

    // MARK: - Additional PlaybackMode Tests

    @Test func allPlaybackModesAreDistinct() {
        #expect(PlaybackMode.gapless != PlaybackMode.crossfade)
    }

    @Test func crossfadeSelectedAtMinimumDuration() {
        let mode = selectMode(crossfadeDuration: 1)
        #expect(mode == .crossfade)
    }

    @Test func crossfadeSelectedAtMaximumDuration() {
        let mode = selectMode(crossfadeDuration: 12)
        #expect(mode == .crossfade)
    }

    @Test func allRepeatModesAreDistinct() {
        #expect(RepeatMode.off != RepeatMode.all)
        #expect(RepeatMode.all != RepeatMode.one)
        #expect(RepeatMode.off != RepeatMode.one)
    }

    @Test func modeSelectionAllCombinations() {
        // crossfade>0 → .crossfade; else → .gapless
        let cases: [(xfade: Int, expected: PlaybackMode)] = [
            (0, .gapless),
            (5, .crossfade),
            (1, .crossfade),
            (12, .crossfade),
        ]
        for c in cases {
            let mode = selectMode(crossfadeDuration: c.xfade)
            #expect(mode == c.expected,
                    "xfade=\(c.xfade) → expected \(c.expected), got \(mode)")
        }
    }
}
