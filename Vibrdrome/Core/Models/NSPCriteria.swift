import Foundation

// MARK: - NSP Criteria

/// Navidrome Smart Playlist criteria, matching the .nsp JSON format.
/// Sent as the `rules` field in the Navidrome native REST API.
///
/// Format mirrors the Navidrome `model/criteria` package:
///   { "all": [ { "contains": { "title": "love" } }, … ], "sort": "rating", "order": "desc", "limit": 100 }
struct NSPCriteria: Codable, Sendable {
    enum Combinator: String, Codable, Sendable { case all, any }

    var combinator: Combinator
    var expressions: [NSPExpression]
    var sort: String?
    var order: String?
    var limit: Int?
    var limitPercent: Int?

    // MARK: Codable

    enum CodingKeys: String, CodingKey { case all, any, sort, order, limit, limitPercent }

    init(combinator: Combinator = .all, expressions: [NSPExpression] = [],
         sort: String? = nil, order: String? = nil, limit: Int? = nil, limitPercent: Int? = nil) {
        self.combinator = combinator
        self.expressions = expressions
        self.sort = sort
        self.order = order
        self.limit = limit
        self.limitPercent = limitPercent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sort = try c.decodeIfPresent(String.self, forKey: .sort)
        order = try c.decodeIfPresent(String.self, forKey: .order)
        limit = try c.decodeIfPresent(Int.self, forKey: .limit)
        limitPercent = try c.decodeIfPresent(Int.self, forKey: .limitPercent)
        if let all = try c.decodeIfPresent([NSPExpression].self, forKey: .all) {
            combinator = .all; expressions = all
        } else if let any = try c.decodeIfPresent([NSPExpression].self, forKey: .any) {
            combinator = .any; expressions = any
        } else {
            // Mirror Navidrome: criteria must have an 'all' or 'any' key.
            throw DecodingError.dataCorruptedError(
                forKey: .all,
                in: c,
                debugDescription: "NSPCriteria missing required 'all' or 'any' key"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(sort, forKey: .sort)
        try c.encodeIfPresent(order, forKey: .order)
        try c.encodeIfPresent(limit, forKey: .limit)
        try c.encodeIfPresent(limitPercent, forKey: .limitPercent)
        switch combinator {
        case .all: try c.encode(expressions, forKey: .all)
        case .any: try c.encode(expressions, forKey: .any)
        }
    }

    /// Serialize to a plain `[String: Any]` dictionary for embedding in an API request body.
    func toJSON() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - NSP Expression

/// One rule node in the NSP format: `{ "<operator>": { "<field>": <value> } }`.
/// Also handles nested `all`/`any` conjunctions.
indirect enum NSPExpression: Codable, Sendable {
    case leaf(operator: String, field: String, value: NSPValue)
    case conjunction(NSPCriteria)

    // Operator names recognised by Navidrome (lowercased for comparison).
    private static let leafOperators: Set<String> = [
        "is", "isnot", "gt", "lt", "contains", "notcontains",
        "startswith", "endswith", "intherange",
        "before", "after", "inthelast", "notinthelast",
        "inplaylist", "notinplaylist", "ismissing", "ispresent",
    ]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Decode as a raw single-key dict to inspect the operator name first,
        // mirroring Navidrome's unmarshalConjunctionType logic exactly:
        // known leaf operators → leaf; "all"/"any" → nested conjunction.
        let raw = try container.decode([String: NSPRawValue].self)
        guard let (key, rawValue) = raw.first else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Empty NSP expression")
        }
        let lowerKey = key.lowercased()
        if NSPExpression.leafOperators.contains(lowerKey) {
            // Leaf: { "<op>": { "<field>": <value> } }
            guard case .object(let fieldMap) = rawValue,
                  let (field, nspVal) = fieldMap.first else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid leaf expression for op '\(key)'")
            }
            self = .leaf(operator: key, field: field, value: nspVal)
        } else if lowerKey == "all" || lowerKey == "any" {
            // Nested conjunction: { "all": [...] } or { "any": [...] }
            let nested = try container.decode(NSPCriteria.self)
            self = .conjunction(nested)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown NSP expression key '\(key)'")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .conjunction(let crit):
            try container.encode(crit)
        case .leaf(let op, let field, let value):
            try container.encode([op: [field: value]])
        }
    }
}

// MARK: - NSP Raw Value (expression decoding helper)

