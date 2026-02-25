import Testing
import Foundation
@testable import Vibrdrome

/// Tests for cache eviction algorithms mirroring CacheManager logic.
struct CacheEvictionTests {

    // MARK: - Helper Types

    private struct CacheEntry: Identifiable {
        let id: String
        let songId: String
        let fileSize: Int64
        let downloadedAt: Date
        let lastAccessedAt: Date?
    }

    // MARK: - Algorithm Mirrors

    /// Mirror the LRU sort from CacheManager.evictIfNeeded():
    /// nil lastAccessedAt first (using downloadedAt as fallback), then by lastAccessedAt ascending.
    private func sortedByLRU(_ entries: [CacheEntry]) -> [CacheEntry] {
        entries.sorted { lhs, rhs in
            let lhsDate = lhs.lastAccessedAt ?? lhs.downloadedAt
            let rhsDate = rhs.lastAccessedAt ?? rhs.downloadedAt
            return lhsDate < rhsDate
        }
    }

    /// Mirror the eviction loop from CacheManager.evictIfNeeded():
    /// Given a byte limit, pinned song IDs, and entries sorted by LRU,
    /// evict oldest non-pinned entries until total size <= limit.
    /// Returns the IDs of evicted entries.
    private func evict(
        entries: [CacheEntry],
        limit: Int64,
        pinned: Set<String>
    ) -> [String] {
        // Unlimited (0) means no eviction
        guard limit > 0 else { return [] }

        var total = entries.reduce(Int64(0)) { $0 + $1.fileSize }
        guard total > limit else { return [] }

        let sorted = sortedByLRU(entries)
        var evictedIds: [String] = []

        for entry in sorted {
            guard total > limit else { break }
            if pinned.contains(entry.songId) { continue }
            total -= entry.fileSize
            evictedIds.append(entry.id)
        }

        return evictedIds
    }

    // MARK: - Test Data Helpers

    private static let now = Date()

    private static func date(hoursAgo hours: Double) -> Date {
        now.addingTimeInterval(-hours * 3600)
    }

    // MARK: - Sort Order Tests

