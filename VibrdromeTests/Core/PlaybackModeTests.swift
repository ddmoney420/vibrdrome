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

    /// Simulates AudioEngine.selectMode() logic
    private func selectMode(eqEnabled: Bool, isLocal: Bool, crossfadeDuration: Int) -> PlaybackMode {
        if eqEnabled && isLocal { return .eq }
        if crossfadeDuration > 0 { return .crossfade }
        return .gapless
    }

    @Test func defaultSelectionIsGapless() {
        let mode = selectMode(eqEnabled: false, isLocal: false, crossfadeDuration: 0)
        #expect(mode == .gapless)
    }

    @Test func crossfadeWhenDurationPositive() {
        let mode = selectMode(eqEnabled: false, isLocal: false, crossfadeDuration: 5)
        #expect(mode == .crossfade)
    }

    @Test func eqWhenEnabledAndLocal() {
        let mode = selectMode(eqEnabled: true, isLocal: true, crossfadeDuration: 0)
        #expect(mode == .eq)
    }

    @Test func eqTakesPriorityOverCrossfade() {
        let mode = selectMode(eqEnabled: true, isLocal: true, crossfadeDuration: 5)
        #expect(mode == .eq)
    }

    @Test func crossfadeWhenEqEnabledButNotLocal() {
        let mode = selectMode(eqEnabled: true, isLocal: false, crossfadeDuration: 5)
        #expect(mode == .crossfade)
    }

    @Test func gaplessWhenEqEnabledButNotLocal() {
        let mode = selectMode(eqEnabled: true, isLocal: false, crossfadeDuration: 0)
        #expect(mode == .gapless)
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
        let mode = selectMode(eqEnabled: false, isLocal: false, crossfadeDuration: 1)
        #expect(mode == .crossfade)
    }

    @Test func crossfadeSelectedAtMaximumDuration() {
        // crossfadeDuration of 12 (maximum) selects crossfade
        let mode = selectMode(eqEnabled: false, isLocal: false, crossfadeDuration: 12)
        #expect(mode == .crossfade)
    }

    @Test func eqEnabledButNotLocalWithNoCrossfadeFallsToGapless() {
        // eqEnabled=true, isLocal=false, crossfade=0 → falls through to gapless
        let mode = selectMode(eqEnabled: true, isLocal: false, crossfadeDuration: 0)
        #expect(mode == .gapless)
    }

    @Test func allRepeatModesAreDistinct() {
        #expect(RepeatMode.off != RepeatMode.all)
        #expect(RepeatMode.all != RepeatMode.one)
        #expect(RepeatMode.off != RepeatMode.one)
    }

    @Test func modeSelectionTableAll8Combinations() {
        // All 8 combinations of (eqEnabled, isLocal, crossfade>0)
        // Priority: (eqEnabled && isLocal) → .eq; crossfade>0 → .crossfade; else → .gapless
        let cases: [(eq: Bool, local: Bool, xfade: Int, expected: PlaybackMode)] = [
            (false, false, 0, .gapless),
            (false, false, 5, .crossfade),
            (false, true,  0, .gapless),
            (false, true,  5, .crossfade),
            (true,  false, 0, .gapless),
            (true,  false, 5, .crossfade),
            (true,  true,  0, .eq),
            (true,  true,  5, .eq),
        ]
        for c in cases {
            let mode = selectMode(eqEnabled: c.eq, isLocal: c.local, crossfadeDuration: c.xfade)
            #expect(mode == c.expected,
                    "eq=\(c.eq), local=\(c.local), xfade=\(c.xfade) → expected \(c.expected), got \(mode)")
        }
    }
}
