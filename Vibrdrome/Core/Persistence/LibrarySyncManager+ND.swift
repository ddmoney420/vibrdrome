import SwiftData

// MARK: - Navidrome-native sync helpers (extracted to keep LibrarySyncManager within size limits)

extension LibrarySyncManager {

    // swiftlint:disable:next function_parameter_count
    nonisolated static func syncAlbumsND(
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

    nonisolated static func hasNDAlbumChanged(_ cached: CachedAlbum, _ server: NDAlbum) -> Bool {
        cached.name != server.name ||
        cached.artistName != server.albumArtist ||
        cached.artistId != server.albumArtistId ||
        cached.year != (server.minYear ?? server.year) ||
        cached.minYear != server.minYear ||
        cached.maxYear != server.maxYear ||
        cached.songCount != server.songCount ||
        cached.duration != server.duration.map({ Int($0) }) ||
        cached.isStarred != (server.starred ?? false) ||
        cached.userRating != (server.rating ?? 0) ||
        cached.playCount != (server.playCount ?? 0) ||
        cached.isCompilation != (server.compilation ?? false) ||
        cached.label != server.recordLabel ||
        cached.catalogNum != server.catalogNum ||
        cached.releaseType != server.releaseType ||
        cached.releaseCountry != server.releaseCountry ||
        cached.releaseStatus != server.releaseStatus ||
        cached.mood != server.mood ||
        cached.grouping != server.grouping ||
        cached.mediaType != server.mediaType ||
        cached.sortAlbumName != server.sortAlbumName ||
        cached.sortAlbumArtistName != server.sortAlbumArtistName ||
        cached.musicBrainzId != server.mbzAlbumId ||
        cached.mbzAlbumArtistId != server.mbzAlbumArtistId ||
        cached.mbzReleaseGroupId != server.mbzReleaseGroupId ||
        cached.mbzAlbumType != server.mbzAlbumType ||
        cached.mbzAlbumComment != server.mbzAlbumComment ||
        Set(cached.genres) != Set(server.allGenres)
    }

    // swiftlint:disable:next function_parameter_count
    nonisolated static func syncSongsND(
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

    nonisolated static func hasNDSongChanged(_ cached: CachedSong, _ server: NDSong) -> Bool {
        cached.title != server.title ||
        cached.artist != server.artist ||
        cached.albumName != server.album ||
        cached.track != server.trackNumber ||
        cached.year != server.year ||
        Set(cached.genres) != Set(server.allGenres) ||
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
        cached.hasCoverArt != (server.hasCoverArt ?? false) ||
        cached.rgTrackGain != server.rgTrackGain ||
        cached.rgAlbumGain != server.rgAlbumGain ||
        cached.displayArtistOverride != server.participantArtistOverride
    }
}
