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

    /// Incremented after each successful rebuild so views can detect changes via `.onChange`.
    /// Intentionally in-session only (not persisted) — resets to 0 on launch. Views only need
    /// to detect changes *within* a session; cross-launch staleness is handled by `LibrarySyncManager`.
    private(set) var generation: Int = 0

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
            generation += 1
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
    }

    // MARK: - Background Work

    private struct CacheResult: Sendable {
        let songs: [Song]
        let artists: [Artist]
        let albums: [Album]
        let years: [Int]
        let artistNames: [String]
        let genres: [String]
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

        // Albums
        let albumDescriptor = FetchDescriptor<CachedAlbum>(sortBy: [SortDescriptor<CachedAlbum>(\.name)])
        let convertedAlbums: [Album]
        if let cached = try? context.fetch(albumDescriptor) {
            convertedAlbums = cached.map { $0.toAlbum() }
        } else {
            convertedAlbums = []
        }

        // Songs — single pass for conversion + filter option extraction
        let songDescriptor = FetchDescriptor<CachedSong>(sortBy: [SortDescriptor<CachedSong>(\.title)])
        var convertedSongs = [Song]()
        var yearSet = Set<Int>()
        var artistSet = Set<String>()
        var genreSet = Set<String>()
        if let cached = try? context.fetch(songDescriptor) {
            convertedSongs.reserveCapacity(cached.count)
            for item in cached {
                convertedSongs.append(item.toSong())
                if let year = item.year { yearSet.insert(year) }
                if let artist = item.artist { artistSet.insert(artist) }
                if let genre = item.genre { genreSet.insert(genre) }
            }
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
            genres: sortedGenres
        )
    }
}
