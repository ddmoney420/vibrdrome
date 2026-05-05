import Foundation

/// Which entity type the filter sidebar / filter window is controlling.
enum FilterContext: String, Codable, Hashable, CaseIterable {
    case album, artist, song

    var windowTitle: String {
        switch self {
        case .album:  "Album Filters"
        case .artist: "Artist Filters"
        case .song:   "Song Filters"
        }
    }
}
