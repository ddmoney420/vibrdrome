import Foundation
import Testing
@testable import Vibrdrome

struct NSPCriteriaTests {

    // MARK: - FilterField → NSP field name

    @Test func textFieldsMappedCorrectly() {
        let pairs: [(FilterField, String)] = [
            (.title, "title"),
            (.artist, "artist"),
            (.albumTitle, "album"),
            (.genre, "genre"),
            (.label, "recordlabel"),
            (.suffix, "filetype"),
            (.contentType, "codec"),
        ]
        for (field, expected) in pairs {
            let rule = FilterRule(field: field, operator: .contains, value: .text("x"))
            let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
            #expect(criteria.expressions.count == 1)
            if case .leaf(let op, let f, _) = criteria.expressions[0] {
                #expect(f == expected, "Field \(field) should map to '\(expected)', got '\(f)'")
                #expect(op == "contains")
            }
        }
    }

    @Test func numericFieldsMappedCorrectly() {
        let pairs: [(FilterField, String)] = [
            (.year, "year"),
            (.duration, "duration"),
            (.bitRate, "bitrate"),
            (.playCount, "playcount"),
            (.rating, "rating"),
            (.trackNumber, "tracknumber"),
            (.discNumber, "discnumber"),
        ]
        for (field, expected) in pairs {
            let rule = FilterRule(field: field, operator: .isGreaterThan, value: .number(0))
            let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
            #expect(criteria.expressions.count == 1)
            if case .leaf(_, let f, _) = criteria.expressions[0] {
                #expect(f == expected)
            }
        }
    }

