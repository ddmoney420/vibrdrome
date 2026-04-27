import Foundation

// MARK: - Field

/// Metadata fields that can be targeted by a filter rule.
enum FilterField: String, CaseIterable, Codable, Sendable {
    // Text fields
    case title
    case artist
    case albumTitle
    case genre
    case label
    case suffix       // file extension / codec
    case contentType

    // Numeric fields
    case year
    case duration     // seconds
    case bitRate      // kbps
    case playCount
    case rating       // 1-5 stars (0 = unrated)
    case trackNumber
    case discNumber

    // Boolean fields
    case isFavorited
    case isDownloaded

    var displayName: String {
        switch self {
        case .title:       "Title"
        case .artist:      "Artist"
        case .albumTitle:  "Album"
        case .genre:       "Genre"
        case .label:       "Label"
        case .suffix:      "Format"
        case .contentType: "Content Type"
        case .year:        "Year"
        case .duration:    "Duration (s)"
        case .bitRate:     "Bit Rate (kbps)"
        case .playCount:   "Play Count"
        case .rating:      "Rating"
        case .trackNumber: "Track #"
        case .discNumber:  "Disc #"
        case .isFavorited: "Is Favorited"
        case .isDownloaded: "Is Downloaded"
        }
    }

    var kind: FieldKind {
        switch self {
        case .title, .artist, .albumTitle, .genre, .label, .suffix, .contentType:
            return .text
        case .year, .duration, .bitRate, .playCount, .rating, .trackNumber, .discNumber:
            return .numeric
        case .isFavorited, .isDownloaded:
            return .boolean
        }
    }

    enum FieldKind { case text, numeric, boolean }
}

// MARK: - Operator

enum FilterOperator: String, CaseIterable, Codable, Sendable {
    // Text operators
    case contains
    case notContains
    case equals
    case notEquals
    case startsWith
    case endsWith
    case matchesRegex

    // Numeric operators
    case isEqualTo
    case isNotEqualTo
    case isGreaterThan
    case isLessThan
    case isGreaterOrEqual
    case isLessOrEqual
    case isBetween

    // Boolean operator
    case isTrue

    var displayName: String {
        switch self {
        case .contains:        "contains"
        case .notContains:     "does not contain"
        case .equals:          "is"
        case .notEquals:       "is not"
        case .startsWith:      "starts with"
        case .endsWith:        "ends with"
        case .matchesRegex:    "matches regex"
        case .isEqualTo:       "="
        case .isNotEqualTo:    "≠"
        case .isGreaterThan:   ">"
        case .isLessThan:      "<"
        case .isGreaterOrEqual: "≥"
        case .isLessOrEqual: "≤"
        case .isBetween:       "between"
        case .isTrue:          "is"
        }
    }

    static func allowed(for kind: FilterField.FieldKind) -> [FilterOperator] {
        switch kind {
        case .text:
            return [.contains, .notContains, .equals, .notEquals, .startsWith, .endsWith, .matchesRegex]
        case .numeric:
            return [.isEqualTo, .isNotEqualTo, .isGreaterThan, .isLessThan, .isGreaterOrEqual, .isLessOrEqual, .isBetween]
        case .boolean:
            return [.isTrue]
        }
    }
}

// MARK: - Value

enum FilterValue: Codable, Sendable, Equatable {
    case text(String)
    case number(Int)
    case range(Int, Int)
    case boolean(Bool)

    private enum CodingKeys: String, CodingKey { case type, text, number, low, high, boolean }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":    self = .text(try c.decode(String.self, forKey: .text))
        case "number":  self = .number(try c.decode(Int.self, forKey: .number))
        case "range":   self = .range(try c.decode(Int.self, forKey: .low), try c.decode(Int.self, forKey: .high))
        case "boolean": self = .boolean(try c.decode(Bool.self, forKey: .boolean))
        default:        self = .text("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):
            try c.encode("text", forKey: .type); try c.encode(s, forKey: .text)
        case .number(let n):
            try c.encode("number", forKey: .type); try c.encode(n, forKey: .number)
        case .range(let lo, let hi):
            try c.encode("range", forKey: .type); try c.encode(lo, forKey: .low); try c.encode(hi, forKey: .high)
        case .boolean(let b):
            try c.encode("boolean", forKey: .type); try c.encode(b, forKey: .boolean)
        }
    }

    static func defaultValue(for kind: FilterField.FieldKind) -> FilterValue {
        switch kind {
        case .text:    return .text("")
        case .numeric: return .number(0)
        case .boolean: return .boolean(true)
        }
    }
}

