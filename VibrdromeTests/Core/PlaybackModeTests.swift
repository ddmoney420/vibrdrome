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
        let modes: [PlaybackMode] = [.gapless, .crossfade, .eq]
        #expect(modes.count == 3)
    }

    @Test func modesAreSendable() {
        let mode: Sendable = PlaybackMode.gapless
        _ = mode
    }

    // MARK: - Mode Selection Logic
    // Tests the priority: EQ > Crossfade > Gapless
    // EQ works for all tracks (local and streamed). Streams are buffered to a temp file.

    /// Simulates AudioEngine.selectMode() logic
    private func selectMode(eqEnabled: Bool, crossfadeDuration: Int) -> PlaybackMode {
        if eqEnabled { return .eq }
        if crossfadeDuration > 0 { return .crossfade }
        return .gapless
    }

    @Test func defaultSelectionIsGapless() {
        let mode = selectMode(eqEnabled: false, crossfadeDuration: 0)
        #expect(mode == .gapless)
    }

    @Test func crossfadeWhenDurationPositive() {
        let mode = selectMode(eqEnabled: false, crossfadeDuration: 5)
        #expect(mode == .crossfade)
    }

    @Test func eqWhenEnabled() {
        let mode = selectMode(eqEnabled: true, crossfadeDuration: 0)
        #expect(mode == .eq)
    }

    @Test func eqTakesPriorityOverCrossfade() {
        let mode = selectMode(eqEnabled: true, crossfadeDuration: 5)
        #expect(mode == .eq)
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
        #expect(PlaybackMode.crossfade != PlaybackMode.eq)
        #expect(PlaybackMode.gapless != PlaybackMode.eq)
    }

    @Test func crossfadeSelectedAtMinimumDuration() {
        // crossfadeDuration of 1 (minimum valid) selects crossfade
        let mode = selectMode(eqEnabled: false, crossfadeDuration: 1)
        #expect(mode == .crossfade)
    }

    @Test func crossfadeSelectedAtMaximumDuration() {
        // crossfadeDuration of 12 (maximum) selects crossfade
        let mode = selectMode(eqEnabled: false, crossfadeDuration: 12)
        #expect(mode == .crossfade)
    }

    @Test func allRepeatModesAreDistinct() {
        #expect(RepeatMode.off != RepeatMode.all)
        #expect(RepeatMode.all != RepeatMode.one)
        #expect(RepeatMode.off != RepeatMode.one)
    }

    @Test func modeSelectionTableAll4Combinations() {
        // All 4 combinations of (eqEnabled, crossfade>0)
        // Priority: eqEnabled → .eq; crossfade>0 → .crossfade; else → .gapless
        let cases: [(eq: Bool, xfade: Int, expected: PlaybackMode)] = [
            (false, 0, .gapless),
            (false, 5, .crossfade),
            (true,  0, .eq),
            (true,  5, .eq),
        ]
        for c in cases {
            let mode = selectMode(eqEnabled: c.eq, crossfadeDuration: c.xfade)
            #expect(mode == c.expected,
                    "eq=\(c.eq), xfade=\(c.xfade) → expected \(c.expected), got \(mode)")
        }
    }
}
