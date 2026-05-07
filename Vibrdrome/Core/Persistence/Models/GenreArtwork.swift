import Foundation
import SwiftData

/// Caches the cover art ID of a representative album for a given genre so the
/// Genres screen can show real album artwork instead of generated icons.
@Model
final class GenreArtwork {
    @Attribute(.unique) var genre: String = ""
    var coverArtId: String = ""
    var updatedAt: Date = Date()

    init(genre: String, coverArtId: String) {
        self.genre = genre
        self.coverArtId = coverArtId
        self.updatedAt = Date()
    }
}
