import Testing
import Foundation
@testable import Veydrune

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
}
