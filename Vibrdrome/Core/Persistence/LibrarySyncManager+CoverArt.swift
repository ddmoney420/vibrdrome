import Foundation
import Nuke
import SwiftData

// MARK: - Cover Art Prefetch

extension LibrarySyncManager {
    /// Warm the in-memory image cache on startup by loading all known cover art.
    /// Images already in memory are skipped; images in disk cache load instantly.
    /// Skipped if a prefetch already ran during sync this session.
    func warmImageCache(client: SubsonicClient, container: ModelContainer) async {
        guard !didPrefetchThisSession else { return }
        isWarmingImages = true
        defer { isWarmingImages = false }
        let context = ModelContext(container)
        await prefetchCoverArt(client: client, context: context)
    }

    private func prefetchCoverArt(client: SubsonicClient, context: ModelContext) async {
        syncProgress = "Prefetching cover art…"

        // Collect cover art IDs from albums and artists without loading full objects
        var coverArtIds = Set<String>()

        let albumDescriptor = FetchDescriptor<CachedAlbum>(
            predicate: #Predicate<CachedAlbum> { $0.coverArtId != nil }
        )
        let albums = (try? context.fetch(albumDescriptor)) ?? []
        for album in albums {
            if let id = album.coverArtId { coverArtIds.insert(id) }
        }

        let artistDescriptor = FetchDescriptor<CachedArtist>(
            predicate: #Predicate<CachedArtist> { $0.coverArtId != nil }
        )
        let artists = (try? context.fetch(artistDescriptor)) ?? []
        for artist in artists {
            if let id = artist.coverArtId { coverArtIds.insert(id) }
        }

        let total = coverArtIds.count
        guard total > 0 else {
            didPrefetchThisSession = true
            return
        }
        syncLog.info("Prefetching \(total) cover art images")

        let pipeline = ImagePipeline.shared
        let dataCache = pipeline.configuration.dataCache as? DataCache

        // Filter out images already in disk cache so we only fetch what's missing.
        // Use stable cache keys (no auth salt) so lookups survive across app launches.
        let uncachedUrls: [(String, URL)] = coverArtIds.compactMap { id in
            let url = client.coverArtURL(id: id, size: CoverArtSize.gridThumb)
            var request = ImageRequest(url: url)
            request.userInfo[.imageIdKey] = client.coverArtCacheKey(id: id, size: CoverArtSize.gridThumb)
            let key = pipeline.cache.makeDataCacheKey(for: request)
            if dataCache?.containsData(for: key) == true { return nil }
            return (id, url)
        }

        let alreadyCached = total - uncachedUrls.count

        if !uncachedUrls.isEmpty {
            syncLog.info("Prefetching \(uncachedUrls.count) cover art images (\(alreadyCached) already cached)")
            let fetched = await prefetchBatches(uncachedUrls: uncachedUrls, total: total, alreadyCached: alreadyCached, client: client)
            syncLog.info("Cover art prefetch complete: \(fetched)/\(total) processed")
            // Flush staging area to disk synchronously so files survive if the app quits
            // before Nuke's async 1-second flush fires — prevents re-fetching on next launch.
            dataCache?.flush()
        } else {
            syncLog.info("Cover art prefetch skipped — all \(total) images already on disk")
        }

        // Promote disk-cached images into memory so the grid renders instantly without decompression stalls.
        await warmMemoryFromDisk(coverArtIds: coverArtIds, client: client)

        didPrefetchThisSession = true
        UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.lastCoverArtPrefetchDate)
    }

    /// Fetch cover art in batches of 10 with per-image timeouts. Returns total processed count.
    private func prefetchBatches(uncachedUrls: [(String, URL)], total: Int, alreadyCached: Int, client: SubsonicClient) async -> Int {
        let pipeline = ImagePipeline.shared
        var fetched = alreadyCached
        let batchSize = 10
        let perImageTimeout: UInt64 = 15_000_000_000 // 15 seconds

        for batchStart in stride(from: 0, to: uncachedUrls.count, by: batchSize) {
            guard !Task.isCancelled else { break }
            let batch = uncachedUrls[batchStart..<min(batchStart + batchSize, uncachedUrls.count)]
            let batchRequests: [(URL, String)] = batch.map { id, url in
                (url, client.coverArtCacheKey(id: id, size: CoverArtSize.gridThumb))
            }
            await withTaskGroup(of: Void.self) { group in
                for (url, stableKey) in batchRequests {
                    var req = ImageRequest(url: url)
                    req.userInfo[.imageIdKey] = stableKey
                    let finalRequest = req
                    group.addTask {
                        // Timeout prevents a single stalled request from blocking the entire prefetch
                        await withTaskGroup(of: Void.self) { inner in
                            inner.addTask {
                                _ = try? await pipeline.image(for: finalRequest)
                            }
                            inner.addTask {
                                try? await Task.sleep(nanoseconds: perImageTimeout)
                            }
                            // Return as soon as the first child completes (image loaded or timeout)
                            await inner.next()
                            inner.cancelAll()
                        }
                    }
                }
            }
            fetched += batch.count
            syncProgress = "Prefetching cover art… \(fetched)/\(total)"
        }
        return fetched
    }

    /// Decode all disk-cached cover art into the memory cache in background batches.
    /// No network traffic — pure disk→CPU→memory. Runs at background priority so it
    /// doesn't compete with UI rendering but completes before the user starts scrolling.
    private func warmMemoryFromDisk(coverArtIds: Set<String>, client: SubsonicClient) async {
        let pipeline = ImagePipeline.shared
        let dataCache = pipeline.configuration.dataCache as? DataCache
        syncProgress = "Warming image cache…"

        // Only decode images that are on disk but not yet in memory.
        let diskOnlyIds: [String] = coverArtIds.compactMap { id in
            let url = client.coverArtURL(id: id, size: CoverArtSize.gridThumb)
            var request = ImageRequest(url: url)
            request.userInfo[.imageIdKey] = client.coverArtCacheKey(id: id, size: CoverArtSize.gridThumb)
            if pipeline.cache.containsCachedImage(for: request) { return nil }
            let key = pipeline.cache.makeDataCacheKey(for: request)
            return dataCache?.containsData(for: key) == true ? id : nil
        }

        guard !diskOnlyIds.isEmpty else {
            syncLog.info("Memory warm skipped — all images already in memory")
            return
        }

        syncLog.info("Warming \(diskOnlyIds.count) images from disk into memory")

        let batchSize = 20
        var warmed = 0
        for batchStart in stride(from: 0, to: diskOnlyIds.count, by: batchSize) {
            guard !Task.isCancelled else { break }
            let batch = diskOnlyIds[batchStart..<min(batchStart + batchSize, diskOnlyIds.count)]
            let batchPairs: [(URL, String)] = batch.map { id in
                (client.coverArtURL(id: id, size: CoverArtSize.gridThumb),
                 client.coverArtCacheKey(id: id, size: CoverArtSize.gridThumb))
            }
            await withTaskGroup(of: Void.self) { group in
                for (url, stableKey) in batchPairs {
                    group.addTask(priority: .background) {
                        var request = ImageRequest(url: url)
                        request.userInfo[.imageIdKey] = stableKey
                        _ = try? await pipeline.image(for: request)
                    }
                }
            }
            warmed += batch.count
            syncProgress = "Warming image cache… \(warmed)/\(diskOnlyIds.count)"
        }
        syncLog.info("Memory warm complete: \(warmed) images")
        await warmBlurThumbnailsFromDisk(coverArtIds: coverArtIds, client: client, batchSize: batchSize)
    }

    private func warmBlurThumbnailsFromDisk(
        coverArtIds: Set<String>, client: SubsonicClient, batchSize: Int
    ) async {
        let blurPipeline = VibrdromeApp.blurPipeline
        let blurDataCache = blurPipeline.configuration.dataCache as? DataCache
        let blurDiskOnlyIds: [String] = coverArtIds.compactMap { id in
            var request = ImageRequest(url: client.coverArtURL(id: id, size: CoverArtSize.blur))
            request.userInfo[.imageIdKey] = client.coverArtCacheKey(id: id, size: CoverArtSize.blur)
            if blurPipeline.cache.containsCachedImage(for: request) { return nil }
            let key = blurPipeline.cache.makeDataCacheKey(for: request)
            return blurDataCache?.containsData(for: key) == true ? id : nil
        }
        guard !blurDiskOnlyIds.isEmpty else { return }
        syncLog.info("Warming \(blurDiskOnlyIds.count) blur thumbnails from disk into memory")
        let blurPairs: [(URL, String)] = blurDiskOnlyIds.map { id in
            (client.coverArtURL(id: id, size: CoverArtSize.blur),
             client.coverArtCacheKey(id: id, size: CoverArtSize.blur))
        }
        for batchStart in stride(from: 0, to: blurPairs.count, by: batchSize) {
            guard !Task.isCancelled else { break }
            let batch = blurPairs[batchStart..<min(batchStart + batchSize, blurPairs.count)]
            await withTaskGroup(of: Void.self) { group in
                for (url, stableKey) in batch {
                    group.addTask(priority: .background) {
                        var request = ImageRequest(url: url)
                        request.userInfo[.imageIdKey] = stableKey
                        _ = try? await blurPipeline.image(for: request)
                    }
                }
            }
        }
    }
}

