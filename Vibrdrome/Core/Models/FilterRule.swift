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
    case suffix         // file extension
    case contentType    // codec
    case comment
    case explicitStatus // explicit content flag string
    case mbzRecordingId // MusicBrainz Recording ID
    case mbzAlbumId     // MusicBrainz Album ID
    case mbzArtistId    // MusicBrainz Artist ID
    case mbzAlbumArtistId
    case mbzReleaseTrackId
    case mbzReleaseGroupId

    // Numeric fields
    case year
    case duration       // seconds
    case size           // bytes
    case channels       // audio channels
    case bitRate        // kbps
    case bitDepth
    case sampleRate
    case bpm
    case playCount
    case rating         // 1-5 stars (0 = unrated)
    case averageRating  // average across all users
    case albumRating
    case albumPlayCount
    case artistRating
    case artistPlayCount
    case trackNumber
    case discNumber

    // Date-relative fields (value = number of days for inTheLast/notInTheLast)
    case lastPlayed
    case dateLoved      // track loved date
    case dateRated      // track rated date
    case dateAdded
    case dateModified
    case albumLastPlayed
    case albumDateLoved
    case albumDateRated
    case artistLastPlayed
    case artistDateLoved
    case artistDateRated

    // Boolean fields
    case isFavorited
    case albumFavorited
    case artistFavorited
    case hasCoverArt
    case isCompilation
    case isMissing
    case isDownloaded

    // Playlist membership (value = playlist ID string)
    case inPlaylist
    case notInPlaylist

    var displayName: String {
        switch self {
        case .title:           "Title"
        case .artist:          "Artist"
        case .albumTitle:      "Album"
        case .genre:           "Genre"
        case .label:           "Label"
        case .suffix:          "Format"
        case .contentType:     "Codec"
        case .comment:         "Comment"
        case .explicitStatus:  "Explicit Status"
        case .mbzRecordingId:  "MBZ Recording ID"
        case .mbzAlbumId:      "MBZ Album ID"
        case .mbzArtistId:     "MBZ Artist ID"
        case .mbzAlbumArtistId: "MBZ Album Artist ID"
        case .mbzReleaseTrackId: "MBZ Release Track ID"
        case .mbzReleaseGroupId: "MBZ Release Group ID"
        case .year:            "Year"
        case .duration:        "Duration (s)"
        case .size:            "File Size"
        case .channels:        "Channels"
        case .bitRate:         "Bit Rate (kbps)"
        case .bitDepth:        "Bit Depth"
        case .sampleRate:      "Sample Rate"
        case .bpm:             "BPM"
        case .playCount:       "Play Count"
        case .averageRating:   "Avg Rating"
        case .rating:          "Rating"
        case .albumRating:     "Album Rating"
        case .albumPlayCount:  "Album Play Count"
        case .artistRating:    "Artist Rating"
        case .artistPlayCount: "Artist Play Count"
        case .trackNumber:     "Track #"
        case .discNumber:      "Disc #"
        case .lastPlayed:      "Last Played"
        case .dateLoved:       "Date Loved"
        case .dateRated:       "Date Rated"
        case .dateAdded:       "Date Added"
        case .dateModified:    "Date Modified"
        case .albumLastPlayed: "Album Last Played"
        case .albumDateLoved:  "Album Date Loved"
        case .albumDateRated:  "Album Date Rated"
        case .artistLastPlayed: "Artist Last Played"
        case .artistDateLoved: "Artist Date Loved"
        case .artistDateRated: "Artist Date Rated"
        case .isFavorited:     "Loved"
        case .albumFavorited:  "Album Loved"
        case .artistFavorited: "Artist Loved"
        case .hasCoverArt:     "Has Cover Art"
        case .isCompilation:   "Compilation"
        case .isMissing:       "File Missing"
        case .isDownloaded:    "Is Downloaded"
        case .inPlaylist:      "In Playlist"
        case .notInPlaylist:   "Not In Playlist"
        }
    }

    var kind: FieldKind {
        switch self {
        case .title, .artist, .albumTitle, .genre, .label, .suffix, .contentType, .comment,
             .explicitStatus, .mbzRecordingId, .mbzAlbumId, .mbzArtistId, .mbzAlbumArtistId,
             .mbzReleaseTrackId, .mbzReleaseGroupId:
            return .text
        case .year, .duration, .size, .channels, .bitRate, .bitDepth, .sampleRate, .bpm,
             .playCount, .rating, .averageRating, .albumRating, .albumPlayCount,
             .artistRating, .artistPlayCount, .trackNumber, .discNumber:
            return .numeric
        case .lastPlayed, .dateLoved, .dateRated, .dateAdded, .dateModified,
             .albumLastPlayed, .albumDateLoved, .albumDateRated,
             .artistLastPlayed, .artistDateLoved, .artistDateRated:
            return .days
        case .isFavorited, .albumFavorited, .artistFavorited,
             .hasCoverArt, .isCompilation, .isMissing, .isDownloaded:
            return .boolean
        case .inPlaylist, .notInPlaylist:
            return .playlist
        }
    }

    enum FieldKind { case text, numeric, days, boolean, playlist }
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

    // Days-ago operators (for date fields)
    case inTheLast
    case notInTheLast
    case before         // absolute date "YYYY-MM-DD"
    case after          // absolute date "YYYY-MM-DD"

    // Boolean operator
    case isTrue

    // Playlist membership (no argument — field holds the playlist ID)
    case isInPlaylist

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
        case .isLessOrEqual:   "≤"
        case .isBetween:       "between"
        case .inTheLast:       "in the last"
        case .notInTheLast:    "not in the last"
        case .before:          "before"
        case .after:           "after"
        case .isTrue:          "is"
        case .isInPlaylist:    "in playlist"
        }
    }

    static func allowed(for kind: FilterField.FieldKind) -> [FilterOperator] {
        switch kind {
        case .text:
            return [.contains, .notContains, .equals, .notEquals, .startsWith, .endsWith, .matchesRegex]
        case .numeric:
            return [.isEqualTo, .isNotEqualTo, .isGreaterThan, .isLessThan, .isGreaterOrEqual, .isLessOrEqual, .isBetween]
        case .days:
            return [.inTheLast, .notInTheLast, .before, .after]
        case .boolean:
            return [.isTrue]
        case .playlist:
            return [.isInPlaylist]
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
        case .text:     return .text("")
        case .numeric:  return .number(0)
        case .days:     return .number(30)
        case .boolean:  return .boolean(true)
        case .playlist: return .text("")
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

        case .days:
            // Local evaluation not meaningful for date fields — server handles it.
            return true

        case .boolean:
            guard case .boolean(let expected) = value else { return true }
            return target.boolValue(for: field) == expected

        case .playlist:
            // Playlist membership cannot be evaluated locally — server handles it.
            return true
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

// MARK: - Field Sets

extension FilterField {
    static let songFields: [FilterField] = [
        // Text
        .title, .artist, .albumTitle, .genre, .label, .suffix, .contentType, .comment,
        // Numeric
        .year, .duration, .size, .channels, .bitRate, .bitDepth, .sampleRate, .bpm,
        .playCount, .rating, .averageRating, .albumRating, .albumPlayCount,
        .artistRating, .artistPlayCount, .trackNumber, .discNumber,
        // Date-relative
        .lastPlayed, .dateLoved, .dateRated, .dateAdded, .dateModified,
        .albumLastPlayed, .albumDateLoved, .albumDateRated,
        .artistLastPlayed, .artistDateLoved, .artistDateRated,
        // Boolean
        .isFavorited, .albumFavorited, .artistFavorited,
        .hasCoverArt, .isCompilation, .isMissing, .isDownloaded,
    ]
    static let albumFields: [FilterField] = [
        .albumTitle, .artist, .genre, .label,
        .year, .duration, .rating, .albumRating,
        .isFavorited, .isDownloaded,
    ]
    static let artistFields: [FilterField] = [
        .artist, .genre,
        .isFavorited,
    ]

    /// Fields available in the smart playlist editor (server-evaluated; excludes local-only fields).
    static let smartPlaylistFields: [FilterField] = [
        // Text
        .title, .artist, .albumTitle, .genre, .label, .suffix, .contentType, .comment,
        .explicitStatus,
        .mbzRecordingId, .mbzAlbumId, .mbzArtistId, .mbzAlbumArtistId,
        .mbzReleaseTrackId, .mbzReleaseGroupId,
        // Numeric
        .year, .duration, .size, .channels, .bitRate, .bitDepth, .sampleRate, .bpm,
        .playCount, .rating, .averageRating, .albumRating, .albumPlayCount,
        .artistRating, .artistPlayCount, .trackNumber, .discNumber,
        // Date-relative
        .lastPlayed, .dateLoved, .dateRated, .dateAdded, .dateModified,
        .albumLastPlayed, .albumDateLoved, .albumDateRated,
        .artistLastPlayed, .artistDateLoved, .artistDateRated,
        // Boolean
        .isFavorited, .albumFavorited, .artistFavorited,
        .hasCoverArt, .isCompilation, .isMissing,
        // Playlist membership
        .inPlaylist, .notInPlaylist,
    ]
}

// MARK: - Rule Set

struct FilterRuleSet: Codable, Sendable, Equatable {
    enum Combinator: String, Codable, Sendable { case all, any }

    var combinator: Combinator = .all
    var rules: [FilterRule] = []

    var isEmpty: Bool { rules.allSatisfy(\.isEffectivelyEmpty) }

    /// True when any active rule targets a field that requires CachedSong lookup
    /// (fields not carried on the Song value type — stored in CachedSong or its album relationship).
    var needsCachedSong: Bool {
        let cachedFields: Set<FilterField> = [
            .playCount, .rating, .albumRating, .albumFavorited, .albumPlayCount,
            .artistRating, .artistPlayCount, .artistFavorited,
            .bitDepth, .sampleRate, .size, .channels, .comment,
            .hasCoverArt, .isCompilation, .dateAdded,
        ]
        return rules.contains { !$0.isEffectivelyEmpty && cachedFields.contains($0.field) }
    }

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
        let label: String?
        let suffix: String?
        let contentType: String?
        let comment: String?
        let year: Int?
        let duration: Int?
        let bitRate: Int?
        let bitDepth: Int?
        let samplingRate: Int?
        let bpm: Int?
        let playCount: Int
        let rating: Int
        let albumRating: Int
        let trackNumber: Int?
        let discNumber: Int?
        let isFavorited: Bool
        let albumFavorited: Bool
        let isDownloaded: Bool
        let hasCoverArt: Bool
        let isCompilation: Bool
        let size: Int?
        let channels: Int?
        let mbzRecordingId: String?
        let dateAdded: Date?
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
        case .label:       return label
        case .suffix:      return suffix
        case .contentType: return contentType
        case .comment:         return comment
        case .mbzRecordingId:  return mbzRecordingId
        default:               return nil
        }
    }
    func numericValue(for field: FilterField) -> Int? {
        switch field {
        case .year:        return year
        case .duration:    return duration
        case .bitRate:     return bitRate
        case .bitDepth:    return bitDepth
        case .sampleRate:  return samplingRate
        case .bpm:         return bpm
        case .playCount:   return playCount
        case .rating:      return rating
        case .albumRating: return albumRating
        case .trackNumber: return trackNumber
        case .discNumber:  return discNumber
        case .size:        return size
        case .channels:    return channels
        default:           return nil
        }
    }
    func boolValue(for field: FilterField) -> Bool {
        switch field {
        case .isFavorited:    return isFavorited
        case .albumFavorited: return albumFavorited
        case .isDownloaded:   return isDownloaded
        case .hasCoverArt:    return hasCoverArt
        case .isCompilation:  return isCompilation
        default:              return false
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
        case .year:               return year
        case .duration:           return duration
        case .rating, .albumRating: return rating
        default:                  return nil
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
