import Foundation

/// A single crash / hang / exception report captured from MetricKit.
///
/// MetricKit delivers diagnostics asynchronously (typically on the launch *after*
/// the event), so these are persisted to disk and surfaced in Diagnostics.
struct DiagnosticRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case crash
        case hang
        case cpuException
        case diskWriteException

        var displayName: String {
            switch self {
            case .crash: return "Crash"
            case .hang: return "Hang"
            case .cpuException: return "CPU Exception"
            case .diskWriteException: return "Disk Write Exception"
            }
        }
    }

    let id: UUID
    let date: Date
    let kind: Kind
    /// One-line human summary (app/OS version + reason where available).
    let summary: String
    /// Full JSON representation of the underlying diagnostic, for copy/export.
    let detail: String

    init(id: UUID = UUID(), date: Date, kind: Kind, summary: String, detail: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.summary = summary
        self.detail = detail
    }
}

/// Persists a capped, newest-first list of `DiagnosticRecord`s to a JSON file.
///
/// Deliberately free of any MetricKit dependency so it can be unit-tested in
/// isolation: inject a temp `fileURL` and a small `maxRecords` in tests.
final class DiagnosticsStore {
    private let fileURL: URL
    private let maxRecords: Int
    private let lock = NSLock()

    init(fileURL: URL, maxRecords: Int = 25) {
        self.fileURL = fileURL
        self.maxRecords = max(1, maxRecords)
    }

    /// Default store location: Application Support/Diagnostics/crash-reports.json.
    static func makeDefault() -> DiagnosticsStore {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return DiagnosticsStore(fileURL: dir.appendingPathComponent("crash-reports.json"))
    }

    /// All stored records, newest first.
    func load() -> [DiagnosticRecord] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    /// Append new records, keeping only the newest `maxRecords`. Returns the new full list.
    @discardableResult
    func append(_ records: [DiagnosticRecord]) -> [DiagnosticRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard !records.isEmpty else { return loadUnlocked() }
        let merged = (records + loadUnlocked())
            .sorted { $0.date > $1.date }
        let capped = Array(merged.prefix(maxRecords))
        persistUnlocked(capped)
        return capped
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Private (must hold `lock`)

    private func loadUnlocked() -> [DiagnosticRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DiagnosticRecord].self, from: data)) ?? []
    }

    private func persistUnlocked(_ records: [DiagnosticRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
