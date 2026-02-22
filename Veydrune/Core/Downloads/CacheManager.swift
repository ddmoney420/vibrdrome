import Foundation
import SwiftData
import os.log

private let cacheLog = Logger(subsystem: "com.veydrune.app", category: "Cache")

@MainActor
final class CacheManager {
    static let shared = CacheManager()

    /// Cache limit options in bytes (0 = unlimited)
    static let limitOptions: [(String, Int64)] = [
        ("1 GB", 1_073_741_824),
        ("5 GB", 5_368_709_120),
        ("10 GB", 10_737_418_240),
        ("25 GB", 26_843_545_600),
        ("50 GB", 53_687_091_200),
        ("Unlimited", 0),
    ]

    /// Current cache limit in bytes from UserDefaults (0 = unlimited)
    var cacheLimitBytes: Int64 {
        Int64(UserDefaults.standard.integer(forKey: "cacheLimitBytes"))
    }

    /// Total size of all completed downloads
    var totalCacheSize: Int64 {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.isComplete == true }
        )
        guard let downloads = try? context.fetch(descriptor) else { return 0 }
        return downloads.reduce(0) { $0 + $1.fileSize }
    }

    private init() {}

    /// Build a set of pinned song IDs (songs in any offline playlist for the current server)
    private func pinnedSongIds() -> Set<String> {
        guard let serverId = AppState.shared.activeServerId else { return [] }
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<OfflinePlaylist>(
            predicate: #Predicate { $0.serverId == serverId }
        )
        guard let playlists = try? context.fetch(descriptor) else { return [] }
        var pinned = Set<String>()
        for playlist in playlists {
            pinned.formUnion(playlist.songIds)
        }
        return pinned
    }

    /// Evict oldest non-pinned downloads if over the cache limit
    func evictIfNeeded() {
        let limit = cacheLimitBytes
        guard limit > 0 else { return }

        var total = totalCacheSize
        guard total > limit else { return }

        let pinned = pinnedSongIds()
        let context = PersistenceController.shared.container.mainContext

        // Fetch all completed downloads, sorted by last access (oldest first)
        var descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.isComplete == true },
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .forward)]
        )
        // Secondary sort by downloadedAt not directly supported, so we'll do manual sort
        descriptor.fetchLimit = 500

        guard var candidates = try? context.fetch(descriptor) else { return }

        // Sort: nil lastAccessedAt first (never accessed), then by lastAccessedAt ascending
        candidates.sort { lhs, rhs in
            let lhsDate = lhs.lastAccessedAt ?? lhs.downloadedAt
            let rhsDate = rhs.lastAccessedAt ?? rhs.downloadedAt
            return lhsDate < rhsDate
        }

        var evictedCount = 0
        for download in candidates {
            guard total > limit else { break }

            // Skip pinned songs
            if pinned.contains(download.songId) { continue }

            // Delete the file
            let fileURL = DownloadManager.absoluteURL(for: download.localFilePath)
            try? FileManager.default.removeItem(at: fileURL)

            total -= download.fileSize
            context.delete(download)
            evictedCount += 1
        }

        if evictedCount > 0 {
            do {
                try context.save()
            } catch {
                cacheLog.error("Failed to save after cache eviction: \(error)")
            }
            cacheLog.info("Evicted \(evictedCount) cached tracks to meet \(limit) byte limit")
        }
    }

    /// Touch the lastAccessedAt date for a downloaded song
    func touchAccess(songId: String) {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
        )
        guard let download = try? context.fetch(descriptor).first else { return }
        download.lastAccessedAt = Date()
        try? context.save()
    }
}
