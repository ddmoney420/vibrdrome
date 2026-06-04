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
/// Note: Sendable conformance is implicit via @MainActor isolation (Swift 6 strict concurrency).
@Observable
@MainActor
final class LibraryFilter {
    var isFavorited: TriState = .none
    var isRated: TriState = .none
    var isCompilation: TriState = .none
    var isRecentlyPlayed: Bool = false
    var selectedArtistIds: Set<String> = []
    var selectedGenres: Set<String> = []
    var selectedLabels: Set<String> = []
    var year: Int?
    var ruleSet: FilterRuleSet = FilterRuleSet() { didSet { persistRuleSet() } }
    var matchCount: Int?
    var ruleSetPersistenceKey: String?

    var isActive: Bool {
        isFavorited != .none ||
        isRated != .none ||
        isCompilation != .none ||
        isRecentlyPlayed ||
        !selectedArtistIds.isEmpty ||
        !selectedGenres.isEmpty ||
        !selectedLabels.isEmpty ||
        year != nil ||
        !ruleSet.isEmpty
    }

    var activeFilterCount: Int {
        var count = 0
        if isFavorited != .none { count += 1 }
        if isRated != .none { count += 1 }
        if isCompilation != .none { count += 1 }
        if isRecentlyPlayed { count += 1 }
        if !selectedArtistIds.isEmpty { count += 1 }
        if !selectedGenres.isEmpty { count += 1 }
        if !selectedLabels.isEmpty { count += 1 }
        if year != nil { count += 1 }
        if !ruleSet.isEmpty { count += 1 }
        return count
    }

    func reset() {
        isFavorited = .none
        isRated = .none
        isCompilation = .none
        isRecentlyPlayed = false
        selectedArtistIds = []
        selectedGenres = []
        selectedLabels = []
        year = nil
        ruleSet = FilterRuleSet()
        matchCount = nil
    }

    func loadRuleSet(from key: String) {
        ruleSetPersistenceKey = key
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(FilterRuleSet.self, from: data) else { return }
        ruleSet = decoded
    }

    private func persistRuleSet() {
        guard let key = ruleSetPersistenceKey,
              let data = try? JSONEncoder().encode(ruleSet) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
