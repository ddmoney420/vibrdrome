import Foundation

/// Tri-state filter value: no filter, must be true, or must be false.
enum TriState: String, CaseIterable, Sendable, Equatable {
    case none, yes, no

    /// Returns true if the value satisfies this filter (`.none` always passes).
    func matches(_ value: Bool) -> Bool {
        switch self {
        case .none: true
        case .yes: value
        case .no: !value
        }
    }
}

/// Observable filter state for library filter sidebars (albums, artists, songs).
/// All filtering is done locally against SwiftData.
@Observable
final class LibraryFilter: @unchecked Sendable {
    var isFavorited: TriState = .none
    var isRated: TriState = .none
    var isRecentlyPlayed: Bool = false
    var selectedArtistIds: Set<String> = []
    var selectedGenres: Set<String> = []
    var selectedLabels: Set<String> = []
    var year: Int?

    var isActive: Bool {
        isFavorited != .none ||
        isRated != .none ||
        isRecentlyPlayed ||
        !selectedArtistIds.isEmpty ||
        !selectedGenres.isEmpty ||
        !selectedLabels.isEmpty ||
        year != nil
    }

    var activeFilterCount: Int {
        var count = 0
        if isFavorited != .none { count += 1 }
        if isRated != .none { count += 1 }
        if isRecentlyPlayed { count += 1 }
        if !selectedArtistIds.isEmpty { count += 1 }
        if !selectedGenres.isEmpty { count += 1 }
        if !selectedLabels.isEmpty { count += 1 }
        if year != nil { count += 1 }
        return count
    }

    func reset() {
        isFavorited = .none
        isRated = .none
        isRecentlyPlayed = false
        selectedArtistIds = []
        selectedGenres = []
        selectedLabels = []
        year = nil
    }
}
