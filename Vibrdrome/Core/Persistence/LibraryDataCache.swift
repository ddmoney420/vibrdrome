import Foundation
import SwiftData
import os.log

private let cacheLog = Logger(subsystem: "com.vibrdrome.app", category: "LibraryCache")

/// Pre-computes converted model arrays on a background thread so library tabs
/// are ready instantly when first selected.
@Observable
@MainActor
final class LibraryDataCache {
    private(set) var songs: [Song]?
    private(set) var artists: [Artist]?
    private(set) var albums: [Album]?
    private(set) var songFilterYears: [Int]?
    private(set) var songFilterArtists: [String]?
    private(set) var songFilterGenres: [String]?
    private(set) var labelCounts: [String: Int]?
    private(set) var labelArt: [String: String]?

    /// Incremented after each successful rebuild so views can detect changes via `.onChange`.
    /// Intentionally in-session only (not persisted) — resets to 0 on launch. Views only need
    /// to detect changes *within* a session; cross-launch staleness is handled by `LibrarySyncManager`.
    private(set) var generation: Int = 0

    /// True once the first cache build completes. Used by the loading screen to gate
    /// the main UI — becomes true after `generation` moves from 0 → 1.
    private(set) var isReady: Bool = false

    private var buildTask: Task<Void, Never>?

    /// Kick off a background rebuild of all cached model arrays.
    func rebuild(container: ModelContainer) {
        buildTask?.cancel()
        buildTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.buildCache(container: container)
            }.value
            guard !Task.isCancelled else { return }
            songs = result.songs
            artists = result.artists
            albums = result.albums
            songFilterYears = result.years
            songFilterArtists = result.artistNames
            songFilterGenres = result.genres
            labelCounts = result.labelCounts
            labelArt = result.labelArt
            generation += 1
            isReady = true
            cacheLog.info("Library cache ready — \(result.songs.count) songs, \(result.artists.count) artists, \(result.albums.count) albums")
        }
    }

    /// Clear all cached data (e.g. on logout or server switch).
    func invalidate() {
        buildTask?.cancel()
        songs = nil
        artists = nil
        albums = nil
        songFilterYears = nil
        songFilterArtists = nil
        songFilterGenres = nil
        labelCounts = nil
        labelArt = nil
        isReady = false
    }

    // MARK: - Background Work

    private struct CacheResult: Sendable {
        let songs: [Song]
        let artists: [Artist]
        let albums: [Album]
        let years: [Int]
        let artistNames: [String]
        let genres: [String]
        let labelCounts: [String: Int]
        let labelArt: [String: String]
    }

    nonisolated private static func buildCache(container: ModelContainer) -> CacheResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Artists
        let artistDescriptor = FetchDescriptor<CachedArtist>(sortBy: [SortDescriptor<CachedArtist>(\.name)])
        let convertedArtists: [Artist]
        if let cached = try? context.fetch(artistDescriptor) {
            convertedArtists = cached.map { $0.toArtist() }
        } else {
            convertedArtists = []
        }

        // Albums — prefetch genreLinks so toAlbum() doesn't fault each relationship lazily,
        // which would race if two contexts are running concurrently.
        var albumDescriptor = FetchDescriptor<CachedAlbum>(sortBy: [SortDescriptor<CachedAlbum>(\.name)])
        albumDescriptor.relationshipKeyPathsForPrefetching = [\.genreLinks]
        let cachedAlbums = (try? context.fetch(albumDescriptor)) ?? []
        let convertedAlbums = cachedAlbums.map { $0.toAlbum() }

        var labelCountsMap: [String: Int] = [:]
        var labelArtMap: [String: String] = [:]
        for album in cachedAlbums {
            guard let label = album.label, !label.isEmpty else { continue }
            labelCountsMap[label, default: 0] += 1
            if labelArtMap[label] == nil, let artId = album.coverArtId {
                labelArtMap[label] = artId
            }
        }

        // Songs — single pass for conversion + year/artist extraction
        let songDescriptor = FetchDescriptor<CachedSong>(sortBy: [SortDescriptor<CachedSong>(\.title)])
        var convertedSongs = [Song]()
        var yearSet = Set<Int>()
        var artistSet = Set<String>()
        if let cached = try? context.fetch(songDescriptor) {
            convertedSongs.reserveCapacity(cached.count)
            for item in cached {
                convertedSongs.append(item.toSong())
                if let year = item.year { yearSet.insert(year) }
                if let artist = item.artist { artistSet.insert(artist) }
            }
        }

        // Genres from AlbumGenre index — avoids re-scanning the full song table
        var genreSet = Set<String>()
        if let genreLinks = try? context.fetch(FetchDescriptor<AlbumGenre>()) {
            for link in genreLinks where !link.name.isEmpty { genreSet.insert(link.name) }
        }
        // Union in song genres for tracks not linked to an album
        for song in convertedSongs {
            if let g = song.genre, !g.isEmpty { genreSet.insert(g) }
        }

        let sortedYears = yearSet.sorted(by: >)
        let sortedArtists = Array(artistSet)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let sortedGenres = Array(genreSet)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        return CacheResult(
            songs: convertedSongs,
            artists: convertedArtists,
            albums: convertedAlbums,
            years: sortedYears,
            artistNames: sortedArtists,
            genres: sortedGenres,
            labelCounts: labelCountsMap,
            labelArt: labelArtMap
        )
    }
}
