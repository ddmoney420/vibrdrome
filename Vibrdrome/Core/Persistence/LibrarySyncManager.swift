import Foundation
import Nuke
import SwiftData
import os.log

private let syncLog = Logger(subsystem: "com.vibrdrome.app", category: "LibrarySync")

/// Syncs full library metadata (albums, artists, songs) from the Subsonic API
/// into SwiftData for local filtering and search.
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

    private let albumPageSize = 500
    private let songPageSize = 500

    /// Run a full library sync: albums, artists, then songs.
    func sync(client: SubsonicClient, container: ModelContainer) async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        syncProgress = "Starting sync…"
        defer {
            isSyncing = false
            syncProgress = nil
        }

        do {
            let context = ModelContext(container)
            context.autosaveEnabled = false

            try await syncAlbums(client: client, context: context)
            try await syncArtists(client: client, context: context)
            try await syncSongs(client: client, context: context)
            try await syncPlaylists(client: client, context: context)

            try context.save()
            lastSyncDate = Date()
            syncLog.info("Library sync completed successfully")

            // Prefetch cover art in background after metadata sync
            await prefetchCoverArt(client: client, context: context)
        } catch {
            syncError = "Sync failed: \(error.localizedDescription)"
            syncLog.error("Library sync failed: \(error)")
        }
    }

    /// Check if sync is stale (>24h) and trigger background sync if needed.
    func syncIfStale(client: SubsonicClient, container: ModelContainer) async {
        guard let last = lastSyncDate else {
            await sync(client: client, container: container)
            return
        }
        if Date().timeIntervalSince(last) > 86400 {
            await sync(client: client, container: container)
        }
    }

    // MARK: - Albums

    private func syncAlbums(client: SubsonicClient, context: ModelContext) async throws {
        syncProgress = "Syncing albums…"
        var offset = 0
        var serverAlbumIds = Set<String>()
        var totalFetched = 0

        while true {
            let page = try await client.getAlbumList(
                type: .alphabeticalByName, size: albumPageSize, offset: offset
            )
            if page.isEmpty { break }

            for album in page {
                serverAlbumIds.insert(album.id)
                upsertAlbum(album, context: context)
            }

            totalFetched += page.count
            syncProgress = "Syncing albums… \(totalFetched)"
            offset += page.count

            if page.count < albumPageSize { break }
        }

        // Remove albums no longer on server
        let allLocal = try context.fetch(FetchDescriptor<CachedAlbum>())
        for local in allLocal where !serverAlbumIds.contains(local.id) {
            context.delete(local)
        }

        try context.save()
        syncLog.info("Synced \(totalFetched) albums")
    }

    private func upsertAlbum(_ album: Album, context: ModelContext) {
        let albumId = album.id
        var descriptor = FetchDescriptor<CachedAlbum>(
            predicate: #Predicate { $0.id == albumId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.update(from: album)
        } else {
            context.insert(CachedAlbum(from: album))
        }
    }

    // MARK: - Artists

    private func syncArtists(client: SubsonicClient, context: ModelContext) async throws {
        syncProgress = "Syncing artists…"
        let indexes = try await client.getArtists()
        var serverArtistIds = Set<String>()

        for index in indexes {
            for artist in index.artist ?? [] {
                serverArtistIds.insert(artist.id)
                upsertArtist(artist, context: context)
            }
        }

        // Remove artists no longer on server
        let allLocal = try context.fetch(FetchDescriptor<CachedArtist>())
        for local in allLocal where !serverArtistIds.contains(local.id) {
            context.delete(local)
        }

        try context.save()
        syncLog.info("Synced \(serverArtistIds.count) artists")
    }

    private func upsertArtist(_ artist: Artist, context: ModelContext) {
        let artistId = artist.id
        var descriptor = FetchDescriptor<CachedArtist>(
            predicate: #Predicate { $0.id == artistId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.name = artist.name
            existing.coverArtId = artist.coverArt
            existing.albumCount = artist.albumCount
            existing.isStarred = artist.starred != nil
            existing.cachedAt = Date()
        } else {
            context.insert(CachedArtist(from: artist))
        }
    }

    // MARK: - Songs

    private func syncSongs(client: SubsonicClient, context: ModelContext) async throws {
        syncProgress = "Syncing songs…"
        var offset = 0
        var serverSongIds = Set<String>()
        var totalFetched = 0

        // Use search3 with empty query to get all songs
        while true {
            let result = try await client.search(
                query: "", artistCount: 0, albumCount: 0,
                songCount: songPageSize, songOffset: offset
            )
            let songs = result.song ?? []
            if songs.isEmpty { break }

            for song in songs {
                serverSongIds.insert(song.id)
                upsertSong(song, context: context)
            }

            totalFetched += songs.count
            syncProgress = "Syncing songs… \(totalFetched)"
            offset += songs.count

            // Save periodically to manage memory
            if totalFetched % 2000 == 0 {
                try context.save()
            }

            if songs.count < songPageSize { break }
        }

        // Remove songs no longer on server (only cached songs without downloads)
        let allLocal = try context.fetch(FetchDescriptor<CachedSong>())
        for local in allLocal where !serverSongIds.contains(local.id) && local.download == nil {
            context.delete(local)
        }

        try context.save()
        syncLog.info("Synced \(totalFetched) songs")
    }

    private func upsertSong(_ song: Song, context: ModelContext) {
        let songId = song.id
        var descriptor = FetchDescriptor<CachedSong>(
            predicate: #Predicate { $0.id == songId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.title = song.title
            existing.artist = song.artist
            existing.albumArtist = song.albumArtist
            existing.albumName = song.album
            existing.albumId = song.albumId
            existing.artistId = song.artistId
            existing.coverArtId = song.coverArt
            existing.track = song.track
            existing.discNumber = song.discNumber
            existing.year = song.year
            existing.genre = song.genre
            existing.duration = song.duration
            existing.bitRate = song.bitRate
            existing.suffix = song.suffix
            existing.contentType = song.contentType
            existing.size = song.size
            existing.isStarred = song.starred != nil
            existing.rating = song.userRating ?? 0
            existing.cachedAt = Date()
        } else {
            let cached = CachedSong(from: song)
            // Link to album if it exists
            if let albumId = song.albumId {
                var albumDesc = FetchDescriptor<CachedAlbum>(
                    predicate: #Predicate { $0.id == albumId }
                )
                albumDesc.fetchLimit = 1
                cached.album = try? context.fetch(albumDesc).first
            }
            context.insert(cached)
        }
    }

    // MARK: - Playlists

    private func syncPlaylists(client: SubsonicClient, context: ModelContext) async throws {
        syncProgress = "Syncing playlists…"
        let playlists = try await client.getPlaylists()
        var serverPlaylistIds = Set<String>()

        for playlist in playlists {
            serverPlaylistIds.insert(playlist.id)

            // Fetch full playlist with song entries
            let detail = try await client.getPlaylist(id: playlist.id)
            upsertPlaylist(detail, context: context)
        }

        // Remove playlists no longer on server
        let allLocal = try context.fetch(FetchDescriptor<CachedPlaylist>())
        for local in allLocal where !serverPlaylistIds.contains(local.id) {
            context.delete(local)
        }

        try context.save()
        syncLog.info("Synced \(playlists.count) playlists with entries")
    }

    private func upsertPlaylist(_ playlist: Playlist, context: ModelContext) {
        let playlistId = playlist.id
        var descriptor = FetchDescriptor<CachedPlaylist>(
            predicate: #Predicate { $0.id == playlistId }
        )
        descriptor.fetchLimit = 1

        let cached: CachedPlaylist
        if let existing = try? context.fetch(descriptor).first {
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

        // Sync playlist entries (ordered song references)
        // Remove old entries
        for entry in cached.entries {
            context.delete(entry)
        }

        // Add current entries in order
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

        // Collect all unique coverArtIds from albums (albums cover most songs too)
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

        // Pre-compute URLs on the main actor (SubsonicClient is @MainActor)
        let urlMap: [(String, URL)] = coverArtIds.map { id in
            (id, client.coverArtURL(id: id, size: 600))
        }

        var fetched = 0

        // Process in batches of 10 concurrent requests
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
}