/// Intermediate decoded shape for one side of an NSP expression dict.
/// Used by `NSPExpression.init(from:)` to inspect the key before committing to a type.
private enum NSPRawValue: Decodable {
    case object([String: NSPValue])
    case array([NSPExpression])
    case other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let obj = try? c.decode([String: NSPValue].self) { self = .object(obj); return }
        if let arr = try? c.decode([NSPExpression].self)    { self = .array(arr);  return }
        self = .other
    }
}

// MARK: - NSP Value

/// A value in an NSP expression. Can be a string, int, bool, float, or a two-element range array.
indirect enum NSPValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case double(Double)
    case range(NSPValue, NSPValue)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self)   { self = .bool(b);   return }
        if let i = try? c.decode(Int.self)    { self = .int(i);    return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let arr = try? c.decode([NSPValue].self), arr.count == 2 {
            self = .range(arr[0], arr[1]); return
        }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported NSPValue")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i):    try c.encode(i)
        case .bool(let b):   try c.encode(b)
        case .double(let d): try c.encode(d)
        case .range(let lo, let hi): try c.encode([lo, hi])
        }
    }
}

// MARK: - FilterRuleSet → NSPCriteria mapping

extension NSPCriteria {

    /// Convert a `FilterRuleSet` (local filter model) to an `NSPCriteria` (Navidrome native format).
    init(from ruleSet: FilterRuleSet, sort: String? = nil, order: String? = nil, limit: Int? = nil) {
        let expressions = ruleSet.rules
            .filter { !$0.isEffectivelyEmpty }
            .compactMap { NSPExpression(from: $0) }

        self.init(
            combinator: ruleSet.combinator == .all ? .all : .any,
            expressions: expressions,
            sort: sort,
            order: order,
            limit: limit
        )
    }
}

extension NSPExpression {

    /// Map a single `FilterRule` to an `NSPExpression`.
    /// Returns nil for rules that have no valid NSP mapping.
    init?(from rule: FilterRule) {
        guard !rule.isEffectivelyEmpty else { return nil }
        guard let (op, field, value) = rule.toNSP() else { return nil }
        self = .leaf(operator: op, field: field, value: value)
    }
}

// MARK: - FilterRule → (operator, field, value)

private extension FilterRule {

    func toNSP() -> (op: String, field: String, value: NSPValue)? {
        switch self.field.kind {
        case .playlist: return playlistNSP()
        default:
            guard let field = self.field.nspField else { return nil }
            switch self.field.kind {
            case .text:    return textNSP(field: field)
            case .numeric: return numericNSP(field: field)
            case .days:    return daysNSP(field: field)
            case .boolean: return booleanNSP(field: field)
            case .playlist: return nil  // handled above
            }
        }
    }

    // MARK: Text

    private func textNSP(field: String) -> (String, String, NSPValue)? {
        guard case .text(let pattern) = value else { return nil }
        switch `operator` {
        case .contains:     return ("contains", field, .string(pattern))
        case .notContains:  return ("notContains", field, .string(pattern))
        case .equals:       return ("is", field, .string(pattern))
        case .notEquals:    return ("isNot", field, .string(pattern))
        case .startsWith:   return ("startsWith", field, .string(pattern))
        case .endsWith:     return ("endsWith", field, .string(pattern))
        case .matchesRegex:
            // NSP doesn't have a regex operator; skip silently.
            return nil
        default:            return nil
        }
    }

    // MARK: Numeric

    private func numericNSP(field: String) -> (String, String, NSPValue)? {
        switch value {
        case .number(let n):
            switch `operator` {
            case .isEqualTo:       return ("is", field, .int(n))
            case .isNotEqualTo:    return ("isNot", field, .int(n))
            case .isGreaterThan:   return ("gt", field, .int(n))
            case .isLessThan:      return ("lt", field, .int(n))
            case .isGreaterOrEqual:
                // NSP has no ≥; emulate with gt(n-1) for integer fields.
                return ("gt", field, .int(n - 1))
            case .isLessOrEqual:
                // NSP has no ≤; emulate with lt(n+1) for integer fields.
                return ("lt", field, .int(n + 1))
            default: return nil
            }
        case .range(let lo, let hi):
            guard `operator` == .isBetween else { return nil }
            return ("inTheRange", field, .range(.int(lo), .int(hi)))
        default:
            return nil
        }
    }

