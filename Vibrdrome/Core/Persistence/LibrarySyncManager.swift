import Foundation
import Nuke
import SwiftData
import os.log

private let syncLog = Logger(subsystem: "com.vibrdrome.app", category: "LibrarySync")

/// Sync mode determines the depth of library synchronization.
enum SyncMode: String, Sendable {
    /// Full re-sync of all metadata — catches additions, updates, and deletions.
    case full
    /// Lightweight sync — only fetches recently changed content.
    case incremental
    /// Triggered by BGTaskScheduler in the background.
    case background
}

/// Syncs library metadata (albums, artists, songs, playlists) from the Subsonic API
/// into SwiftData for local filtering, search, and offline support.
@Observable
@MainActor
final class LibrarySyncManager {
    var isSyncing = false
    var syncProgress: String?
    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: UserDefaultsKeys.lastLibrarySyncDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.lastLibrarySyncDate) }
    }
    var syncError: String?

    /// Stats from the most recent sync, updated live during sync.
    var lastSyncStats: SyncStats?

    /// Polling timer for change detection while app is active.
    private var pollingTask: Task<Void, Never>?

    private let albumPageSize = 500
    private let songPageSize = 500

    /// Stale threshold for auto-sync (24 hours).
    private let staleInterval: TimeInterval = 86400
    /// Interval between full syncs to catch deletions (7 days).
    private let fullSyncInterval: TimeInterval = 604_800

    // MARK: - Sync Stats

    struct SyncStats: Sendable {
        var albumsAdded = 0
        var albumsUpdated = 0
        var albumsRemoved = 0
        var artistsAdded = 0
        var artistsUpdated = 0
        var artistsRemoved = 0
        var songsAdded = 0
        var songsUpdated = 0
        var songsRemoved = 0
        var playlistsSynced = 0
        var conflictsDetected = 0
        var conflictsResolved = 0
        var startTime = Date()

        var totalChanges: Int {
            albumsAdded + albumsUpdated + albumsRemoved +
            artistsAdded + artistsUpdated + artistsRemoved +
            songsAdded + songsUpdated + songsRemoved
        }

        var duration: TimeInterval {
            Date().timeIntervalSince(startTime)
        }
    }

    // MARK: - Public API

    /// Run a full library sync: albums, artists, songs, then playlists.
    func sync(client: SubsonicClient, container: ModelContainer) async {
        await performSync(mode: .full, client: client, container: container)
    }

    /// Run an incremental sync — only fetches changes since last sync.
    func incrementalSync(client: SubsonicClient, container: ModelContainer) async {
        await performSync(mode: .incremental, client: client, container: container)
    }

    /// Check if sync is stale and trigger the appropriate sync mode.
    func syncIfStale(client: SubsonicClient, container: ModelContainer) async {
        guard let last = lastSyncDate else {
            await performSync(mode: .full, client: client, container: container)
            return
        }
        let elapsed = Date().timeIntervalSince(last)
        guard elapsed > staleInterval else { return }

        // Check if server data actually changed before doing work
        let serverChanged = await hasServerChanged(client: client)

        if serverChanged {
            // Use full sync if it's been over a week, otherwise incremental
            let lastFull = UserDefaults.standard.object(forKey: UserDefaultsKeys.lastFullSyncDate) as? Date
            let needsFullSync = lastFull == nil || Date().timeIntervalSince(lastFull!) > fullSyncInterval
            let mode: SyncMode = needsFullSync ? .full : .incremental
            await performSync(mode: mode, client: client, container: container)
        } else {
            // Server unchanged — just update the stale check timestamp
            lastSyncDate = Date()
            syncLog.info("Server data unchanged, skipping sync")
        }
    }

    // MARK: - Change Detection Polling

    /// Start periodic polling for server changes while the app is active.
    func startPolling(client: SubsonicClient, container: ModelContainer) {
        stopPolling()
        let intervalMinutes = UserDefaults.standard.integer(forKey: UserDefaultsKeys.syncPollingInterval)
        let interval = max(TimeInterval(intervalMinutes > 0 ? intervalMinutes : 15) * 60, 300)

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, !self.isSyncing else { continue }

                let changed = await self.hasServerChanged(client: client)
                if changed {
                    syncLog.info("Polling detected server changes, triggering incremental sync")
                    await self.performSync(mode: .incremental, client: client, container: container)
                }
            }
        }
        syncLog.info("Started change detection polling every \(Int(interval))s")
    }

    /// Stop the periodic polling timer.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Core Sync Engine

    private func performSync(mode: SyncMode, client: SubsonicClient, container: ModelContainer) async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        syncProgress = mode == .full ? "Starting full sync…" : "Starting incremental sync…"
        var stats = SyncStats()
        lastSyncStats = stats
        defer {
            isSyncing = false
            syncProgress = nil
        }

        do {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            switch mode {
            case .full, .background:
                try await syncAlbums(client: client, context: context, stats: &stats, incremental: false)
                try await syncArtists(client: client, context: context, stats: &stats, incremental: false)
                try await syncSongs(client: client, context: context, stats: &stats, incremental: false)
                try await syncPlaylists(client: client, context: context, stats: &stats)
                UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.lastFullSyncDate)

            case .incremental:
                try await syncAlbums(client: client, context: context, stats: &stats, incremental: true)
                try await syncArtists(client: client, context: context, stats: &stats, incremental: true)
                try await syncSongs(client: client, context: context, stats: &stats, incremental: true)
                try await syncPlaylists(client: client, context: context, stats: &stats)
            }

            try context.save()
            lastSyncDate = Date()
            lastSyncStats = stats

            // Save sync history
            saveSyncHistory(stats: stats, mode: mode, context: context)

            syncLog.info("""
                Library sync (\(mode.rawValue)) completed in \
                \(String(format: "%.1f", stats.duration))s — \
                \(stats.totalChanges) changes \
                (+\(stats.albumsAdded + stats.artistsAdded + stats.songsAdded) \
                ~\(stats.albumsUpdated + stats.artistsUpdated + stats.songsUpdated) \
                -\(stats.albumsRemoved + stats.artistsRemoved + stats.songsRemoved))
                """)

            // Prefetch cover art in background after metadata sync
            if stats.albumsAdded > 0 || stats.artistsAdded > 0 {
                await prefetchCoverArt(client: client, context: context)
            }
        } catch {
            syncError = "Sync failed: \(error.localizedDescription)"
            lastSyncStats = stats
            saveSyncHistory(stats: stats, mode: mode, context: ModelContext(container), error: error)
            syncLog.error("Library sync (\(mode.rawValue)) failed: \(error)")
        }
    }

    // MARK: - Server Change Detection

    /// Lightweight check if server data has changed since last sync.
    /// Uses getIndexes with ifModifiedSince to avoid fetching full data.
    private func hasServerChanged(client: SubsonicClient) async -> Bool {
        let lastModified = UserDefaults.standard.integer(forKey: UserDefaultsKeys.lastServerModified)
        guard lastModified > 0 else { return true }

        do {
            let indexes = try await client.getIndexes(ifModifiedSince: lastModified)
            if let serverModified = indexes.lastModified, serverModified > lastModified {
                return true
            }
            let hasContent = indexes.index?.isEmpty == false || indexes.child?.isEmpty == false
            return hasContent
        } catch {
            syncLog.warning("Change detection failed: \(error.localizedDescription)")
            return true
        }
    }

    /// Update the stored server lastModified timestamp.
    private func updateServerModifiedTimestamp(client: SubsonicClient) async {
        do {
            let indexes = try await client.getIndexes()
            if let lastModified = indexes.lastModified {
                UserDefaults.standard.set(lastModified, forKey: UserDefaultsKeys.lastServerModified)
            }
        } catch {
            syncLog.warning("Failed to fetch server modified timestamp: \(error.localizedDescription)")
        }
    }

    // MARK: - Albums

    private func syncAlbums(client: SubsonicClient, context: ModelContext,
                            stats: inout SyncStats, incremental: Bool) async throws {
        syncProgress = "Syncing albums…"

        // Build lookup dictionary of existing albums for O(1) access
        let allLocal = try context.fetch(FetchDescriptor<CachedAlbum>())
        var localMap = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })

        var offset = 0
        var serverAlbumIds = Set<String>()
        var totalFetched = 0

        if incremental {
            // Fetch only newest albums (added/modified recently)
            let newestAlbums = try await client.getAlbumList(type: .newest, size: albumPageSize)
            for album in newestAlbums {
                serverAlbumIds.insert(album.id)
                if let existing = localMap[album.id] {
                    if hasAlbumChanged(existing, album) {
                        existing.update(from: album)
                        stats.albumsUpdated += 1
                    }
                } else {
                    let cached = CachedAlbum(from: album)
                    context.insert(cached)
                    localMap[album.id] = cached
                    stats.albumsAdded += 1
                }
            }
            totalFetched = newestAlbums.count
        } else {
            // Full sync: fetch all albums
            while true {
                let page = try await client.getAlbumList(
                    type: .alphabeticalByName, size: albumPageSize, offset: offset
                )
                if page.isEmpty { break }

                for album in page {
                    serverAlbumIds.insert(album.id)
                    if let existing = localMap[album.id] {
                        if hasAlbumChanged(existing, album) {
                            existing.update(from: album)
                            stats.albumsUpdated += 1
                        }
                    } else {
                        let cached = CachedAlbum(from: album)
                        context.insert(cached)
                        localMap[album.id] = cached
                        stats.albumsAdded += 1
                    }
                }

                totalFetched += page.count
                syncProgress = "Syncing albums… \(totalFetched)"
                offset += page.count

                if page.count < albumPageSize { break }
            }

            // Remove albums no longer on server
            for local in allLocal where !serverAlbumIds.contains(local.id) {
                context.delete(local)
                stats.albumsRemoved += 1
            }
        }

        try context.save()
        lastSyncStats = stats
        let added = stats.albumsAdded
        let updated = stats.albumsUpdated
        let removed = stats.albumsRemoved
        syncLog.info("Synced \(totalFetched) albums (+\(added) ~\(updated) -\(removed))")
    }

    private func hasAlbumChanged(_ cached: CachedAlbum, _ server: Album) -> Bool {
        cached.name != server.name ||
        cached.artistName != server.artist ||
        cached.year != server.year ||
        cached.genre != server.genre ||
        cached.songCount != server.songCount ||
        cached.duration != server.duration ||
        cached.isStarred != (server.starred != nil) ||
        cached.coverArtId != server.coverArt
    }

    // MARK: - Artists

    private func syncArtists(client: SubsonicClient, context: ModelContext,
                             stats: inout SyncStats, incremental: Bool) async throws {
        syncProgress = "Syncing artists…"
        let indexes = try await client.getArtists()
        var serverArtistIds = Set<String>()

        // Build lookup dictionary
        let allLocal = try context.fetch(FetchDescriptor<CachedArtist>())
        let localMap = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })

        for index in indexes {
            for artist in index.artist ?? [] {
                serverArtistIds.insert(artist.id)
                if let existing = localMap[artist.id] {
                    if hasArtistChanged(existing, artist) {
                        existing.name = artist.name
                        existing.coverArtId = artist.coverArt
                        existing.albumCount = artist.albumCount
                        existing.isStarred = artist.starred != nil
                        existing.cachedAt = Date()
                        stats.artistsUpdated += 1
                    }
                } else {
                    context.insert(CachedArtist(from: artist))
                    stats.artistsAdded += 1
                }
            }
        }

        // Remove artists no longer on server (only on full sync)
        if !incremental {
            for local in allLocal where !serverArtistIds.contains(local.id) {
                context.delete(local)
                stats.artistsRemoved += 1
            }
        }

        try context.save()
        lastSyncStats = stats
        let artAdded = stats.artistsAdded
        let artUpdated = stats.artistsUpdated
        let artRemoved = stats.artistsRemoved
        syncLog.info("Synced \(serverArtistIds.count) artists (+\(artAdded) ~\(artUpdated) -\(artRemoved))")
    }

    private func hasArtistChanged(_ cached: CachedArtist, _ server: Artist) -> Bool {
        cached.name != server.name ||
        cached.coverArtId != server.coverArt ||
        cached.albumCount != server.albumCount ||
        cached.isStarred != (server.starred != nil)
    }

    // MARK: - Songs

    private func syncSongs(client: SubsonicClient, context: ModelContext,
                           stats: inout SyncStats, incremental: Bool) async throws {
        syncProgress = "Syncing songs…"

        // Build lookup dictionary for O(1) access
        let allLocal = try context.fetch(FetchDescriptor<CachedSong>())
        var localMap = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })

        // Pre-fetch album map for linking
        let allAlbums = try context.fetch(FetchDescriptor<CachedAlbum>())
        let albumMap = Dictionary(uniqueKeysWithValues: allAlbums.map { ($0.id, $0) })

        var offset = 0
        var serverSongIds = Set<String>()
        var totalFetched = 0

        while true {
            let result = try await client.search(
                query: "", artistCount: 0, albumCount: 0,
                songCount: songPageSize, songOffset: offset
            )
            let songs = result.song ?? []
            if songs.isEmpty { break }

            for song in songs {
                serverSongIds.insert(song.id)
                if let existing = localMap[song.id] {
                    if hasSongChanged(existing, song) {
                        updateSongFields(existing, from: song)
                        stats.songsUpdated += 1
                    }
                } else {
                    let cached = CachedSong(from: song)
                    if let albumId = song.albumId {
                        cached.album = albumMap[albumId]
                    }
                    context.insert(cached)
                    localMap[song.id] = cached
                    stats.songsAdded += 1
                }
            }

            totalFetched += songs.count
            syncProgress = "Syncing songs… \(totalFetched)"
            offset += songs.count

            if totalFetched % 2000 == 0 {
                try context.save()
                lastSyncStats = stats
            }

            if songs.count < songPageSize { break }
        }

        // Remove songs no longer on server (only on full sync, preserve downloads)
        if !incremental {
            for local in allLocal where !serverSongIds.contains(local.id) && local.download == nil {
                context.delete(local)
                stats.songsRemoved += 1
            }
        }

        try context.save()
        lastSyncStats = stats
        await updateServerModifiedTimestamp(client: client)
        let songAdded = stats.songsAdded
        let songUpdated = stats.songsUpdated
        let songRemoved = stats.songsRemoved
        syncLog.info("Synced \(totalFetched) songs (+\(songAdded) ~\(songUpdated) -\(songRemoved))")
    }

    private func hasSongChanged(_ cached: CachedSong, _ server: Song) -> Bool {
        cached.title != server.title ||
        cached.artist != server.artist ||
        cached.albumName != server.album ||
        cached.track != server.track ||
        cached.year != server.year ||
        cached.genre != server.genre ||
        cached.duration != server.duration ||
        cached.isStarred != (server.starred != nil) ||
        cached.coverArtId != server.coverArt ||
        cached.bitRate != server.bitRate
    }

    private func updateSongFields(_ cached: CachedSong, from song: Song) {
        cached.title = song.title
        cached.artist = song.artist
        cached.albumArtist = song.albumArtist
        cached.albumName = song.album
        cached.albumId = song.albumId
        cached.artistId = song.artistId
        cached.coverArtId = song.coverArt
        cached.track = song.track
        cached.discNumber = song.discNumber
        cached.year = song.year
        cached.genre = song.genre
        cached.duration = song.duration
        cached.bitRate = song.bitRate
        cached.suffix = song.suffix
        cached.contentType = song.contentType
        cached.size = song.size
        cached.isStarred = song.starred != nil
        cached.rating = song.userRating ?? 0
        cached.cachedAt = Date()
    }

    // MARK: - Playlists

    private func syncPlaylists(client: SubsonicClient, context: ModelContext,
                               stats: inout SyncStats) async throws {
        syncProgress = "Syncing playlists…"
        let playlists = try await client.getPlaylists()
        var serverPlaylistIds = Set<String>()

        let allLocal = try context.fetch(FetchDescriptor<CachedPlaylist>())
        let localMap = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })

        for playlist in playlists {
            serverPlaylistIds.insert(playlist.id)
            let detail = try await client.getPlaylist(id: playlist.id)
            upsertPlaylist(detail, context: context, localMap: localMap)
            stats.playlistsSynced += 1
        }

        for local in allLocal where !serverPlaylistIds.contains(local.id) {
            context.delete(local)
        }

        try context.save()
        lastSyncStats = stats
        syncLog.info("Synced \(playlists.count) playlists with entries")
    }

    private func upsertPlaylist(_ playlist: Playlist, context: ModelContext,
                                localMap: [String: CachedPlaylist]) {
        let cached: CachedPlaylist
        if let existing = localMap[playlist.id] {
            existing.name = playlist.name
            existing.songCount = playlist.songCount
            existing.duration = playlist.duration
            existing.coverArtId = playlist.coverArt
            existing.owner = playlist.owner
            existing.isPublic = playlist.isPublic ?? false
            existing.cachedAt = Date()
            cached = existing
        } else {
            cached = CachedPlaylist(from: playlist)
            context.insert(cached)
        }

        for entry in cached.entries {
            context.delete(entry)
        }

        if let songs = playlist.entry {
            for (index, song) in songs.enumerated() {
                let entry = CachedPlaylistEntry(songId: song.id, order: index)
                entry.playlist = cached
                context.insert(entry)
            }
        }
    }

    // MARK: - Cover Art Prefetch

    private func prefetchCoverArt(client: SubsonicClient, context: ModelContext) async {
        syncProgress = "Prefetching cover art…"

        var coverArtIds = Set<String>()

        let albums = (try? context.fetch(FetchDescriptor<CachedAlbum>())) ?? []
        for album in albums {
            if let id = album.coverArtId { coverArtIds.insert(id) }
        }

        let artists = (try? context.fetch(FetchDescriptor<CachedArtist>())) ?? []
        for artist in artists {
            if let id = artist.coverArtId { coverArtIds.insert(id) }
        }

        let total = coverArtIds.count
        guard total > 0 else { return }
        syncLog.info("Prefetching \(total) cover art images")

        let pipeline = ImagePipeline.shared
        let urlMap: [(String, URL)] = coverArtIds.map { id in
            (id, client.coverArtURL(id: id, size: 600))
        }

        var fetched = 0
        let batchSize = 10
        for batchStart in stride(from: 0, to: urlMap.count, by: batchSize) {
            let batch = urlMap[batchStart..<min(batchStart + batchSize, urlMap.count)]
            await withTaskGroup(of: Void.self) { group in
                for (_, url) in batch {
                    group.addTask {
                        let request = ImageRequest(url: url)
                        if pipeline.cache.containsCachedImage(for: request) { return }
                        _ = try? await pipeline.image(for: request)
                    }
                }
            }
            fetched += batch.count
            syncProgress = "Prefetching cover art… \(fetched)/\(total)"
        }

        syncLog.info("Cover art prefetch complete: \(fetched) processed")
    }

    // MARK: - Sync History

    private func saveSyncHistory(stats: SyncStats, mode: SyncMode,
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
        guard let old = try? context.fetch(descriptor), !old.isEmpty else { return }
        for entry in old {
            context.delete(entry)
        }
        try? context.save()
    }
}