// MARK: - Rule

struct FilterRule: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var field: FilterField
    var `operator`: FilterOperator
    var value: FilterValue

    init(id: UUID = UUID(), field: FilterField = .title, operator op: FilterOperator = .contains, value: FilterValue = .text("")) {
        self.id = id
        self.field = field
        self.operator = op
        self.value = value
    }

    /// True when the rule has no meaningful value and should be treated as a no-op.
    /// An empty text pattern or a boolean rule (which always has a value) is never empty.
    var isEffectivelyEmpty: Bool {
        switch value {
        case .text(let s):  return s.isEmpty
        case .number:       return false
        case .range:        return false
        case .boolean:      return false
        }
    }

    /// Returns true when the rule passes for the given metadata values.
    func matches(song: FilterRuleSet.SongMeta) -> Bool {
        evaluate(against: song)
    }

    func matches(album: FilterRuleSet.AlbumMeta) -> Bool {
        evaluate(against: album)
    }

    func matches(artist: FilterRuleSet.ArtistMeta) -> Bool {
        evaluate(against: artist)
    }

    // MARK: Private evaluation

    private func evaluate(against target: any FilterTarget) -> Bool {
        switch field.kind {
        case .text:
            guard case .text(let pattern) = value, !pattern.isEmpty else { return true }
            let haystack = target.textValue(for: field) ?? ""
            return matchText(haystack: haystack, pattern: pattern)

        case .numeric:
            let actual = target.numericValue(for: field)
            return matchNumeric(actual: actual)

        case .boolean:
            guard case .boolean(let expected) = value else { return true }
            return target.boolValue(for: field) == expected
        }
    }

    private func matchText(haystack: String, pattern: String) -> Bool {
        switch `operator` {
        case .contains:
            return haystack.localizedCaseInsensitiveContains(pattern)
        case .notContains:
            return !haystack.localizedCaseInsensitiveContains(pattern)
        case .equals:
            return haystack.localizedCaseInsensitiveCompare(pattern) == .orderedSame
        case .notEquals:
            return haystack.localizedCaseInsensitiveCompare(pattern) != .orderedSame
        case .startsWith:
            return haystack.lowercased().hasPrefix(pattern.lowercased())
        case .endsWith:
            return haystack.lowercased().hasSuffix(pattern.lowercased())
        case .matchesRegex:
            let (rawPattern, options) = Self.parseRegexLiteral(pattern)
            return (try? NSRegularExpression(pattern: rawPattern, options: options))
                .map { $0.firstMatch(in: haystack, range: NSRange(haystack.startIndex..., in: haystack)) != nil } ?? false
        default:
            return true
        }
    }

    /// Parses an optional `/pattern/flags` regex literal, returning the raw pattern and options.
    /// If the input doesn't start with `/`, it is returned as-is with no options (plain pattern).
    /// Supported flags: i (caseInsensitive), s (dotMatchesLineSeparators), m (anchorsMatchLines).
    static func parseRegexLiteral(_ input: String) -> (pattern: String, options: NSRegularExpression.Options) {
        guard input.hasPrefix("/") else { return (input, []) }
        // Find the closing slash — search from the second character onwards
        let afterOpen = input.index(after: input.startIndex)
        guard let closingSlash = input[afterOpen...].lastIndex(of: "/"), closingSlash != input.startIndex else {
            // Malformed (no closing slash) — treat the whole string as a plain pattern
            return (input, [])
        }
        let rawPattern = String(input[afterOpen..<closingSlash])
        let flagString = String(input[input.index(after: closingSlash)...])
        var options: NSRegularExpression.Options = []
        for flag in flagString {
            switch flag {
            case "i": options.insert(.caseInsensitive)
            case "s": options.insert(.dotMatchesLineSeparators)
            case "m": options.insert(.anchorsMatchLines)
            default: break
            }
        }
        return (rawPattern, options)
    }

    private func matchNumeric(actual: Int?) -> Bool {
        switch value {
        case .number(let n):
            guard let a = actual else { return false }
            switch `operator` {
            case .isEqualTo:       return a == n
            case .isNotEqualTo:    return a != n
            case .isGreaterThan:   return a > n
            case .isLessThan:      return a < n
            case .isGreaterOrEqual: return a >= n
            case .isLessOrEqual: return a <= n
            default: return true
            }
        case .range(let lo, let hi):
            guard `operator` == .isBetween, let a = actual else { return false }
            return a >= lo && a <= hi
        default:
            return true
        }
    }
}