    @Test func isFavoritedMapsToLoved() {
        let rule = FilterRule(field: .isFavorited, operator: .isTrue, value: .boolean(true))
        let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
        #expect(criteria.expressions.count == 1)
        if case .leaf(let op, let field, let value) = criteria.expressions[0] {
            #expect(field == "loved")
            #expect(op == "is")
            if case .bool(let b) = value { #expect(b == true) }
        }
    }

    @Test func isDownloadedIsDropped() {
        let rule = FilterRule(field: .isDownloaded, operator: .isTrue, value: .boolean(true))
        let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
        #expect(criteria.expressions.isEmpty, "isDownloaded has no NSP mapping and should be dropped")
    }

    // MARK: - Operator mapping

    @Test func textOperators() {
        let cases: [(FilterOperator, String)] = [
            (.contains, "contains"),
            (.notContains, "notContains"),
            (.equals, "is"),
            (.notEquals, "isNot"),
            (.startsWith, "startsWith"),
            (.endsWith, "endsWith"),
        ]
        for (op, expected) in cases {
            let rule = FilterRule(field: .title, operator: op, value: .text("test"))
            let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
            if case .leaf(let nspOp, _, _) = criteria.expressions.first {
                #expect(nspOp == expected, "Operator \(op) should map to '\(expected)', got '\(nspOp)'")
            } else {
                #expect(Bool(false), "Missing expression for operator \(op)")
            }
        }
    }

    @Test func regexOperatorIsDropped() {
        let rule = FilterRule(field: .title, operator: .matchesRegex, value: .text(".*love.*"))
        let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
        #expect(criteria.expressions.isEmpty, "matchesRegex has no NSP mapping and should be dropped")
    }

    @Test func numericEqualTo() {
        let rule = FilterRule(field: .rating, operator: .isEqualTo, value: .number(4))
        let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
        if case .leaf(let op, _, let val) = criteria.expressions.first {
            #expect(op == "is")
            if case .int(let n) = val { #expect(n == 4) }
        }
    }

    @Test func numericGreaterThan() {
        let rule = FilterRule(field: .rating, operator: .isGreaterThan, value: .number(3))
        let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
        if case .leaf(let op, _, let val) = criteria.expressions.first {
            #expect(op == "gt")
            if case .int(let n) = val { #expect(n == 3) }
        }
    }

    @Test func numericGreaterOrEqualEmulatedWithGtMinusOne() {
        // ≥ n is emulated as gt(n-1)
        let rule = FilterRule(field: .rating, operator: .isGreaterOrEqual, value: .number(3))
        let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
        if case .leaf(let op, _, let val) = criteria.expressions.first {
            #expect(op == "gt")
            if case .int(let n) = val { #expect(n == 2) }
        }
    }

    @Test func numericLessOrEqualEmulatedWithLtPlusOne() {
        // ≤ n is emulated as lt(n+1)
        let rule = FilterRule(field: .year, operator: .isLessOrEqual, value: .number(2000))
        let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
        if case .leaf(let op, _, let val) = criteria.expressions.first {
            #expect(op == "lt")
            if case .int(let n) = val { #expect(n == 2001) }
        }
    }

    @Test func rangeProducesInTheRange() {
        let rule = FilterRule(field: .year, operator: .isBetween, value: .range(1980, 1989))
        let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
        if case .leaf(let op, let field, let val) = criteria.expressions.first {
            #expect(op == "inTheRange")
            #expect(field == "year")
            if case .range(let lo, let hi) = val {
                if case .int(let loN) = lo { #expect(loN == 1980) }
                if case .int(let hiN) = hi { #expect(hiN == 1989) }
            } else {
                #expect(Bool(false), "Expected range value")
            }
        }
    }

    // MARK: - Combinator

    @Test func allCombinatorPreserved() {
        let ruleSet = FilterRuleSet(combinator: .all, rules: [
            FilterRule(field: .title, operator: .contains, value: .text("a")),
            FilterRule(field: .artist, operator: .contains, value: .text("b")),
        ])
        let criteria = NSPCriteria(from: ruleSet)
        #expect(criteria.combinator == .all)
        #expect(criteria.expressions.count == 2)
    }

    @Test func anyCombinatorPreserved() {
        let ruleSet = FilterRuleSet(combinator: .any, rules: [
            FilterRule(field: .title, operator: .contains, value: .text("a")),
            FilterRule(field: .genre, operator: .equals, value: .text("Rock")),
        ])
        let criteria = NSPCriteria(from: ruleSet)
        #expect(criteria.combinator == .any)
    }

    // MARK: - Empty / effectively-empty rules skipped

    @Test func emptyTextRuleIsSkipped() {
        let rule = FilterRule(field: .title, operator: .contains, value: .text(""))
        let criteria = NSPCriteria(from: FilterRuleSet(combinator: .all, rules: [rule]))
        #expect(criteria.expressions.isEmpty)
    }

    @Test func mixedEmptyAndNonEmptyRules() {
        let ruleSet = FilterRuleSet(combinator: .all, rules: [
            FilterRule(field: .title, operator: .contains, value: .text("")),
            FilterRule(field: .genre, operator: .equals, value: .text("Jazz")),
        ])
        let criteria = NSPCriteria(from: ruleSet)
        #expect(criteria.expressions.count == 1)
    }

    // MARK: - JSON round-trip

    @Test func criteriaRoundTripsJSON() throws {
        let ruleSet = FilterRuleSet(combinator: .all, rules: [
            FilterRule(field: .rating, operator: .isGreaterThan, value: .number(3)),
            FilterRule(field: .isFavorited, operator: .isTrue, value: .boolean(true)),
            FilterRule(field: .genre, operator: .contains, value: .text("Rock")),
        ])
        let criteria = NSPCriteria(from: ruleSet, sort: "rating", order: "desc", limit: 100)
        let data = try JSONEncoder().encode(criteria)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["sort"] as? String == "rating")
        #expect(json?["order"] as? String == "desc")
        #expect(json?["limit"] as? Int == 100)
        #expect(json?["all"] != nil)
    }

    @Test func toJSONProducesNonNilDictionary() {
        let ruleSet = FilterRuleSet(combinator: .all, rules: [
            FilterRule(field: .artist, operator: .contains, value: .text("Beatles")),
        ])
        let criteria = NSPCriteria(from: ruleSet)
        #expect(criteria.toJSON() != nil)
    }

    // MARK: - Full decode round-trip (catches NSPExpression decoder ordering bugs)

    @Test func decodesNavidromeAPIResponseFormat() throws {
        // Mirrors the JSON shape Navidrome returns from GET /api/playlist
        let json = """
        {
            "all": [
                { "contains": { "title": "love" } },
                { "gt": { "year": 2020 } },
                { "is": { "loved": true } }
            ],
            "sort": "year",
            "order": "desc",
            "limit": 50
        }
        """
        let data = json.data(using: .utf8)!
        let criteria = try JSONDecoder().decode(NSPCriteria.self, from: data)

        #expect(criteria.combinator == .all)
        #expect(criteria.expressions.count == 3)
        #expect(criteria.sort == "year")
        #expect(criteria.order == "desc")
        #expect(criteria.limit == 50)

        if case .leaf(let op, let field, let value) = criteria.expressions[0] {
            #expect(op == "contains")
            #expect(field == "title")
            if case .string(let s) = value { #expect(s == "love") }
        } else { #expect(Bool(false), "Expression 0 should be a leaf") }

        if case .leaf(let op, let field, let value) = criteria.expressions[1] {
            #expect(op == "gt")
            #expect(field == "year")
            if case .int(let n) = value { #expect(n == 2020) }
        } else { #expect(Bool(false), "Expression 1 should be a leaf") }

        if case .leaf(let op, let field, let value) = criteria.expressions[2] {
            #expect(op == "is")
            #expect(field == "loved")
            if case .bool(let b) = value { #expect(b == true) }
        } else { #expect(Bool(false), "Expression 2 should be a leaf") }
    }
}
