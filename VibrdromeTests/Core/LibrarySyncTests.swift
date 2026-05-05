import Testing
import Foundation
import SwiftData
@testable import Vibrdrome

/// Tests for library sync infrastructure: SyncMode, SyncStats,
/// CachedAlbum/CachedArtist round-trip conversions, and update detection.
struct LibrarySyncTests {

    // MARK: - SyncMode

    @Test func syncModeRawValues() {
        #expect(SyncMode.full.rawValue == "full")
        #expect(SyncMode.incremental.rawValue == "incremental")
        #expect(SyncMode.background.rawValue == "background")
    }

    // MARK: - SyncStats

    @Test func syncStatsTotalChangesEmpty() {
        let stats = LibrarySyncManager.SyncStats()
        #expect(stats.totalChanges == 0)
    }

    @Test func syncStatsTotalChangesAggregatesAll() {
        var stats = LibrarySyncManager.SyncStats()
        stats.albumsAdded = 5
        stats.albumsUpdated = 3
        stats.albumsRemoved = 1
        stats.artistsAdded = 10
        stats.artistsUpdated = 2
        stats.artistsRemoved = 0
        stats.songsAdded = 100
        stats.songsUpdated = 20
        stats.songsRemoved = 5
        #expect(stats.totalChanges == 146)
    }

    @Test func syncStatsDuration() throws {
        let stats = LibrarySyncManager.SyncStats()
        // Duration is time since startTime, should be >= 0
        #expect(stats.duration >= 0)
    }

    // MARK: - CachedAlbum Round-Trip

    @Test func cachedAlbumRoundTripPreservesId() {
        let album = makeAlbum(id: "alb-1")
        let cached = CachedAlbum(from: album)
        let restored = cached.toAlbum()
        #expect(restored.id == "alb-1")
    }

    @Test func cachedAlbumRoundTripPreservesName() {
        let album = makeAlbum(name: "OK Computer")
        let cached = CachedAlbum(from: album)
        let restored = cached.toAlbum()
        #expect(restored.name == "OK Computer")
    }

    @Test func cachedAlbumRoundTripPreservesArtist() {
        let album = makeAlbum(artist: "Radiohead")
        let cached = CachedAlbum(from: album)
        let restored = cached.toAlbum()
        #expect(restored.artist == "Radiohead")
    }

    @Test func cachedAlbumRoundTripPreservesYear() {
        let album = makeAlbum(year: 1997)
        let cached = CachedAlbum(from: album)
        let restored = cached.toAlbum()
        #expect(restored.year == 1997)
    }

    @Test func cachedAlbumRoundTripPreservesGenre() {
        let album = makeAlbum(genre: "Alternative Rock")
        let cached = CachedAlbum(from: album)
        let restored = cached.toAlbum()
        #expect(restored.genre == "Alternative Rock")
    }

    @Test func cachedAlbumStarredConversion() {
        let starred = makeAlbum(starred: "2024-01-01T00:00:00Z")
        let cachedStarred = CachedAlbum(from: starred)
        #expect(cachedStarred.isStarred == true)
        #expect(cachedStarred.toAlbum().starred == "true")

        let unstarred = makeAlbum(starred: nil)
        let cachedUnstarred = CachedAlbum(from: unstarred)
        #expect(cachedUnstarred.isStarred == false)
        #expect(cachedUnstarred.toAlbum().starred == nil)
    }

    @Test func cachedAlbumRoundTripPreservesRating() {
        let album = makeAlbum(userRating: 4)
        let cached = CachedAlbum(from: album)
        let restored = cached.toAlbum()
        #expect(restored.userRating == 4)
    }

    @Test func cachedAlbumRoundTripNilRatingBecomesNil() {
        let album = makeAlbum(userRating: nil)
        let cached = CachedAlbum(from: album)
        #expect(cached.userRating == 0)
        let restored = cached.toAlbum()
        #expect(restored.userRating == nil)
    }

    @Test func cachedAlbumRoundTripPreservesLabel() {
        let album = makeAlbum(label: "XL Recordings")
        let cached = CachedAlbum(from: album)
        let restored = cached.toAlbum()
        #expect(restored.label == "XL Recordings")
    }

    @Test func cachedAlbumUpdateAppliesChanges() {
        let original = makeAlbum(id: "alb-1", name: "Old Name", year: 2020)
        let cached = CachedAlbum(from: original)

        let updated = makeAlbum(id: "alb-1", name: "New Name", year: 2024, genre: "Electronic")
        cached.update(from: updated)

        #expect(cached.name == "New Name")
        #expect(cached.year == 2024)
        #expect(cached.genres == ["Electronic"])
    }

    @Test func cachedAlbumUpdatePreservesIdOnMismatch() {
        // update(from:) doesn't change ID — it's the caller's responsibility to match
        let cached = CachedAlbum(from: makeAlbum(id: "alb-1"))
        cached.update(from: makeAlbum(id: "alb-2", name: "Different"))
        #expect(cached.id == "alb-1")
        #expect(cached.name == "Different")
    }

    // MARK: - CachedArtist Round-Trip

