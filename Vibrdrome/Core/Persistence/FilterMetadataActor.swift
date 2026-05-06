#if os(macOS)
import Foundation
import SwiftData

/// Runs filter-sidebar metadata fetches off the main actor.
@ModelActor
actor FilterMetadataActor {
    func loadAlbumFilterMetadata() -> (genres: [String], labels: [String], artists: [FilterArtistItem]) {
        let albums = (try? modelContext.fetch(FetchDescriptor<CachedAlbum>())) ?? []
        let songs = (try? modelContext.fetch(FetchDescriptor<CachedSong>())) ?? []

        var genreSet = Set(albums.flatMap { $0.genres }).subtracting([""])
        genreSet.formUnion(Set(songs.compactMap { $0.genre }).subtracting([""]))

        let labelSet = Set(albums.compactMap { $0.label }).subtracting([""])
        let labels = labelSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let genres = genreSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let artists = fetchArtists()
        return (genres, labels, artists)
    }

    func loadArtistFilterMetadata() -> [String] {
        let albums = (try? modelContext.fetch(FetchDescriptor<CachedAlbum>())) ?? []
        let genreSet = Set(albums.flatMap { $0.genres }).subtracting([""])
        return genreSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func loadSongFilterMetadata() -> (genres: [String], artists: [FilterArtistItem]) {
        let songs = (try? modelContext.fetch(FetchDescriptor<CachedSong>())) ?? []
        let genreSet = Set(songs.compactMap { $0.genre }).subtracting([""])
        let genres = genreSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return (genres, fetchArtists())
    }

    private func fetchArtists() -> [FilterArtistItem] {
        let sort = SortDescriptor<CachedArtist>(\.name)
        var descriptor = FetchDescriptor<CachedArtist>(sortBy: [sort])
        descriptor.propertiesToFetch = [\.id, \.name, \.albumCount, \.coverArtId]
        return ((try? modelContext.fetch(descriptor)) ?? []).map {
            FilterArtistItem(id: $0.id, name: $0.name, coverArtId: $0.coverArtId, albumCount: $0.albumCount)
        }
    }
}
#endif
