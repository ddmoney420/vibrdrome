#if os(macOS)
import Foundation
import SwiftData
import os.log

private let homeLog = Logger(subsystem: "com.vibrdrome.app", category: "MacHome")

/// Drives the macOS home page. Lives on AppState so data is prefetched during
/// the loading screen — in parallel with cache rebuild and server sync.
@Observable
@MainActor
final class MacHomeViewModel {

    // MARK: - Section data

    var jumpBackInAlbums: [Album] = []
    var recentlyAddedAlbums: [Album] = []
    var topArtists: [(id: String?, name: String, count: Int, coverArtId: String?)] = []
    var starredSongs: [Song] = []
    var favoriteAlbums: [Album] = []
    var mostPlayedAlbums: [Album] = []
    var featuredGenreName: String = ""
    var featuredGenreAlbums: [Album] = []
    var randomPickAlbums: [Album] = []

    // MARK: - Quick action state

    var isLoadingRandomMix = false
    var isLoadingRandomAlbum = false
    var isLoadingShuffleFavorites = false

    // MARK: - Layout config

    var layoutConfig = MacHomeLayoutConfig.load()

    // MARK: - Internal

    private var hasLoaded = false

    // MARK: - Prefetch (called during loading screen alongside cache rebuild + sync)

    /// Loads local data immediately and fires network fetches in parallel.
    /// Guarded by `hasLoaded` so subsequent appearances don't re-fetch.
    func prefetch(client: SubsonicClient, container: ModelContainer, libraryCache: LibraryDataCache) async {
        guard !hasLoaded else { return }
        hasLoaded = true

        let context = ModelContext(container)
        loadLocalData(modelContext: context, libraryCache: libraryCache)
        await fetchNetworkData(client: client)
    }

    /// Force a re-fetch (e.g. after a post-sync cache rebuild).
    func reload(client: SubsonicClient, container: ModelContainer, libraryCache: LibraryDataCache) async {
        hasLoaded = false
        await prefetch(client: client, container: container, libraryCache: libraryCache)
    }

    // MARK: - Local data (synchronous, instant — no network)

    private func loadLocalData(modelContext: ModelContext, libraryCache: LibraryDataCache) {
        loadJumpBackIn(modelContext: modelContext)
        loadTopArtists(modelContext: modelContext)
        loadStarredSongs(modelContext: modelContext)
        loadFavoriteAlbums(libraryCache: libraryCache)
        seedRecentlyAdded(modelContext: modelContext)
    }

