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
    var isRecentlyPlayed: Bool = false
    var selectedArtistIds: Set<String> = []
    var selectedGenres: Set<String> = []
    var selectedLabels: Set<String> = []
    var year: Int?

    /// Advanced rule-set filter (regex / operator-based, persisted separately).
    var ruleSet: FilterRuleSet = .init() {
        didSet { persistRuleSet() }
    }

    /// Live result count written back by the library view after each filter pass. Nil when filter is inactive.
    var matchCount: Int?

    /// UserDefaults key used to persist this filter's rule set. Set once after init.
    var ruleSetPersistenceKey: String?

    var isActive: Bool {
        isFavorited != .none ||
        isRated != .none ||
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
        isRecentlyPlayed = false
        selectedArtistIds = []
        selectedGenres = []
        selectedLabels = []
        year = nil
        ruleSet = .init()
        matchCount = nil
    }

    // MARK: Persistence

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
