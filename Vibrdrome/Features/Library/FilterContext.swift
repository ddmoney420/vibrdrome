/// Which entity type the filter sidebar is controlling.
enum FilterContext: Hashable, Codable {
    case album, artist, song

    var windowTitle: String {
        switch self {
        case .album:  "Album Filters"
        case .artist: "Artist Filters"
        case .song:   "Song Filters"
        }
    }
}
