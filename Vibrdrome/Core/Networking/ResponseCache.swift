import CryptoKit
import Foundation
import os.log

private let cacheLog = Logger(subsystem: "com.vibrdrome.app", category: "Cache")

/// File-based cache for raw API response JSON data.
/// Stored in the Caches directory so iOS can evict under storage pressure.
actor ResponseCache {
    static let shared = ResponseCache()

    private let cacheDir: URL
    private var timestamps: [String: Date] = [:]

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = base.appendingPathComponent("APIResponses", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Build a deterministic cache key from an endpoint's path and query items.
    func cacheKey(for endpoint: SubsonicEndpoint) -> String {
        let params = endpoint.queryItems
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        return "\(endpoint.path)?\(params)"
    }

    /// Read cached JSON data for a key, returning nil if missing or expired.
    func data(for key: String, ttl: TimeInterval) -> Data? {
        let file = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }

        // Check TTL
        if let ts = timestamps[key], Date().timeIntervalSince(ts) > ttl {
            return nil
        }
        // Fall back to file modification date if no in-memory timestamp
        if timestamps[key] == nil,
           let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modified = attrs[.modificationDate] as? Date {
            if Date().timeIntervalSince(modified) > ttl {
                return nil
            }
            timestamps[key] = modified
        }

        return try? Data(contentsOf: file)
    }

    /// Store raw JSON data for a key.
    func store(data: Data, for key: String) {
        let file = fileURL(for: key)
        do {
            try data.write(to: file, options: .atomic)
            timestamps[key] = Date()
        } catch {
            cacheLog.error("Failed to write cache for \(key): \(error)")
        }
    }

    /// Remove a specific cached response.
    func remove(for key: String) {
        let file = fileURL(for: key)
        try? FileManager.default.removeItem(at: file)
        timestamps.removeValue(forKey: key)
    }

    /// Clear all cached responses (e.g. on logout or server switch).
    func clearAll() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        timestamps.removeAll()
        cacheLog.info("Cleared all cached API responses")
    }

    private func fileURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return cacheDir.appendingPathComponent(hash + ".json")
    }
}
