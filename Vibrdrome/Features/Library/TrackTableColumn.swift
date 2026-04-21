#if os(macOS)
import Foundation

// MARK: - Column Definition

enum TrackTableColumn: String, CaseIterable, Codable, Identifiable, Sendable {
    case trackNumber
    case title
    case artist
    case album
    case duration
    case year
    case genre
    case bitRate
    case format
    case bpm
    case dateAdded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trackNumber: return "#"
        case .title:       return "Title"
        case .artist:      return "Artist"
        case .album:       return "Album"
        case .duration:    return "Time"
        case .year:        return "Year"
        case .genre:       return "Genre"
        case .bitRate:     return "Bitrate"
        case .format:      return "Format"
        case .bpm:         return "BPM"
        case .dateAdded:   return "Date Added"
        }
    }

    /// Minimum column width in points.
    var minWidth: CGFloat {
        switch self {
        case .trackNumber: return 36
        case .title:       return 180
        case .artist:      return 140
        case .album:       return 140
        case .duration:    return 56
        case .year:        return 52
        case .genre:       return 100
        case .bitRate:     return 72
        case .format:      return 60
        case .bpm:         return 52
        case .dateAdded:   return 110
        }
    }

    /// Whether the column is flexible (expands to fill remaining space).
    var isFlexible: Bool {
        switch self {
        case .title, .artist, .album, .genre: return true
        default: return false
        }
    }

    /// `true` → column can be hidden by the user.
    var isRemovable: Bool { self != .title }

    /// Default visibility when no saved preference exists.
    var isOnByDefault: Bool {
        switch self {
        case .trackNumber, .title, .artist, .album, .duration: return true
        default: return false
        }
    }

    /// `true` → clicking the column header cycles sort on this field.
    var isSortable: Bool {
        switch self {
        case .trackNumber, .format: return false
        default: return true
        }
    }
}

// MARK: - Column Entry (order + visibility tuple)

struct TrackTableColumnEntry: Codable, Identifiable, Equatable {
    var id: String { column.rawValue }
    var column: TrackTableColumn
    var visible: Bool
}
#endif
