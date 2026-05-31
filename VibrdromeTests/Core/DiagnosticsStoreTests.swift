import Testing
import Foundation
@testable import Vibrdrome

struct DiagnosticsStoreTests {
    private func makeTempStore(maxRecords: Int = 25) -> (DiagnosticsStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diag-test-\(UUID().uuidString).json")
        return (DiagnosticsStore(fileURL: url, maxRecords: maxRecords), url)
    }

    private func record(_ kind: DiagnosticRecord.Kind, secondsAgo: TimeInterval) -> DiagnosticRecord {
        DiagnosticRecord(
            date: Date(timeIntervalSince1970: 1_700_000_000 - secondsAgo),
            kind: kind,
            summary: "\(kind.rawValue) summary",
            detail: "{\"k\":\"\(kind.rawValue)\"}"
        )
    }

    @Test func emptyStoreLoadsNothing() {
        let (store, url) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(store.load().isEmpty)
    }

    @Test func appendPersistsAcrossInstances() {
        let (store, url) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let rec = record(.crash, secondsAgo: 0)
        store.append([rec])

        let reopened = DiagnosticsStore(fileURL: url)
        let loaded = reopened.load()
        #expect(loaded.count == 1)
        #expect(loaded.first == rec)
    }

    @Test func recordsAreNewestFirst() {
        let (store, url) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let older = record(.hang, secondsAgo: 100)
        let newer = record(.crash, secondsAgo: 10)
        store.append([older])
        store.append([newer])

        let loaded = store.load()
        #expect(loaded.map(\.kind) == [.crash, .hang])
    }

    @Test func capsToMaxRecordsKeepingNewest() {
        let (store, url) = makeTempStore(maxRecords: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        // Append 5 records, increasingly recent.
        let recs = (0..<5).map { record(.crash, secondsAgo: TimeInterval(100 - $0)) }
        store.append(recs)

        let loaded = store.load()
        #expect(loaded.count == 3)
        // Newest three have the smallest secondsAgo => largest dates.
        let dates = loaded.map(\.date)
        #expect(dates == dates.sorted(by: >))
    }

    @Test func appendingEmptyDoesNotClobber() {
        let (store, url) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.append([record(.crash, secondsAgo: 0)])
        store.append([])
        #expect(store.load().count == 1)
    }

    @Test func clearRemovesAll() {
        let (store, url) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.append([record(.crash, secondsAgo: 0)])
        store.clear()
        #expect(store.load().isEmpty)
    }

    @Test func recordRoundTripsThroughCodable() throws {
        let rec = record(.diskWriteException, secondsAgo: 42)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(rec)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticRecord.self, from: data)
        #expect(decoded == rec)
    }
}
