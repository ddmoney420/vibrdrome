import Testing
import Foundation
@testable import Vibrdrome

struct LosslessBadgeTests {

    /// Replicates the lossless detection logic from AlbumDetailView.
    private static let losslessFormats: Set<String> = ["flac", "alac", "wav", "aiff"]

    private func isLossless(_ suffix: String?) -> Bool {
        guard let suffix else { return false }
        return Self.losslessFormats.contains(suffix.lowercased())
    }

    @Test func flacIsLossless() {
        #expect(isLossless("flac"))
    }

    @Test func alacIsLossless() {
        #expect(isLossless("alac"))
    }

    @Test func wavIsLossless() {
        #expect(isLossless("wav"))
    }

    @Test func aiffIsLossless() {
        #expect(isLossless("aiff"))
    }

    @Test func mp3IsNotLossless() {
        #expect(!isLossless("mp3"))
    }

    @Test func aacIsNotLossless() {
        #expect(!isLossless("aac"))
    }

    @Test func nilSuffixIsNotLossless() {
        #expect(!isLossless(nil))
    }

    @Test func caseInsensitive() {
        #expect(isLossless("FLAC"))
        #expect(isLossless("Wav"))
        #expect(isLossless("AIFF"))
        #expect(isLossless("Alac"))
    }
}