// MARK: - Rule Set

struct FilterRuleSet: Codable, Sendable, Equatable {
    enum Combinator: String, Codable, Sendable { case all, any }

    var combinator: Combinator = .all
    var rules: [FilterRule] = []

    var isEmpty: Bool { rules.allSatisfy(\.isEffectivelyEmpty) }

    private var activeRules: [FilterRule] { rules.filter { !$0.isEffectivelyEmpty } }

    func matches(song: SongMeta) -> Bool {
        let active = activeRules
        guard !active.isEmpty else { return true }
        switch combinator {
        case .all: return active.allSatisfy { $0.matches(song: song) }
        case .any: return active.contains { $0.matches(song: song) }
        }
    }

    func matches(album: AlbumMeta) -> Bool {
        let active = activeRules
        guard !active.isEmpty else { return true }
        switch combinator {
        case .all: return active.allSatisfy { $0.matches(album: album) }
        case .any: return active.contains { $0.matches(album: album) }
        }
    }

    func matches(artist: ArtistMeta) -> Bool {
        let active = activeRules
        guard !active.isEmpty else { return true }
        switch combinator {
        case .all: return active.allSatisfy { $0.matches(artist: artist) }
        case .any: return active.contains { $0.matches(artist: artist) }
        }
    }

    // MARK: Metadata structs

    struct SongMeta {
        let title: String
        let artist: String?
        let albumTitle: String?
        let genre: String?
        let suffix: String?
        let contentType: String?
        let year: Int?
        let duration: Int?
        let bitRate: Int?
        let playCount: Int
        let rating: Int
        let trackNumber: Int?
        let discNumber: Int?
        let isFavorited: Bool
        let isDownloaded: Bool
    }

    struct AlbumMeta {
        let title: String
        let artist: String?
        let genre: String?
        let label: String?
        let year: Int?
        let duration: Int?
        let rating: Int
        let isFavorited: Bool
        let isDownloaded: Bool = false
    }

    struct ArtistMeta {
        let name: String
        let genre: String?
        let isFavorited: Bool
        let isDownloaded: Bool = false
    }
}

// MARK: - FilterTarget protocol (private)

private protocol FilterTarget {
    func textValue(for field: FilterField) -> String?
    func numericValue(for field: FilterField) -> Int?
    func boolValue(for field: FilterField) -> Bool
}

extension FilterRuleSet.SongMeta: FilterTarget {
    func textValue(for field: FilterField) -> String? {
        switch field {
        case .title:       return title
        case .artist:      return artist
        case .albumTitle:  return albumTitle
        case .genre:       return genre
        case .suffix:      return suffix
        case .contentType: return contentType
        default:           return nil
        }
    }
    func numericValue(for field: FilterField) -> Int? {
        switch field {
        case .year:        return year
        case .duration:    return duration
        case .bitRate:     return bitRate
        case .playCount:   return playCount
        case .rating:      return rating
        case .trackNumber: return trackNumber
        case .discNumber:  return discNumber
        default:           return nil
        }
    }
    func boolValue(for field: FilterField) -> Bool {
        switch field {
        case .isFavorited:  return isFavorited
        case .isDownloaded: return isDownloaded
        default:            return false
        }
    }
}

extension FilterRuleSet.AlbumMeta: FilterTarget {
    func textValue(for field: FilterField) -> String? {
        switch field {
        case .title, .albumTitle: return title
        case .artist:             return artist
        case .genre:              return genre
        case .label:              return label
        default:                  return nil
        }
    }
    func numericValue(for field: FilterField) -> Int? {
        switch field {
        case .year:     return year
        case .duration: return duration
        case .rating:   return rating
        default:        return nil
        }
    }
    func boolValue(for field: FilterField) -> Bool {
        switch field {
        case .isFavorited:  return isFavorited
        case .isDownloaded: return isDownloaded
        default:            return false
        }
    }
}

extension FilterRuleSet.ArtistMeta: FilterTarget {
    func textValue(for field: FilterField) -> String? {
        switch field {
        case .artist, .title: return name
        case .genre:          return genre
        default:              return nil
        }
    }
    func numericValue(for field: FilterField) -> Int? { nil }
    func boolValue(for field: FilterField) -> Bool {
        switch field {
        case .isFavorited:  return isFavorited
        case .isDownloaded: return isDownloaded
        default:            return false
        }
    }
}