    // MARK: Days (inTheLast / notInTheLast / before / after)

    private func daysNSP(field: String) -> (String, String, NSPValue)? {
        switch `operator` {
        case .inTheLast:
            guard case .number(let n) = value else { return nil }
            return ("inTheLast", field, .int(n))
        case .notInTheLast:
            guard case .number(let n) = value else { return nil }
            return ("notInTheLast", field, .int(n))
        case .before:
            guard case .text(let date) = value, !date.isEmpty else { return nil }
            return ("before", field, .string(date))
        case .after:
            guard case .text(let date) = value, !date.isEmpty else { return nil }
            return ("after", field, .string(date))
        default: return nil
        }
    }

    // MARK: Boolean

    private func booleanNSP(field: String) -> (String, String, NSPValue)? {
        guard case .boolean(let flag) = value else { return nil }
        // NSP uses `is` for booleans: { "is": { "loved": true } }
        return ("is", field, .bool(flag))
    }

    // MARK: Playlist membership
    // NSP format: { "inPlaylist": { "id": "<playlistId>" } }
    // The "field" key inside inPlaylist/notInPlaylist is always "id".

    private func playlistNSP() -> (String, String, NSPValue)? {
        guard case .text(let playlistId) = value, !playlistId.isEmpty else { return nil }
        switch self.field {
        case .inPlaylist:    return ("inPlaylist", "id", .string(playlistId))
        case .notInPlaylist: return ("notInPlaylist", "id", .string(playlistId))
        default:             return nil
        }
    }
}

// MARK: - FilterField → NSP field name

private extension FilterField {
    /// Maps a Vibrdrome filter field to the corresponding Navidrome NSP field name.
    /// Returns nil for fields that have no valid NSP mapping (local-only fields).
    var nspField: String? {
        switch self {
        // Text
        case .title:              return "title"
        case .artist:             return "artist"
        case .albumTitle:         return "album"
        case .genre:              return "genre"
        case .label:              return "recordlabel"
        case .suffix:             return "filetype"
        case .contentType:        return "codec"
        case .comment:            return "comment"
        case .explicitStatus:     return "explicitstatus"
        case .mbzRecordingId:     return "mbz_recording_id"
        case .mbzAlbumId:         return "mbz_album_id"
        case .mbzArtistId:        return "mbz_artist_id"
        case .mbzAlbumArtistId:   return "mbz_album_artist_id"
        case .mbzReleaseTrackId:  return "mbz_release_track_id"
        case .mbzReleaseGroupId:  return "mbz_release_group_id"
        // Numeric
        case .year:               return "year"
        case .duration:           return "duration"
        case .size:               return "size"
        case .channels:           return "channels"
        case .bitRate:            return "bitrate"
        case .bitDepth:           return "bitdepth"
        case .sampleRate:         return "samplerate"
        case .bpm:                return "bpm"
        case .playCount:          return "playcount"
        case .rating:             return "rating"
        case .averageRating:      return "averagerating"
        case .albumRating:        return "albumrating"
        case .albumPlayCount:     return "albumplaycount"
        case .artistRating:       return "artistrating"
        case .artistPlayCount:    return "artistplaycount"
        case .trackNumber:        return "tracknumber"
        case .discNumber:         return "discnumber"
        // Date-relative
        case .lastPlayed:         return "lastplayed"
        case .dateLoved:          return "dateloved"
        case .dateRated:          return "daterated"
        case .dateAdded:          return "dateadded"
        case .dateModified:       return "datemodified"
        case .albumLastPlayed:    return "albumlastplayed"
        case .albumDateLoved:     return "albumdateloved"
        case .albumDateRated:     return "albumdaterated"
        case .artistLastPlayed:   return "artistlastplayed"
        case .artistDateLoved:    return "artistdateloved"
        case .artistDateRated:    return "artistdaterated"
        // Boolean
        case .isFavorited:        return "loved"
        case .albumFavorited:     return "albumloved"
        case .artistFavorited:    return "artistloved"
        case .hasCoverArt:        return "hascoverart"
        case .isCompilation:      return "compilation"
        case .isMissing:          return "missing"
        // Local-only — no server mapping
        case .isDownloaded:       return nil
        // Playlist membership — handled specially in playlistNSP(), not via nspField
        case .inPlaylist, .notInPlaylist: return nil
        }
    }
}
