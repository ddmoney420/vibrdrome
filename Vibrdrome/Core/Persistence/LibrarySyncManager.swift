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
    static let shared = LibrarySyncManager()

    /// Configured by AppState at login for convenience sync calls.
    weak var client: SubsonicClient?
    var container: ModelContainer?

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

    // Page sizes for paginated API calls. 500 is a safe default for most Subsonic servers;
    // could be made configurable per-server if needed for very large or constrained instances.
    // `nonisolated` so the `nonisolated static` sync helpers running off the main actor can
    // read them without hopping back to MainActor just to read a constant.
    nonisolated static let albumPageSize = 500
    nonisolated static let songPageSize = 500

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
    func sync(client: SubsonicClient, ndClient: NavidromeNativeClient? = nil, container: ModelContainer) async {
        await performSync(mode: .full, client: client, ndClient: ndClient, container: container)
    }

    /// Run an incremental sync — only fetches changes since last sync.
    func incrementalSync(client: SubsonicClient, ndClient: NavidromeNativeClient? = nil, container: ModelContainer) async {
        await performSync(mode: .incremental, client: client, ndClient: ndClient, container: container)
    }

    /// Convenience: sync using the configured client and container.
    func syncIfStale() async {
        guard let client, let container else { return }
        await syncIfStale(client: client, container: container)
    }

    /// Check if sync is stale and trigger the appropriate sync mode.
    func syncIfStale(client: SubsonicClient, ndClient: NavidromeNativeClient? = nil, container: ModelContainer) async {
        guard let last = lastSyncDate else {
            await performSync(mode: .full, client: client, ndClient: ndClient, container: container)
            return
        }
        let elapsed = Date().timeIntervalSince(last)
        guard elapsed > staleInterval else { return }

        let serverChanged = await hasServerChanged(client: client)

        if serverChanged {
            let lastFull = UserDefaults.standard.object(forKey: UserDefaultsKeys.lastFullSyncDate) as? Date
            let needsFullSync = lastFull == nil || Date().timeIntervalSince(lastFull!) > fullSyncInterval
            let mode: SyncMode = needsFullSync ? .full : .incremental
            await performSync(mode: mode, client: client, ndClient: ndClient, container: container)
        } else {
            lastSyncDate = Date()
            syncLog.info("Server data unchanged, skipping sync (trigger: auto-stale-check)")
        }
    }

    // MARK: - Change Detection Polling

    /// Start periodic polling for server changes while the app is active.
    func startPolling(client: SubsonicClient, ndClient: NavidromeNativeClient? = nil, container: ModelContainer) {
        stopPolling()
        let intervalMinutes = UserDefaults.standard.integer(forKey: UserDefaultsKeys.syncPollingInterval)
        let interval = max(TimeInterval(intervalMinutes > 0 ? intervalMinutes : 15) * 60, 300)

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, !self.isSyncing else { continue }

                let changed = await self.hasServerChanged(client: client)
                if changed {
                    syncLog.info("Polling detected server changes, triggering incremental sync (trigger: auto-poll)")
                    await self.performSync(mode: .incremental, client: client, ndClient: ndClient, container: container)
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

    // swiftlint:disable:next function_body_length
    private func performSync(mode: SyncMode, client: SubsonicClient, ndClient: NavidromeNativeClient? = nil, container: ModelContainer) async {
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

        // Progress callback — hops to MainActor to update @Observable state.
        // Marked @Sendable so it's safe to pass into nonisolated static helpers.
        @Sendable func updateProgress(_ message: String) {
            Task { @MainActor in
                self.syncProgress = message
            }
        }
        @Sendable func publishPartialStats(_ partial: SyncStats) {
            Task { @MainActor in
                self.lastSyncStats = partial
            }
        }

        do {
            // All heavy lifting (SwiftData fetch/insert/save + per-row diff loops) happens on a
            // detached task using a background ModelContext. This keeps the main actor free so
            // the polling task (which fires every 15+ min) doesn't stutter UI on large libraries.
            // Background mode is incremental-only: BGAppRefreshTask gets ~30s of CPU, a full sync
            // on a large library would hit the expirationHandler and be killed.
            let incremental = (mode == .incremental || mode == .background)

            stats = try await Task.detached(priority: .utility) { () -> SyncStats in
                var working = SyncStats()

                try await Self.syncAlbumsOffMain(
                    client: client, ndClient: ndClient, container: container,
                    stats: &working, incremental: incremental,
                    progress: updateProgress, publishStats: publishPartialStats
                )
                try await Self.syncArtistsOffMain(
                    client: client, container: container,
                    stats: &working, incremental: incremental,
                    progress: updateProgress, publishStats: publishPartialStats
                )
                try await Self.syncSongsOffMain(
                    client: client, ndClient: ndClient, container: container,
                    stats: &working, incremental: incremental,
                    progress: updateProgress, publishStats: publishPartialStats
                )
                try await Self.syncPlaylistsOffMain(
                    client: client, container: container,
                    stats: &working,
                    progress: updateProgress, publishStats: publishPartialStats
                )
                return working
            }.value

            if mode == .full {
                UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.lastFullSyncDate)
            }

            lastSyncDate = Date()
            lastSyncStats = stats

            // Save sync history on a fresh context (the work context above is already gone).
            let historyContext = ModelContext(container)
            historyContext.autosaveEnabled = false
            saveSyncHistory(stats: stats, mode: mode, context: historyContext)

            syncLog.info("""
                Library sync (\(mode.rawValue)) completed in \
                \(String(format: "%.1f", stats.duration))s — \
                \(stats.totalChanges) changes \
                (+\(stats.albumsAdded + stats.artistsAdded + stats.songsAdded) \
                ~\(stats.albumsUpdated + stats.artistsUpdated + stats.songsUpdated) \
                -\(stats.albumsRemoved + stats.artistsRemoved + stats.songsRemoved))
                """)

            // Prefetch cover art in background after metadata sync. Also fires when existing
            // albums/artists gain a new coverArtId (e.g. server-side art-scan completes after
            // the metadata was already cached), not just when new rows are inserted.
            let artChanged = stats.albumsAdded > 0 || stats.artistsAdded > 0 ||
                stats.albumsUpdated > 0 || stats.artistsUpdated > 0
            if artChanged {
                await warmImageCache(client: client, container: container)
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

    // MARK: - Albums

    // swiftlint:disable:next function_parameter_count
    nonisolated static func syncAlbumsOffMain(
        client: SubsonicClient,
        ndClient: NavidromeNativeClient?,
        container: ModelContainer,
        stats: inout SyncStats,
        incremental: Bool,
        progress: @Sendable (String) -> Void,
        publishStats: @Sendable (SyncStats) -> Void
    ) async throws {
        progress("Syncing albums…")

        let context = ModelContext(container)
        context.autosaveEnabled = false

        let allLocal = try context.fetch(FetchDescriptor<CachedAlbum>())
        var localMap = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })
        var serverAlbumIds = Set<String>()
        var totalFetched = 0

        if let ndClient, await ndClient.isAvailable {
            totalFetched = try await syncAlbumsND(
                ndClient: ndClient, context: context, allLocal: allLocal,
                localMap: &localMap, serverIds: &serverAlbumIds, stats: &stats, progress: progress
            )
        } else if incremental {
            totalFetched = try await syncAlbumsIncremental(
                client: client, context: context,
                localMap: &localMap, serverIds: &serverAlbumIds, stats: &stats
            )
        } else {
            totalFetched = try await syncAlbumsSubsonic(
                client: client, context: context, allLocal: allLocal,
                localMap: &localMap, serverIds: &serverAlbumIds, stats: &stats, progress: progress
            )
        }

        try context.save()
        publishStats(stats)
        let added = stats.albumsAdded
        let updated = stats.albumsUpdated
        let removed = stats.albumsRemoved
        syncLog.info("Synced \(totalFetched) albums (+\(added) ~\(updated) -\(removed))")
    }

    nonisolated private static func syncAlbumsIncremental(
        client: SubsonicClient, context: ModelContext,
        localMap: inout [String: CachedAlbum], serverIds: inout Set<String>,
        stats: inout SyncStats
    ) async throws -> Int {
        let newestAlbums = try await client.getAlbumList(type: .newest, size: albumPageSize)
        for album in newestAlbums {
            serverIds.insert(album.id)
            if let existing = localMap[album.id] {
                if hasAlbumChanged(existing, album) { existing.update(from: album); stats.albumsUpdated += 1 }
            } else {
                let cached = CachedAlbum(from: album)
                context.insert(cached); localMap[album.id] = cached; stats.albumsAdded += 1
            }
        }
        return newestAlbums.count
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated private static func syncAlbumsND(
        ndClient: NavidromeNativeClient, context: ModelContext, allLocal: [CachedAlbum],
        localMap: inout [String: CachedAlbum], serverIds: inout Set<String>,
        stats: inout SyncStats, progress: @Sendable (String) -> Void
    ) async throws -> Int {
        var start = 0
        var totalFetched = 0
        while true {
            let (page, total) = try await ndClient.getAlbums(start: start, end: start + albumPageSize)
            if page.isEmpty { break }
            for ndAlbum in page {
                serverIds.insert(ndAlbum.id)
                if let existing = localMap[ndAlbum.id] {
                    if hasNDAlbumChanged(existing, ndAlbum) { existing.update(from: ndAlbum); stats.albumsUpdated += 1 }
                } else {
                    let cached = CachedAlbum(from: ndAlbum)
                    context.insert(cached); localMap[ndAlbum.id] = cached; stats.albumsAdded += 1
                }
            }
            totalFetched += page.count
            progress("Syncing albums… \(totalFetched)/\(total)")
            start += page.count
            if totalFetched >= total || page.count < albumPageSize { break }
        }
        for local in allLocal where !serverIds.contains(local.id) { context.delete(local); stats.albumsRemoved += 1 }
        return totalFetched
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated private static func syncAlbumsSubsonic(
        client: SubsonicClient, context: ModelContext, allLocal: [CachedAlbum],
        localMap: inout [String: CachedAlbum], serverIds: inout Set<String>,
        stats: inout SyncStats, progress: @Sendable (String) -> Void
    ) async throws -> Int {
        var offset = 0
        var totalFetched = 0
        while true {
            let page = try await client.getAlbumList(type: .alphabeticalByName, size: albumPageSize, offset: offset)
            if page.isEmpty { break }
            for album in page {
                serverIds.insert(album.id)
                if let existing = localMap[album.id] {
                    if hasAlbumChanged(existing, album) { existing.update(from: album); stats.albumsUpdated += 1 }
                } else {
                    let cached = CachedAlbum(from: album)
                    context.insert(cached); localMap[album.id] = cached; stats.albumsAdded += 1
                }
            }
            totalFetched += page.count
            progress("Syncing albums… \(totalFetched)")
            offset += page.count
            if page.count < albumPageSize { break }
        }
        for local in allLocal where !serverIds.contains(local.id) { context.delete(local); stats.albumsRemoved += 1 }
        return totalFetched
    }

    nonisolated static func hasAlbumChanged(_ cached: CachedAlbum, _ server: Album) -> Bool {
        cached.name != server.name ||
        cached.artistName != server.artist ||
        cached.artistId != server.artistId ||
        cached.year != server.year ||
        cached.genre != server.genre ||
        cached.songCount != server.songCount ||
        cached.duration != server.duration ||
        cached.isStarred != (server.starred != nil) ||
        cached.coverArtId != server.coverArt ||
        cached.created != server.created ||
        cached.userRating != (server.userRating ?? 0) ||
        cached.label != server.label ||
        cached.mbzAlbumId != server.musicBrainzId
    }

    nonisolated static func hasNDAlbumChanged(_ cached: CachedAlbum, _ server: NDAlbum) -> Bool {
        cached.name != server.name ||
        cached.artistId != server.artistId ||
        cached.year != server.year ||
        cached.genre != server.genre ||
        cached.songCount != server.songCount ||
        cached.duration != server.duration.map({ Int($0) }) ||
        cached.isStarred != (server.starred ?? false) ||
        cached.userRating != (server.rating ?? 0) ||
        cached.mbzAlbumId != server.mbzAlbumId ||
        cached.mbzAlbumArtistId != server.mbzAlbumArtistId ||
        cached.mbzReleaseGroupId != server.mbzReleaseGroupId ||
        cached.playCount != (server.playCount ?? 0) ||
        cached.isCompilation != (server.compilation ?? false)
    }

    // MARK: - Artists

    // swiftlint:disable:next function_parameter_count
    nonisolated static func syncArtistsOffMain(
        client: SubsonicClient,
        container: ModelContainer,
        stats: inout SyncStats,
        incremental: Bool,
        progress: @Sendable (String) -> Void,
        publishStats: @Sendable (SyncStats) -> Void
    ) async throws {
        progress("Syncing artists…")
        let indexes = try await client.getArtists()
        var serverArtistIds = Set<String>()

        let context = ModelContext(container)
        context.autosaveEnabled = false

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
        publishStats(stats)
        let artAdded = stats.artistsAdded
        let artUpdated = stats.artistsUpdated
        let artRemoved = stats.artistsRemoved
        syncLog.info("Synced \(serverArtistIds.count) artists (+\(artAdded) ~\(artUpdated) -\(artRemoved))")
    }

    nonisolated static func hasArtistChanged(_ cached: CachedArtist, _ server: Artist) -> Bool {
        cached.name != server.name ||
        cached.coverArtId != server.coverArt ||
        cached.albumCount != server.albumCount ||
        cached.isStarred != (server.starred != nil)
    }

    // MARK: - Songs

    // swiftlint:disable:next function_parameter_count
    nonisolated static func syncSongsOffMain(
        client: SubsonicClient,
        ndClient: NavidromeNativeClient?,
        container: ModelContainer,
        stats: inout SyncStats,
        incremental: Bool,
        progress: @Sendable (String) -> Void,
        publishStats: @Sendable (SyncStats) -> Void
    ) async throws {
        progress("Syncing songs…")

        let context = ModelContext(container)
        context.autosaveEnabled = false

        let allLocal = try context.fetch(FetchDescriptor<CachedSong>())
        var localMap = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })
        let albumMap = Dictionary(
            uniqueKeysWithValues: (try context.fetch(FetchDescriptor<CachedAlbum>())).map { ($0.id, $0) }
        )
        var serverSongIds = Set<String>()

        let totalFetched: Int
        if let ndClient, await ndClient.isAvailable {
            totalFetched = try await syncSongsND(
                ndClient: ndClient, context: context, allLocal: allLocal, albumMap: albumMap,
                localMap: &localMap, serverIds: &serverSongIds, stats: &stats,
                progress: progress, publishStats: publishStats
            )
        } else {
            totalFetched = try await syncSongsSubsonic(
                client: client, context: context, allLocal: allLocal, albumMap: albumMap,
                localMap: &localMap, serverIds: &serverSongIds, stats: &stats,
                incremental: incremental, progress: progress, publishStats: publishStats
            )
        }

        try context.save()
        publishStats(stats)
        await updateServerModifiedTimestamp(client: client)
        let songAdded = stats.songsAdded
        let songUpdated = stats.songsUpdated
        let songRemoved = stats.songsRemoved
        syncLog.info("Synced \(totalFetched) songs (+\(songAdded) ~\(songUpdated) -\(songRemoved))")
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated private static func syncSongsND(
        ndClient: NavidromeNativeClient, context: ModelContext,
        allLocal: [CachedSong], albumMap: [String: CachedAlbum],
        localMap: inout [String: CachedSong], serverIds: inout Set<String>,
        stats: inout SyncStats,
        progress: @Sendable (String) -> Void,
        publishStats: @Sendable (SyncStats) -> Void
    ) async throws -> Int {
        var start = 0
        var totalFetched = 0
        while true {
            let (page, total) = try await ndClient.getSongs(start: start, end: start + songPageSize)
            if page.isEmpty { break }
            for ndSong in page {
                serverIds.insert(ndSong.id)
                if let existing = localMap[ndSong.id] {
                    if hasNDSongChanged(existing, ndSong) {
                        existing.update(from: ndSong)
                        if let albumId = ndSong.albumId { existing.album = albumMap[albumId] }
                        stats.songsUpdated += 1
                    }
                } else {
                    let cached = CachedSong(from: ndSong)
                    if let albumId = ndSong.albumId { cached.album = albumMap[albumId] }
                    context.insert(cached); localMap[ndSong.id] = cached; stats.songsAdded += 1
                }
            }
            totalFetched += page.count
            progress("Syncing songs… \(totalFetched)/\(total)")
            start += page.count
            if totalFetched % 2000 == 0 { try context.save(); publishStats(stats) }
            if totalFetched >= total || page.count < songPageSize { break }
        }
        for local in allLocal where !serverIds.contains(local.id) && local.download == nil {
            context.delete(local); stats.songsRemoved += 1
        }
        return totalFetched
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated private static func syncSongsSubsonic(
        client: SubsonicClient, context: ModelContext,
        allLocal: [CachedSong], albumMap: [String: CachedAlbum],
        localMap: inout [String: CachedSong], serverIds: inout Set<String>,
        stats: inout SyncStats, incremental: Bool,
        progress: @Sendable (String) -> Void,
        publishStats: @Sendable (SyncStats) -> Void
    ) async throws -> Int {
        var offset = 0
        var totalFetched = 0
        while true {
            let result = try await client.search(
                query: "", artistCount: 0, albumCount: 0, songCount: songPageSize, songOffset: offset
            )
            let songs = result.song ?? []
            if songs.isEmpty { break }
            for song in songs {
                serverIds.insert(song.id)
                if let existing = localMap[song.id] {
                    if hasSongChanged(existing, song) { updateSongFields(existing, from: song); stats.songsUpdated += 1 }
                } else {
                    let cached = CachedSong(from: song)
                    if let albumId = song.albumId { cached.album = albumMap[albumId] }
                    context.insert(cached); localMap[song.id] = cached; stats.songsAdded += 1
                }
            }
            totalFetched += songs.count
            progress("Syncing songs… \(totalFetched)")
            offset += songs.count
            if totalFetched % 2000 == 0 { try context.save(); publishStats(stats) }
            if songs.count < songPageSize { break }
        }
        if !incremental {
            for local in allLocal where !serverIds.contains(local.id) && local.download == nil {
                context.delete(local); stats.songsRemoved += 1
            }
        }
        return totalFetched
    }

    /// Nonisolated so songs sync (off MainActor) can call it directly.
    nonisolated static func updateServerModifiedTimestamp(client: SubsonicClient) async {
        do {
            let indexes = try await client.getIndexes()
            if let lastModified = indexes.lastModified {
                UserDefaults.standard.set(lastModified, forKey: UserDefaultsKeys.lastServerModified)
            }
        } catch {
            syncLog.warning("Failed to fetch server modified timestamp: \(error.localizedDescription)")
        }
    }

    nonisolated static func hasSongChanged(_ cached: CachedSong, _ server: Song) -> Bool {
        cached.title != server.title ||
        cached.artist != server.artist ||
        cached.albumName != server.album ||
        cached.track != server.track ||
        cached.year != server.year ||
        cached.genre != server.genre ||
        cached.duration != server.duration ||
        cached.isStarred != (server.starred != nil) ||
        cached.coverArtId != server.coverArt ||
        cached.bitRate != server.bitRate ||
        cached.bitDepth != server.bitDepth ||
        cached.samplingRate != server.samplingRate ||
        cached.comment != server.comment ||
        cached.bpm != server.bpm ||
        cached.mbzRecordingId != server.musicBrainzId
    }

    nonisolated static func updateSongFields(_ cached: CachedSong, from song: Song) {
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
        cached.bitDepth = song.bitDepth
        cached.samplingRate = song.samplingRate
        cached.comment = song.comment
        cached.suffix = song.suffix
        cached.contentType = song.contentType
        cached.size = song.size
        cached.bpm = song.bpm
        cached.dateAdded = song.created.flatMap { ISO8601DateFormatter().date(from: $0) }
        cached.mbzRecordingId = song.musicBrainzId
        cached.isStarred = song.starred != nil
        cached.rating = song.userRating ?? 0
        cached.cachedAt = Date()
    }

    nonisolated static func hasNDSongChanged(_ cached: CachedSong, _ server: NDSong) -> Bool {
        cached.title != server.title ||
        cached.artist != server.artist ||
        cached.albumName != server.album ||
        cached.track != server.trackNumber ||
        cached.year != server.year ||
        cached.genre != server.genre ||
        cached.duration != server.duration.map({ Int($0) }) ||
        cached.isStarred != (server.starred ?? false) ||
        cached.bitRate != server.bitRate ||
        cached.bitDepth != server.bitDepth ||
        cached.samplingRate != server.sampleRate ||
        cached.channels != server.channels ||
        cached.comment != server.comment ||
        cached.bpm != server.bpm ||
        cached.mbzRecordingId != server.mbzReleaseTrackId ||
        cached.rating != (server.rating ?? 0) ||
        cached.playCount != (server.playCount ?? 0) ||
        cached.isCompilation != (server.compilation ?? false) ||
        cached.hasCoverArt != (server.hasCoverArt ?? false)
    }

    // MARK: - Playlists

    nonisolated static func syncPlaylistsOffMain(
        client: SubsonicClient,
        container: ModelContainer,
        stats: inout SyncStats,
        progress: @Sendable (String) -> Void,
        publishStats: @Sendable (SyncStats) -> Void
    ) async throws {
        progress("Syncing playlists…")

        let context = ModelContext(container)
        context.autosaveEnabled = false

        let playlists = try await client.getPlaylists()

        // Source of truth for "what exists on the server" is the getPlaylists() list — NOT the
        // set of playlists whose details we managed to fetch below. A transient failure on a
        // single getPlaylist(id:) call must not cause its cached row to be deleted locally.
        let serverPlaylistIds = Set(playlists.map { $0.id })

        let allLocal = try context.fetch(FetchDescriptor<CachedPlaylist>())
        let localMap = Dictionary(uniqueKeysWithValues: allLocal.map { ($0.id, $0) })

        // Fetch playlist details with bounded concurrency (tolerates individual failures e.g. deleted playlists)
        let details = await withTaskGroup(of: Playlist?.self, returning: [Playlist].self) { group in
            var results: [Playlist] = []
            var inflight = 0
            let maxConcurrency = 2

            for playlist in playlists {
                if inflight >= maxConcurrency {
                    if let detail = await group.next(), let playlist = detail {
                        results.append(playlist)
                    }
                    inflight -= 1
                }
                group.addTask {
                    try? await client.getPlaylist(id: playlist.id)
                }
                inflight += 1
            }

            for await detail in group {
                if let detail {
                    results.append(detail)
                }
            }
            return results
        }

        for detail in details {
            upsertPlaylist(detail, context: context, localMap: localMap)
            stats.playlistsSynced += 1
        }

        // Only delete local playlists that are confirmed missing from the server list.
        // Playlists whose detail fetch failed will simply retain their existing cached entries.
        for local in allLocal where !serverPlaylistIds.contains(local.id) {
            context.delete(local)
        }

        try context.save()
        publishStats(stats)
        syncLog.info("Synced \(playlists.count) playlists with entries")
    }

    nonisolated static func upsertPlaylist(_ playlist: Playlist, context: ModelContext,
                                           localMap: [String: CachedPlaylist]) {
        let cached: CachedPlaylist
        if let existing = localMap[playlist.id] {
            existing.name = playlist.name
            existing.songCount = playlist.songCount
            existing.duration = playlist.duration
            existing.coverArtId = playlist.coverArt
            existing.owner = playlist.owner
            existing.isPublic = playlist.isPublic ?? false
            existing.changed = playlist.changed
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

    /// Whether a prefetch pass already ran this session (avoids duplicate work).
    private var didPrefetchThisSession = false

    /// Warm the in-memory image cache on startup by loading all known cover art.
    /// Images already in memory are skipped; images in disk cache load instantly.
    /// Skipped if a prefetch already ran during sync this session.
    func warmImageCache(client: SubsonicClient, container: ModelContainer) async {
        guard !didPrefetchThisSession else { return }
        // Skip if a full prefetch completed recently (within 24 hours)
        if let lastPrefetch = UserDefaults.standard.object(forKey: UserDefaultsKeys.lastCoverArtPrefetchDate) as? Date,
           Date().timeIntervalSince(lastPrefetch) < 86_400 {
            didPrefetchThisSession = true
            return
        }
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

        // Filter out images already in memory or disk cache so we only fetch what's missing
        let dataCache = pipeline.configuration.dataCache as? DataCache
        let uncachedUrls: [(String, URL)] = coverArtIds.compactMap { id in
            let url = client.coverArtURL(id: id, size: 600)
            let request = ImageRequest(url: url)
            if pipeline.cache.containsCachedImage(for: request) { return nil }
            let key = pipeline.cache.makeDataCacheKey(for: request)
            if dataCache?.containsData(for: key) == true { return nil }
            return (id, url)
        }

        let alreadyCached = total - uncachedUrls.count
        guard !uncachedUrls.isEmpty else {
            didPrefetchThisSession = true
            UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.lastCoverArtPrefetchDate)
            syncLog.info("Cover art prefetch skipped — all \(total) images already cached")
            return
        }

        syncLog.info("Prefetching \(uncachedUrls.count) cover art images (\(alreadyCached) already cached)")

        let fetched = await prefetchBatches(uncachedUrls: uncachedUrls, total: total, alreadyCached: alreadyCached)

        didPrefetchThisSession = true
        UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.lastCoverArtPrefetchDate)
        syncLog.info("Cover art prefetch complete: \(fetched)/\(total) processed")
    }

    /// Fetch cover art in batches of 10 with per-image timeouts. Returns total processed count.
    private func prefetchBatches(uncachedUrls: [(String, URL)], total: Int, alreadyCached: Int) async -> Int {
        let pipeline = ImagePipeline.shared
        var fetched = alreadyCached
        let batchSize = 10
        let perImageTimeout: UInt64 = 15_000_000_000 // 15 seconds

        for batchStart in stride(from: 0, to: uncachedUrls.count, by: batchSize) {
            guard !Task.isCancelled else { break }
            let batch = uncachedUrls[batchStart..<min(batchStart + batchSize, uncachedUrls.count)]
            await withTaskGroup(of: Void.self) { group in
                for (_, url) in batch {
                    group.addTask {
                        let request = ImageRequest(url: url)
                        // Timeout prevents a single stalled request from blocking the entire prefetch
                        await withTaskGroup(of: Void.self) { inner in
                            inner.addTask {
                                _ = try? await pipeline.image(for: request)
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