// MARK: - Sync History

extension LibrarySyncManager {
    func saveSyncHistory(stats: SyncStats, mode: SyncMode,
                         context: ModelContext, error: Error? = nil) {
        let history = SyncHistory(syncType: mode.rawValue)
        history.durationSeconds = stats.duration
        history.albumsAdded = stats.albumsAdded
        history.albumsUpdated = stats.albumsUpdated
        history.albumsRemoved = stats.albumsRemoved
        history.artistsAdded = stats.artistsAdded
        history.artistsUpdated = stats.artistsUpdated
        history.artistsRemoved = stats.artistsRemoved
        history.songsAdded = stats.songsAdded
        history.songsUpdated = stats.songsUpdated
        history.songsRemoved = stats.songsRemoved
        history.playlistsSynced = stats.playlistsSynced
        history.conflictsDetected = stats.conflictsDetected
        history.conflictsResolved = stats.conflictsResolved
        history.succeeded = error == nil
        history.errorMessage = error?.localizedDescription
        context.insert(history)
        try? context.save()

        pruneSyncHistory(context: context)
    }

    private func pruneSyncHistory(context: ModelContext) {
        var descriptor = FetchDescriptor<SyncHistory>(
            sortBy: [SortDescriptor(\.syncDate, order: .reverse)]
        )
        descriptor.fetchOffset = 50
        do {
            let old = try context.fetch(descriptor)
            guard !old.isEmpty else { return }
            for entry in old {
                context.delete(entry)
            }
            try context.save()
        } catch {
            syncLog.warning("Failed to prune sync history: \(error.localizedDescription)")
        }
    }
}
