import Foundation
import SwiftData
import os.log

private let persistLog = Logger(subsystem: "com.vibrdrome.app", category: "Persistence")

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    init() {
        // Schema notes:
        // - All models are caches or queued actions. The Navidrome server is the source of truth.
        // - Adding optional properties with defaults is a lightweight migration (safe).
        // - Removing/renaming properties or changing types requires a versioned schema migration
        //   OR the catch block below will delete and recreate the store (acceptable for cache data).
        // - PendingAction gained songTitle/songArtist/songAlbum/songAlbumArtist/songDuration in Build 37.
        // - DownloadedSong gained additional fields in Build 32.
        let schema = Schema([
            CachedArtist.self,
            CachedAlbum.self,
            CachedSong.self,
            CachedPlaylist.self,
            CachedPlaylistEntry.self,
            DownloadedSong.self,
            PlayHistory.self,
            ServerConfig.self,
            OfflinePlaylist.self,
            PendingAction.self,
            SavedQueue.self,
            SyncHistory.self,
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // D2: On migration failure, delete the store and recreate (it's a cache)
            print("ModelContainer failed, recreating store: \(error)")
            let storeURL = config.url
            try? FileManager.default.removeItem(at: storeURL)
            // Also remove WAL/SHM files
            let walURL = storeURL.appendingPathExtension("wal")
            let shmURL = storeURL.appendingPathExtension("shm")
            try? FileManager.default.removeItem(at: walURL)
            try? FileManager.default.removeItem(at: shmURL)
            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to recreate ModelContainer: \(error)")
            }
        }

        // D5: Incomplete downloads are now handled by DownloadManager.resumeIncompleteDownloads()
        // which checks the background URLSession before deleting records.

        // D6: Prune old play history
        prunePlayHistory()
    }

    /// Record a play history entry for a song
    func recordPlay(song: Song) {
        let context = container.mainContext
        let entry = PlayHistory(from: song)
        context.insert(entry)
        do {
            try context.save()
        } catch {
            persistLog.error("Failed to save play history: \(error)")
        }
    }

    /// Fetch recent play history
    func recentPlays(limit: Int = 50) -> [PlayHistory] {
        var descriptor = FetchDescriptor<PlayHistory>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    // MARK: - Cleanup

    /// D6: Prune play history older than 90 days, cap at 10000 entries
    private func prunePlayHistory() {
        let context = container.mainContext
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let oldDescriptor = FetchDescriptor<PlayHistory>(
            predicate: #Predicate { $0.playedAt < cutoff }
        )
        if let oldEntries = try? context.fetch(oldDescriptor), !oldEntries.isEmpty {
            for entry in oldEntries {
                context.delete(entry)
            }
            do {
                try context.save()
            } catch {
                persistLog.error("Failed to save after pruning old play history: \(error)")
            }
        }

        // Also cap total count
        var countDescriptor = FetchDescriptor<PlayHistory>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        countDescriptor.fetchOffset = 10000
        if let excess = try? context.fetch(countDescriptor), !excess.isEmpty {
            for entry in excess {
                context.delete(entry)
            }
            do {
                try context.save()
            } catch {
                persistLog.error("Failed to save after capping play history: \(error)")
            }
        }
    }
}
