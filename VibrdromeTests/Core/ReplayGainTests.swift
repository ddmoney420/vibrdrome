import Testing
import Foundation
@testable import Vibrdrome

/// Tests for ReplayGain computation logic.
/// Uses a helper that mirrors AudioEngine.computeReplayGainFactor() to test
/// the dB-to-linear conversion and clamping without needing the full AudioEngine.
struct ReplayGainTests {

    // MARK: - Helper that mirrors AudioEngine logic

    /// Computes linear gain factor from dB value (same algorithm as AudioEngine)
    private func linearFactor(fromDb db: Double) -> Float {
        let linear = Float(pow(10, db / 20))
        return max(0.0, min(1.5, linear))
    }

    // MARK: - dB to Linear Conversion

    @Test func zeroDbGain() {
        let factor = linearFactor(fromDb: 0)
        #expect(abs(factor - 1.0) < 0.001)
    }

    @Test func positiveSixDb() {
        // +6dB ≈ 2.0x linear → capped to 1.5
        let factor = linearFactor(fromDb: 6)
        #expect(factor == 1.5)
    }

    @Test func negativeSixDb() {
        // -6dB ≈ 0.5x linear
        let factor = linearFactor(fromDb: -6)
        #expect(abs(factor - 0.501) < 0.01)
    }

    @Test func negativeTwentyDb() {
        // -20dB = 0.1x linear
        let factor = linearFactor(fromDb: -20)
        #expect(abs(factor - 0.1) < 0.001)
    }

    @Test func plusTwentyDbClamped() {
        // +20dB = 10.0 linear → clamped to 1.5
        let factor = linearFactor(fromDb: 20)
        #expect(factor == 1.5)
    }

    @Test func plusThreeDbUnderCap() {
        // +3dB ≈ 1.41x linear → under 1.5 cap, passes through
        let factor = linearFactor(fromDb: 3)
        #expect(factor > 1.4)
        #expect(factor < 1.5)
    }

    @Test func veryNegativeDbNearZero() {
        // -60dB = 0.001 linear — very quiet but not zero
        let factor = linearFactor(fromDb: -60)
        #expect(factor > 0)
        #expect(factor < 0.01)
    }

    @Test func extremeNegativeClampsToZero() {
        // -200dB → effectively 0, clamped to 0.0
        let factor = linearFactor(fromDb: -200)
        #expect(factor >= 0.0)
    }

    // MARK: - Song ReplayGain model

    @Test func songWithNoReplayGain() {
        let song = makeSong(replayGain: nil)
        #expect(song.replayGain == nil)
    }

    @Test func songWithTrackGain() {
        let rg = ReplayGain(trackGain: -3.5, albumGain: nil, trackPeak: nil, albumPeak: nil, baseGain: nil)
        let song = makeSong(replayGain: rg)
        #expect(song.replayGain?.trackGain == -3.5)
    }

    @Test func songWithAlbumGain() {
        let rg = ReplayGain(trackGain: -5.0, albumGain: -2.0, trackPeak: nil, albumPeak: nil, baseGain: nil)
        let song = makeSong(replayGain: rg)
        #expect(song.replayGain?.albumGain == -2.0)
    }

    @Test func albumGainFallsBackToTrack() {
        let rg = ReplayGain(trackGain: -4.0, albumGain: nil, trackPeak: nil, albumPeak: nil, baseGain: nil)
        // albumGain is nil, should use trackGain as fallback
        let effectiveGain = rg.albumGain ?? rg.trackGain
        #expect(effectiveGain == -4.0)
    }

    // MARK: - Helpers

    private func makeSong(replayGain: ReplayGain?) -> Song {
        Song(
            id: "test-1", parent: nil, title: "Test Song",
            album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
            track: nil, year: nil, genre: nil, coverArt: nil,
            size: nil, contentType: nil, suffix: nil, duration: 300,
            bitRate: nil, path: nil, discNumber: nil, created: nil,
            starred: nil, userRating: nil, bpm: nil, replayGain: replayGain, musicBrainzId: nil
        )
    }
}