    @Test func sortNilLastAccessedAtComesFirst() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: Self.now),
            CacheEntry(id: "b", songId: "s2", fileSize: 100, downloadedAt: Self.date(hoursAgo: 2), lastAccessedAt: nil),
        ]
        let sorted = sortedByLRU(entries)
        #expect(sorted.first?.id == "b", "Entry with nil lastAccessedAt should sort first")
    }

    @Test func sortOlderLastAccessedAtComesFirst() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 10), lastAccessedAt: Self.date(hoursAgo: 1)),
            CacheEntry(id: "b", songId: "s2", fileSize: 100, downloadedAt: Self.date(hoursAgo: 10), lastAccessedAt: Self.date(hoursAgo: 5)),
        ]
        let sorted = sortedByLRU(entries)
        #expect(sorted.first?.id == "b", "Entry with older lastAccessedAt should sort first")
    }

    @Test func sortNilLastAccessedAtUsesDownloadedAtAsFallback() {
        // Both have nil lastAccessedAt; downloadedAt is the tiebreaker
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
            CacheEntry(id: "b", songId: "s2", fileSize: 100, downloadedAt: Self.date(hoursAgo: 5), lastAccessedAt: nil),
        ]
        let sorted = sortedByLRU(entries)
        #expect(sorted.first?.id == "b", "Entry downloaded earlier should sort first when both have nil lastAccessedAt")
    }

    // MARK: - Eviction Tests

    @Test func noEvictionWhenTotalUnderLimit() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
            CacheEntry(id: "b", songId: "s2", fileSize: 100, downloadedAt: Self.date(hoursAgo: 2), lastAccessedAt: nil),
        ]
        let evicted = evict(entries: entries, limit: 300, pinned: [])
        #expect(evicted.isEmpty, "No eviction when total (200) < limit (300)")
    }

    @Test func evictsOldestEntryWhenOverLimit() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 5), lastAccessedAt: nil),
            CacheEntry(id: "b", songId: "s2", fileSize: 100, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
        ]
        // Total is 200, limit 150 → need to evict 50+ bytes
        let evicted = evict(entries: entries, limit: 150, pinned: [])
        #expect(evicted == ["a"], "Should evict oldest entry (downloaded 5 hours ago)")
    }

    @Test func evictsMultipleEntriesUntilUnderLimit() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 5), lastAccessedAt: nil),
            CacheEntry(id: "b", songId: "s2", fileSize: 100, downloadedAt: Self.date(hoursAgo: 3), lastAccessedAt: nil),
            CacheEntry(id: "c", songId: "s3", fileSize: 100, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
        ]
        // Total is 300, limit 100 → need to evict 200 bytes → 2 entries
        let evicted = evict(entries: entries, limit: 100, pinned: [])
        #expect(evicted.count == 2)
        #expect(evicted.contains("a"))
        #expect(evicted.contains("b"))
    }

    @Test func evictionSkipsPinnedSongs() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 5), lastAccessedAt: nil),
            CacheEntry(id: "b", songId: "s2", fileSize: 100, downloadedAt: Self.date(hoursAgo: 3), lastAccessedAt: nil),
            CacheEntry(id: "c", songId: "s3", fileSize: 100, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
        ]
        // Total 300, limit 200 → need to evict 100 bytes, but oldest (s1) is pinned
        let evicted = evict(entries: entries, limit: 200, pinned: ["s1"])
        #expect(evicted == ["b"], "Should skip pinned s1 and evict next oldest (s2)")
    }

    @Test func evictsNewerNonPinnedWhenOlderArePinned() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 5), lastAccessedAt: nil),
            CacheEntry(id: "b", songId: "s2", fileSize: 100, downloadedAt: Self.date(hoursAgo: 3), lastAccessedAt: nil),
            CacheEntry(id: "c", songId: "s3", fileSize: 100, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
        ]
        // Total 300, limit 150 → need to evict 150 bytes; s1 and s2 pinned → can only evict s3
        let evicted = evict(entries: entries, limit: 150, pinned: ["s1", "s2"])
        #expect(evicted == ["c"], "Should evict newer non-pinned s3 since older entries are pinned")
    }

    @Test func allPinnedNothingEvicted() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 5), lastAccessedAt: nil),
            CacheEntry(id: "b", songId: "s2", fileSize: 100, downloadedAt: Self.date(hoursAgo: 3), lastAccessedAt: nil),
        ]
        // Total 200, limit 50 → way over, but all pinned
        let evicted = evict(entries: entries, limit: 50, pinned: ["s1", "s2"])
        #expect(evicted.isEmpty, "Should evict nothing when all entries are pinned")
    }

    @Test func unlimitedMeansNoEviction() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 1_000_000_000, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
        ]
        let evicted = evict(entries: entries, limit: 0, pinned: [])
        #expect(evicted.isEmpty, "Limit 0 (unlimited) should never evict")
    }

    @Test func exactLimitMatchNoEviction() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 2), lastAccessedAt: nil),
            CacheEntry(id: "b", songId: "s2", fileSize: 100, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
        ]
        let evicted = evict(entries: entries, limit: 200, pinned: [])
        #expect(evicted.isEmpty, "No eviction when total exactly equals limit")
    }

    @Test func oneByteOverEvictsOneEntry() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 2), lastAccessedAt: nil),
            CacheEntry(id: "b", songId: "s2", fileSize: 101, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
        ]
        // Total 201, limit 200 → 1 byte over → evict oldest (a, 100 bytes) → total 101 <= 200
        let evicted = evict(entries: entries, limit: 200, pinned: [])
        #expect(evicted == ["a"], "1 byte over limit should evict one entry")
    }

    @Test func pinnedEntriesNotEvictionCandidates() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 500, downloadedAt: Self.date(hoursAgo: 5), lastAccessedAt: nil),
            CacheEntry(id: "b", songId: "s2", fileSize: 300, downloadedAt: Self.date(hoursAgo: 3), lastAccessedAt: nil),
            CacheEntry(id: "c", songId: "s3", fileSize: 200, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
        ]
        // Total 1000, limit 600 → need to evict 400+; s1 pinned (500 bytes) → evict s2 (300) + s3 (200) = 500 freed
        let evicted = evict(entries: entries, limit: 600, pinned: ["s1"])
        #expect(evicted.contains("b"))
        #expect(evicted.contains("c"))
        #expect(!evicted.contains("a"), "Pinned entry s1 must not be evicted")
    }

    @Test func evictionRespectsLRUOrderWithMixedAccessTimes() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 100, downloadedAt: Self.date(hoursAgo: 10), lastAccessedAt: Self.date(hoursAgo: 1)),
            CacheEntry(id: "b", songId: "s2", fileSize: 100, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
            CacheEntry(id: "c", songId: "s3", fileSize: 100, downloadedAt: Self.date(hoursAgo: 5), lastAccessedAt: Self.date(hoursAgo: 8)),
        ]
        // LRU sort: c (accessed 8h ago), b (downloaded 1h ago, nil access), a (accessed 1h ago)
        // Total 300, limit 200 → evict 1 entry → c (oldest access)
        let evicted = evict(entries: entries, limit: 200, pinned: [])
        #expect(evicted == ["c"], "Should evict entry with oldest effective access time")
    }

    @Test func evictionStopsOnceUnderLimit() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 50, downloadedAt: Self.date(hoursAgo: 5), lastAccessedAt: nil),
            CacheEntry(id: "b", songId: "s2", fileSize: 50, downloadedAt: Self.date(hoursAgo: 4), lastAccessedAt: nil),
            CacheEntry(id: "c", songId: "s3", fileSize: 50, downloadedAt: Self.date(hoursAgo: 3), lastAccessedAt: nil),
            CacheEntry(id: "d", songId: "s4", fileSize: 50, downloadedAt: Self.date(hoursAgo: 2), lastAccessedAt: nil),
        ]
        // Total 200, limit 150 → need to evict 50 bytes → only 1 entry needed
        let evicted = evict(entries: entries, limit: 150, pinned: [])
        #expect(evicted.count == 1, "Should stop evicting once under limit")
        #expect(evicted.first == "a")
    }

    @Test func emptyEntriesNoEviction() {
        let evicted = evict(entries: [], limit: 100, pinned: [])
        #expect(evicted.isEmpty, "No entries means nothing to evict")
    }

    @Test func singleLargeEntryEvictedWhenOverLimit() {
        let entries = [
            CacheEntry(id: "a", songId: "s1", fileSize: 1000, downloadedAt: Self.date(hoursAgo: 1), lastAccessedAt: nil),
        ]
        let evicted = evict(entries: entries, limit: 500, pinned: [])
        #expect(evicted == ["a"])
    }

    // MARK: - CacheManager.limitOptions Tests

    @MainActor @Test func limitOptionsCount() {
        #expect(CacheManager.limitOptions.count == 6)
    }

    @MainActor @Test func limitOptionsContainsCorrectValues() {
        let values = CacheManager.limitOptions.map(\.1)
        #expect(values.contains(1_073_741_824),  "Should contain 1 GB")
        #expect(values.contains(5_368_709_120),  "Should contain 5 GB")
        #expect(values.contains(10_737_418_240), "Should contain 10 GB")
        #expect(values.contains(26_843_545_600), "Should contain 25 GB")
        #expect(values.contains(53_687_091_200), "Should contain 50 GB")
    }

    @MainActor @Test func limitOptionsUnlimitedIsZero() {
        let unlimited = CacheManager.limitOptions.first { $0.0 == "Unlimited" }
        #expect(unlimited != nil, "Should have an 'Unlimited' option")
        #expect(unlimited?.1 == 0, "'Unlimited' should map to 0 bytes")
    }
}
