#if os(macOS)
import Foundation
import SwiftData

/// Runs filter-sidebar metadata fetches off the main actor.
@ModelActor
actor FilterMetadataActor {
    func loadAlbumFilterMetadata() -> (genres: [String], labels: [String], artists: [FilterArtistItem]) {
        // Genres: fetch from AlbumGenre index (one row per genre link, no full album hydration)
        var genreDescriptor = FetchDescriptor<AlbumGenre>()
        genreDescriptor.propertiesToFetch = [\.name]
        let albumGenres = (try? modelContext.fetch(genreDescriptor)) ?? []
        var genreSet = Set(albumGenres.map(\.name)).subtracting([""])

        // Union in song genres for tracks not linked to an album
        var songGenreDescriptor = FetchDescriptor<CachedSong>()
        songGenreDescriptor.propertiesToFetch = [\.genre]
        let songs = (try? modelContext.fetch(songGenreDescriptor)) ?? []
        genreSet.formUnion(Set(songs.compactMap(\.genre)).subtracting([""]))

        // Labels: fetch only the label column from CachedAlbum
        var labelDescriptor = FetchDescriptor<CachedAlbum>()
        labelDescriptor.propertiesToFetch = [\.label]
        let albums = (try? modelContext.fetch(labelDescriptor)) ?? []
        let labelSet = Set(albums.compactMap(\.label)).subtracting([""])

        let genres = genreSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let labels = labelSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let artists = fetchArtists()
        return (genres, labels, artists)
    }

    func loadArtistFilterMetadata() -> [String] {
        var descriptor = FetchDescriptor<AlbumGenre>()
        descriptor.propertiesToFetch = [\.name]
        let links = (try? modelContext.fetch(descriptor)) ?? []
        let genreSet = Set(links.map(\.name)).subtracting([""])
        return genreSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func loadSongFilterMetadata() -> (genres: [String], artists: [FilterArtistItem]) {
        var descriptor = FetchDescriptor<CachedSong>()
        descriptor.propertiesToFetch = [\.genre]
        let songs = (try? modelContext.fetch(descriptor)) ?? []
        let genreSet = Set(songs.compactMap(\.genre)).subtracting([""])
        let genres = genreSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return (genres, fetchArtists())
    }

    private func fetchArtists() -> [FilterArtistItem] {
        var descriptor = FetchDescriptor<CachedArtist>(sortBy: [SortDescriptor<CachedArtist>(\.name)])
        descriptor.propertiesToFetch = [\.id, \.name, \.albumCount, \.coverArtId]
        return ((try? modelContext.fetch(descriptor)) ?? []).map {
            FilterArtistItem(id: $0.id, name: $0.name, coverArtId: $0.coverArtId, albumCount: $0.albumCount)
        }
    }
}
#endif