    private func loadJumpBackIn(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PlayHistory>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        guard let plays = try? modelContext.fetch(descriptor) else { return }

        // Collect unique songIds in play order, limited to what we need
        var orderedSongIds: [String] = []
        var seen = Set<String>()
        for play in plays {
            guard !play.songId.isEmpty, !seen.contains(play.songId) else { continue }
            seen.insert(play.songId)
            orderedSongIds.append(play.songId)
            if orderedSongIds.count == 12 { break }
        }
        guard !orderedSongIds.isEmpty else { return }

        // Batch-fetch the CachedSong records to resolve albumIds
        let songIdSet = orderedSongIds
        let songDescriptor = FetchDescriptor<CachedSong>(
            predicate: #Predicate<CachedSong> { song in songIdSet.contains(song.id) }
        )
        let cachedSongs = (try? modelContext.fetch(songDescriptor)) ?? []
        let albumIdBySongId = Dictionary(
            uniqueKeysWithValues: cachedSongs.compactMap { s -> (String, String)? in
                guard let albumId = s.albumId else { return nil }
                return (s.id, albumId)
            }
        )

        // Build PlayHistory lookup for metadata
        let historyBySongId = Dictionary(
            plays.prefix(100).map { ($0.songId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Deduplicate by albumId, preserve play order
        var result: [Album] = []
        var seenAlbums = Set<String>()
        for songId in orderedSongIds {
            guard let albumId = albumIdBySongId[songId] else { continue }
            guard !seenAlbums.contains(albumId) else { continue }
            seenAlbums.insert(albumId)
            let play = historyBySongId[songId]
            let album = Album(
                id: albumId,
                name: play?.albumName ?? "Unknown Album",
                artist: play?.artistName,
                artistId: nil,
                artists: nil, displayArtist: nil,
                coverArt: play?.coverArtId,
                songCount: nil, duration: nil, playCount: nil,
                year: nil, genre: nil, genres: nil,
                starred: nil, played: nil, created: nil,
                userRating: nil, song: nil,
                replayGain: nil, musicBrainzId: nil, recordLabels: nil,
                version: nil, releaseTypes: nil, moods: nil, sortName: nil,
                originalReleaseDate: nil, releaseDate: nil,
                isCompilation: nil, explicitStatus: nil, discTitles: nil
            )
            result.append(album)
            if result.count == 12 { break }
        }
        jumpBackInAlbums = result
        homeLog.debug("Jump Back In: \(result.count) albums from play history")
    }

    private func loadTopArtists(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PlayHistory>(
            sortBy: [SortDescriptor(\.playedAt, order: .reverse)]
        )
        guard let plays = try? modelContext.fetch(descriptor) else { return }
        var counts: [String: Int] = [:]
        var latestArt: [String: String] = [:]
        for play in plays {
            let artist = play.artistName ?? "Unknown"
            counts[artist, default: 0] += 1
            if latestArt[artist] == nil, let art = play.coverArtId { latestArt[artist] = art }
        }
        topArtists = counts.sorted { $0.value > $1.value }
            .prefix(12)
            .map { (id: nil, name: $0.key, count: $0.value, coverArtId: latestArt[$0.key]) }
    }

    private func enrichTopArtistsFromServer(client: SubsonicClient) async {
        guard !topArtists.isEmpty else { return }
        guard let indexes = try? await client.getArtists() else { return }
        let serverArtists = indexes.flatMap { $0.artist ?? [] }
        let byName = Dictionary(serverArtists.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        topArtists = topArtists.map { entry in
            if let match = byName[entry.name] {
                return (id: match.id, name: entry.name, count: entry.count, coverArtId: match.coverArt ?? entry.coverArtId)
            }
            return entry
        }
    }

    private func loadStarredSongs(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<CachedSong>(
            predicate: #Predicate<CachedSong> { $0.isStarred },
            sortBy: [SortDescriptor(\.title)]
        )
        guard let fetched = try? modelContext.fetch(descriptor), !fetched.isEmpty else { return }
        var songs = fetched.map { $0.toSong() }
        songs.shuffle()
        starredSongs = Array(songs.prefix(20))
    }

    private func loadFavoriteAlbums(libraryCache: LibraryDataCache) {
        guard let albums = libraryCache.albums else { return }
        favoriteAlbums = albums
            .filter { $0.userRating ?? 0 >= 4 || $0.starred != nil }
            .sorted { ($0.userRating ?? 0) > ($1.userRating ?? 0) }
            .prefix(20)
            .map { $0 }
    }

    private func seedRecentlyAdded(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<CachedAlbum>(
            sortBy: [SortDescriptor(\CachedAlbum.created, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        if let cached = try? modelContext.fetch(descriptor), !cached.isEmpty {
            recentlyAddedAlbums = cached.map { $0.toAlbum() }
        }
    }

    // MARK: - Network data (all in parallel)

    private func fetchNetworkData(client: SubsonicClient) async {
        async let newestTask = fetchAlbums(client: client, type: .newest, ttl: 0, size: 20)
        async let frequentTask = fetchAlbums(client: client, type: .frequent, ttl: 600, size: 20)
        async let randomTask = fetchAlbums(client: client, type: .random, ttl: 0, size: 20)
        async let starredTask: Starred2? = {
            if let cached = await client.cachedResponse(for: .getStarred2(), ttl: 600) {
                return cached.starred2
            }
            return try? await client.getStarred()
        }()

        let (newest, frequent, random, starred) = await (newestTask, frequentTask, randomTask, starredTask)

        recentlyAddedAlbums = newest.isEmpty ? recentlyAddedAlbums : newest
        mostPlayedAlbums = frequent
        randomPickAlbums = random

        if let starred {
            if let albums = starred.album, !albums.isEmpty {
                favoriteAlbums = Array(albums.prefix(20))
            }
            if var songs = starred.song, !songs.isEmpty {
                songs.shuffle()
                starredSongs = Array(songs.prefix(20))
            }
        }

        await enrichTopArtistsFromServer(client: client)
        await loadFeaturedGenre(client: client)
        homeLog.info("Home data fetch complete")
    }

    private func fetchAlbums(client: SubsonicClient, type: AlbumListType,
                             ttl: TimeInterval, size: Int) async -> [Album] {
        let endpoint = SubsonicEndpoint.getAlbumList2(type: type, size: size)
        if ttl > 0, let cached = await client.cachedResponse(for: endpoint, ttl: ttl) {
            return cached.albumList2?.album ?? []
        }
        return (try? await client.getAlbumList(type: type, size: size)) ?? []
    }

    private func loadFeaturedGenre(client: SubsonicClient) async {
        guard let genres = try? await client.getGenres() else { return }
        let seeded = genres.filter { ($0.albumCount ?? 0) >= 5 }
        guard !seeded.isEmpty else { return }
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let pick = seeded[dayOfYear % seeded.count]
        featuredGenreName = pick.value.cleanedGenreDisplay
        featuredGenreAlbums = (try? await client.getAlbumList(type: .byGenre, size: 15, genre: pick.value)) ?? []
    }

    // MARK: - Quick Actions

    func playRandomMix(appState: AppState) async {
        guard !isLoadingRandomMix else { return }
        isLoadingRandomMix = true
        defer { isLoadingRandomMix = false }
        guard let pool = try? await appState.subsonicClient.getRandomSongs(size: 200) else { return }
        let mix = SidebarContentView.diversifyMix(pool, target: 50, maxPerArtist: 3)
        guard let first = mix.first else { return }
        AudioEngine.shared.play(song: first, from: mix, at: 0)
        AudioEngine.shared.playingFromContext = "Random Mix"
        appState.activeSidePanel = .queue
    }

    func playRandomAlbum(appState: AppState) async {
        guard !isLoadingRandomAlbum else { return }
        isLoadingRandomAlbum = true
        defer { isLoadingRandomAlbum = false }
        guard let albums = try? await appState.subsonicClient.getAlbumList(type: .random, size: 1),
              let album = albums.first,
              let detail = try? await appState.subsonicClient.getAlbum(id: album.id),
              let songs = detail.song, let first = songs.first else { return }
        AudioEngine.shared.play(song: first, from: songs, at: 0)
        appState.pendingNavigation = .album(id: album.id)
    }

    func shuffleFavorites(appState: AppState) async {
        guard !isLoadingShuffleFavorites, !starredSongs.isEmpty else { return }
        isLoadingShuffleFavorites = true
        defer { isLoadingShuffleFavorites = false }
        let shuffled = starredSongs.shuffled()
        guard let first = shuffled.first else { return }
        AudioEngine.shared.play(song: first, from: shuffled, at: 0)
        AudioEngine.shared.playingFromContext = "Shuffle Favorites"
        appState.activeSidePanel = .queue
    }
}
#endif