    @Test func cachedArtistRoundTripPreservesId() {
        let artist = makeArtist(id: "art-1")
        let cached = CachedArtist(from: artist)
        let restored = cached.toArtist()
        #expect(restored.id == "art-1")
    }

    @Test func cachedArtistRoundTripPreservesName() {
        let artist = makeArtist(name: "Boards of Canada")
        let cached = CachedArtist(from: artist)
        let restored = cached.toArtist()
        #expect(restored.name == "Boards of Canada")
    }

    @Test func cachedArtistRoundTripPreservesAlbumCount() {
        let artist = makeArtist(albumCount: 7)
        let cached = CachedArtist(from: artist)
        let restored = cached.toArtist()
        #expect(restored.albumCount == 7)
    }

    @Test func cachedArtistStarredConversion() {
        let starred = makeArtist(starred: "2024-06-01T12:00:00Z")
        let cached = CachedArtist(from: starred)
        #expect(cached.isStarred == true)

        let unstarred = makeArtist(starred: nil)
        let cachedU = CachedArtist(from: unstarred)
        #expect(cachedU.isStarred == false)
    }

    // MARK: - SyncHistory

    @Test func syncHistoryTotalChanges() {
        let history = SyncHistory(syncType: "full")
        history.albumsAdded = 10
        history.songsAdded = 100
        history.artistsUpdated = 5
        #expect(history.totalChanges == 115)
    }

    @Test func syncHistorySummaryNoChanges() {
        let history = SyncHistory(syncType: "incremental")
        #expect(history.summary == "No changes")
    }

    @Test func syncHistorySummaryWithChanges() {
        let history = SyncHistory(syncType: "full")
        history.albumsAdded = 5
        history.songsUpdated = 10
        history.artistsRemoved = 2
        let summary = history.summary
        #expect(summary.contains("+5"))
        #expect(summary.contains("~10"))
        #expect(summary.contains("-2"))
    }

    @Test func syncHistorySummaryOnFailure() {
        let history = SyncHistory(syncType: "full")
        history.succeeded = false
        history.errorMessage = "Connection timeout"
        #expect(history.summary == "Failed: Connection timeout")
    }

    // MARK: - Helpers

    private func makeAlbum(
        id: String = "test",
        name: String = "Test Album",
        artist: String? = nil,
        artistId: String? = nil,
        year: Int? = nil,
        genre: String? = nil,
        songCount: Int? = nil,
        duration: Int? = nil,
        starred: String? = nil,
        userRating: Int? = nil,
        label: String? = nil
    ) -> Album {
        Album(
            id: id, name: name, artist: artist, artistId: artistId,
            coverArt: nil, songCount: songCount, duration: duration,
            year: year, genre: genre, starred: starred, created: nil,
            userRating: userRating, song: nil, replayGain: nil,
            musicBrainzId: nil,
            recordLabels: label.map { [RecordLabel(name: $0)] },
            genres: nil
        )
    }

    private func makeArtist(
        id: String = "test",
        name: String = "Test Artist",
        coverArt: String? = nil,
        albumCount: Int? = nil,
        starred: String? = nil
    ) -> Artist {
        Artist(
            id: id, name: name, coverArt: coverArt,
            albumCount: albumCount, starred: starred, album: nil
        )
    }

    // MARK: - SwiftData Schema Migration

    @Test func migrationFromBuild45SchemaSucceeds() throws {
        // Use a temp file-backed store so data persists across containers
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        // Build 45 schema — the entities that existed before 7a
        let oldSchema = Schema([
            DownloadedSong.self,
            PlayHistory.self,
            ServerConfig.self,
            OfflinePlaylist.self,
            PendingAction.self,
            SavedQueue.self,
            AlbumCollection.self,
        ])
        let oldConfig = ModelConfiguration(schema: oldSchema, url: storeURL)

        // Phase 1: create store with old schema and seed data
        do {
            let oldContainer = try ModelContainer(for: oldSchema, configurations: [oldConfig])
            let ctx = ModelContext(oldContainer)
            let collection = AlbumCollection(name: "Test Collection", listType: .alphabeticalByName)
            ctx.insert(collection)
            try ctx.save()
        }
        // oldContainer deallocated — store is on disk

        // Phase 2: reopen same store with expanded schema (7a)
        let newSchema = Schema([
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
            AlbumCollection.self,
            SyncHistory.self,
        ])
        let newConfig = ModelConfiguration(schema: newSchema, url: storeURL)

        // Lightweight migration: adding entities should not throw
        let newContainer = try ModelContainer(for: newSchema, configurations: [newConfig])
        let newCtx = ModelContext(newContainer)

        // Verify old data survived the migration
        let collections = try newCtx.fetch(FetchDescriptor<AlbumCollection>())
        #expect(collections.count == 1)
        #expect(collections.first?.name == "Test Collection")

        // Verify new entities are accessible and empty
        let albums = try newCtx.fetch(FetchDescriptor<CachedAlbum>())
        #expect(albums.isEmpty)

        let syncHistory = try newCtx.fetch(FetchDescriptor<SyncHistory>())
        #expect(syncHistory.isEmpty)
    }
}
