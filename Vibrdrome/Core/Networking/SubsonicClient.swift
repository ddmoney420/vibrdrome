import Foundation
import Observation
import os.log

private let networkLog = Logger(subsystem: "com.vibrdrome.app", category: "Network")

@Observable
@MainActor
final class SubsonicClient {
    private let session: URLSession
    private var auth: SubsonicAuth
    private var baseURL: URL

    private static let maxRetries = 3
    private static let retryDelays: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000] // 1s, 2s, 4s

    /// Internal marker for HTTP 429 so retry delay can honor Retry-After when present.
    private struct RateLimitError: Error {
        let retryAfterNanoseconds: UInt64?
    }

    var isConnected: Bool = false

    init(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        self.auth = SubsonicAuth(username: username, password: password)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        // Security hardening: disable cookies and credential caching
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        self.session = URLSession(configuration: config)
    }

    // MARK: - Retry Logic

    private func isRetryable(_ error: Error) -> Bool {
        if error is RateLimitError {
            return true
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        if let subsonicError = error as? SubsonicError {
            switch subsonicError {
            case .httpError(let code):
                return code == 429 || code >= 500
            default:
                return false
            }
        }
        return false
    }

    private func retryDelayNanoseconds(for error: Error, attempt: Int) -> UInt64? {
        guard isRetryable(error) else { return nil }

        if let rateLimitError = error as? RateLimitError,
           let retryAfter = rateLimitError.retryAfterNanoseconds {
            return retryAfter
        }

        return Self.retryDelays[min(attempt, Self.retryDelays.count - 1)]
    }

    private func parseRetryAfterNanoseconds(from response: HTTPURLResponse) -> UInt64? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !header.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(header), seconds > 0 {
            return UInt64(seconds * 1_000_000_000)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"

        guard let retryDate = formatter.date(from: header) else { return nil }
        let seconds = max(0, retryDate.timeIntervalSinceNow)
        guard seconds > 0 else { return nil }
        return UInt64(seconds * 1_000_000_000)
    }

    // MARK: - Core Request

    private func request(_ endpoint: SubsonicEndpoint) async throws -> SubsonicResponseBody {
        for attempt in 0...Self.maxRetries {
            do {
                return try await performRequest(endpoint)
            } catch {
                if attempt == Self.maxRetries {
                    if error is RateLimitError {
                        throw SubsonicError.httpError(429)
                    }
                    throw error
                }

                guard let delay = retryDelayNanoseconds(for: error, attempt: attempt) else {
                    throw error
                }

                if error is RateLimitError {
                    networkLog.warning("Rate limited on \(endpoint.path); retry \(attempt + 1)/\(Self.maxRetries) after \(delay / 1_000_000_000)s")
                } else {
                    networkLog.warning("Transient error on \(endpoint.path): \(error.localizedDescription)")
                    networkLog.info("Retry \(attempt + 1)/\(Self.maxRetries) for \(endpoint.path) after \(delay / 1_000_000_000)s")
                }

                try await Task.sleep(nanoseconds: delay)
            }
        }

        // Unreachable: the for-loop above always exits via `return` on success or `throw`
        // on the final attempt. Using fatalError makes that invariant explicit and will
        // surface immediately if the control-flow assumption is ever broken by a refactor.
        fatalError("SubsonicClient.request retry loop exited without returning or throwing")
    }

    private func performRequest(_ endpoint: SubsonicEndpoint) async throws -> SubsonicResponseBody {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SubsonicError.invalidURL
        }
        components.queryItems = auth.authParameters() + endpoint.queryItems
        // URLComponents leaves ';' unencoded (it's a sub-delimiter per RFC 3986), but
        // some servers parse ';' as an alternative query-parameter separator and reject
        // the request. Force-encode it so genre values like "Hip Hop; Pop" work.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: ";", with: "%3B")

        guard let url = components.url else {
            throw SubsonicError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 429, let httpResponse = response as? HTTPURLResponse {
                throw RateLimitError(retryAfterNanoseconds: parseRetryAfterNanoseconds(from: httpResponse))
            }
            if statusCode == 401, !AppState.shared.requiresReAuth {
                networkLog.warning("401 Unauthorized — triggering re-authentication prompt")
                AppState.shared.requiresReAuth = true
            }
            throw SubsonicError.httpError(statusCode)
        }

        let body = try decodeResponse(data)

        // Cache the raw response data on success
        let key = await ResponseCache.shared.cacheKey(for: endpoint)
        await ResponseCache.shared.store(data: data, for: key)

        return body
    }

    private func decodeResponse(_ data: Data) throws -> SubsonicResponseBody {
        let decoded: SubsonicResponse
        do {
            decoded = try JSONDecoder().decode(SubsonicResponse.self, from: data)
        } catch {
            throw SubsonicError.decodingError(error)
        }

        let body = decoded.subsonicResponse

        if body.status != "ok" {
            if let error = body.error {
                if error.code == 40, !AppState.shared.requiresReAuth {
                    networkLog.warning("Subsonic auth error (code 40) — triggering re-authentication prompt")
                    AppState.shared.requiresReAuth = true
                }
                throw SubsonicError.apiError(code: error.code, message: error.message)
            }
            throw SubsonicError.apiError(code: 0, message: "Server returned status: \(body.status)")
        }

        return body
    }

    /// Read a cached response for an endpoint, returning nil if missing or expired.
    func cachedResponse(for endpoint: SubsonicEndpoint, ttl: TimeInterval) async -> SubsonicResponseBody? {
        let key = await ResponseCache.shared.cacheKey(for: endpoint)
        guard let data = await ResponseCache.shared.data(for: key, ttl: ttl) else { return nil }
        return try? decodeResponse(data)
    }

    /// Invalidate cached response for an endpoint.
    func invalidateCache(for endpoint: SubsonicEndpoint) async {
        let key = await ResponseCache.shared.cacheKey(for: endpoint)
        await ResponseCache.shared.remove(for: key)
    }

    /// Clear all cached responses (logout, server switch).
    func clearCache() async {
        await ResponseCache.shared.clearAll()
    }

    /// Fire-and-forget request for endpoints that don't return meaningful data
    private func performAction(_ endpoint: SubsonicEndpoint) async throws {
        _ = try await request(endpoint)
    }

    // MARK: - URL Builders (for streaming, not decoded)

    private func buildURL(path: String, extra: [URLQueryItem] = []) -> URL {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { return baseURL }
        components.queryItems = auth.authParameters() + extra
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: ";", with: "%3B")
        return components.url ?? baseURL
    }

    func streamURL(id: String, maxBitRate: Int? = nil, format: String? = nil) -> URL {
        var extra = [URLQueryItem(name: "id", value: id)]
        if let maxBitRate { extra.append(URLQueryItem(name: "maxBitRate", value: "\(maxBitRate)")) }
        if let format { extra.append(URLQueryItem(name: "format", value: format)) }
        return buildURL(path: "/rest/stream", extra: extra)
    }

    func coverArtURL(id: String, size: Int? = nil) -> URL {
        var extra = [URLQueryItem(name: "id", value: id)]
        if let size { extra.append(URLQueryItem(name: "size", value: "\(size)")) }
        extra.append(URLQueryItem(name: "format", value: "webp"))
        return buildURL(path: "/rest/getCoverArt", extra: extra)
    }

    // MARK: - Raw JSON Metadata

    /// Returns the raw decoded JSON object under `subsonic-response` for an endpoint.
    /// Useful for diagnostics and exposing metadata fields not modeled in typed structs.
    func rawSubsonicResponse(for endpoint: SubsonicEndpoint) async throws -> [String: Any] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SubsonicError.invalidURL
        }
        components.queryItems = auth.authParameters() + endpoint.queryItems

        guard let url = components.url else {
            throw SubsonicError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SubsonicError.httpError(statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any],
              let subsonic = root["subsonic-response"] as? [String: Any] else {
            let error = NSError(
                domain: "SubsonicClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected JSON format"]
            )
            throw SubsonicError.decodingError(error)
        }

        if let status = subsonic["status"] as? String, status != "ok" {
            if let error = subsonic["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? 0
                let message = error["message"] as? String ?? "Unknown API error"
                throw SubsonicError.apiError(code: code, message: message)
            }
            throw SubsonicError.apiError(code: 0, message: "Server returned status: \(status)")
        }

        return subsonic
    }

    /// Returns Navidrome inspect metadata for a media item ID when available.
    /// This endpoint includes `rawTags` with full file tag key/value arrays.
    func inspectMetadata(id: String) async throws -> [String: Any] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("api/inspect"),
            resolvingAgainstBaseURL: false
        ) else {
            throw SubsonicError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "id", value: id)] + auth.authParameters()

        guard let url = components.url else {
            throw SubsonicError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SubsonicError.httpError(statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data)
        guard let payload = json as? [String: Any] else {
            let error = NSError(
                domain: "SubsonicClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected inspect JSON format"]
            )
            throw SubsonicError.decodingError(error)
        }

        return payload
    }

    func downloadURL(id: String) -> URL {
        buildURL(path: "/rest/download", extra: [URLQueryItem(name: "id", value: id)])
    }

    // MARK: - Convenience Methods

    func ping() async throws -> Bool {
        do {
            let body = try await request(.ping)
            isConnected = body.status == "ok"
            return isConnected
        } catch {
            isConnected = false
            throw error
        }
    }

    func getArtists(musicFolderId: String? = nil) async throws -> [ArtistIndex] {
        let body = try await request(.getArtists(musicFolderId: musicFolderId))
        return body.artists?.index ?? []
    }

    func getArtist(id: String) async throws -> Artist {
        let body = try await request(.getArtist(id: id))
        guard let artist = body.artist else {
            throw SubsonicError.apiError(code: 70, message: "Artist not found")
        }
        return artist
    }

    func getAlbum(id: String) async throws -> Album {
        let body = try await request(.getAlbum(id: id))
        guard let album = body.album else {
            throw SubsonicError.apiError(code: 70, message: "Album not found")
        }
        return album
    }

    func getSong(id: String) async throws -> Song {
        let body = try await request(.getSong(id: id))
        guard let song = body.song else {
            throw SubsonicError.apiError(code: 70, message: "Song not found")
        }
        return song
    }

    func search(query: String, artistCount: Int = 20, albumCount: Int = 20,
                songCount: Int = 40, artistOffset: Int = 0, albumOffset: Int = 0,
                songOffset: Int = 0, musicFolderId: String? = nil) async throws -> SearchResult3 {
        let body = try await request(.search3(query: query, artistCount: artistCount,
                                              albumCount: albumCount, songCount: songCount,
                                              artistOffset: artistOffset, albumOffset: albumOffset,
                                              songOffset: songOffset,
                                              musicFolderId: musicFolderId))
        return body.searchResult3 ?? SearchResult3(artist: nil, album: nil, song: nil)
    }

    func getAlbumList(type: AlbumListType, size: Int = 20,
                      offset: Int = 0, genre: String? = nil,
                      fromYear: Int? = nil, toYear: Int? = nil,
                      musicFolderId: String? = nil) async throws -> [Album] {
        let body = try await request(.getAlbumList2(
            type: type, size: size, offset: offset,
            fromYear: fromYear, toYear: toYear, genre: genre,
            musicFolderId: musicFolderId))
        return body.albumList2?.album ?? []
    }

    func getRandomSongs(size: Int = 20, genre: String? = nil,
                        musicFolderId: String? = nil) async throws -> [Song] {
        let body = try await request(.getRandomSongs(size: size, genre: genre,
                                                     musicFolderId: musicFolderId))
        return body.randomSongs?.song ?? []
    }

    func getStarred(musicFolderId: String? = nil) async throws -> Starred2 {
        let body = try await request(.getStarred2(musicFolderId: musicFolderId))
        return body.starred2 ?? Starred2(artist: nil, album: nil, song: nil)
    }

    func getGenres() async throws -> [Genre] {
        let body = try await request(.getGenres)
        return body.genres?.genre ?? []
    }

    func star(id: String? = nil, albumId: String? = nil, artistId: String? = nil) async throws {
        try await performAction(.star(id: id, albumId: albumId, artistId: artistId))
        await invalidateCache(for: .getStarred2())
    }

    func unstar(id: String? = nil, albumId: String? = nil, artistId: String? = nil) async throws {
        try await performAction(.unstar(id: id, albumId: albumId, artistId: artistId))
        await invalidateCache(for: .getStarred2())
    }

    func setRating(id: String, rating: Int) async throws {
        try await performAction(.setRating(id: id, rating: rating))
    }

    func scrobble(id: String, submission: Bool = true) async throws {
        try await performAction(.scrobble(id: id, submission: submission))
    }

    func getPlaylists() async throws -> [Playlist] {
        let body = try await request(.getPlaylists)
        return body.playlists?.playlist ?? []
    }

    func getPlaylist(id: String) async throws -> Playlist {
        let body = try await request(.getPlaylist(id: id))
        guard let playlist = body.playlist else {
            throw SubsonicError.apiError(code: 70, message: "Playlist not found")
        }
        return playlist
    }

    func createPlaylist(name: String, songIds: [String] = []) async throws {
        try await performAction(.createPlaylist(name: name, songIds: songIds))
        await invalidateCache(for: .getPlaylists)
    }

    func updatePlaylist(id: String, name: String? = nil, comment: String? = nil,
                        isPublic: Bool? = nil, songIdsToAdd: [String] = [],
                        songIndexesToRemove: [Int] = []) async throws {
        try await performAction(.updatePlaylist(id: id, name: name, comment: comment,
                                                isPublic: isPublic, songIdsToAdd: songIdsToAdd,
                                                songIndexesToRemove: songIndexesToRemove))
    }

    func deletePlaylist(id: String) async throws {
        try await performAction(.deletePlaylist(id: id))
        await invalidateCache(for: .getPlaylists)
    }

    func getLyrics(songId: String) async throws -> LyricsList? {
        let body = try await request(.getLyricsBySongId(id: songId))
        return body.lyricsList
    }

    func getRadioStations() async throws -> [InternetRadioStation] {
        let body = try await request(.getInternetRadioStations)
        return body.internetRadioStations?.internetRadioStation ?? []
    }

    func createRadioStation(streamUrl: String, name: String, homepageUrl: String? = nil) async throws {
        try await performAction(.createInternetRadioStation(streamUrl: streamUrl, name: name, homepageUrl: homepageUrl))
    }

    func deleteRadioStation(id: String) async throws {
        try await performAction(.deleteInternetRadioStation(id: id))
    }

    func getPlayQueue() async throws -> PlayQueue? {
        let body = try await request(.getPlayQueue)
        return body.playQueue
    }

    func savePlayQueue(ids: [String], current: String? = nil, position: Int? = nil) async throws {
        try await performAction(.savePlayQueue(ids: ids, current: current, position: position))
    }

    func getBookmarks() async throws -> [Bookmark] {
        let body = try await request(.getBookmarks)
        return body.bookmarks?.bookmark ?? []
    }

    func createBookmark(id: String, position: Int, comment: String? = nil) async throws {
        try await performAction(.createBookmark(id: id, position: position, comment: comment))
    }

    func deleteBookmark(id: String) async throws {
        try await performAction(.deleteBookmark(id: id))
    }

    func getArtistInfo(id: String, count: Int = 20) async throws -> ArtistInfo2 {
        let body = try await request(.getArtistInfo2(id: id, count: count))
        return body.artistInfo2 ?? ArtistInfo2(
            similarArtist: nil, biography: nil, musicBrainzId: nil,
            lastFmUrl: nil, smallImageUrl: nil, mediumImageUrl: nil, largeImageUrl: nil
        )
    }

    func getAlbumInfo(id: String) async throws -> AlbumInfo2 {
        let body = try await request(.getAlbumInfo2(id: id))
        return body.albumInfo ?? AlbumInfo2(
            notes: nil, musicBrainzId: nil, lastFmUrl: nil,
            smallImageUrl: nil, mediumImageUrl: nil, largeImageUrl: nil
        )
    }

    func getSimilarSongs(id: String, count: Int = 50) async throws -> [Song] {
        let body = try await request(.getSimilarSongs2(id: id, count: count))
        return body.similarSongs2?.song ?? []
    }

    func getTopSongs(artist: String, count: Int = 50) async throws -> [Song] {
        let body = try await request(.getTopSongs(artist: artist, count: count))
        return body.topSongs?.song ?? []
    }

    func getMusicFolders() async throws -> [MusicFolder] {
        let body = try await request(.getMusicFolders)
        return body.musicFolders?.musicFolder ?? []
    }

    func getIndexes(musicFolderId: String? = nil, ifModifiedSince: Int? = nil) async throws -> IndexesResponse {
        let body = try await request(.getIndexes(musicFolderId: musicFolderId, ifModifiedSince: ifModifiedSince))
        guard let indexes = body.indexes else {
            throw SubsonicError.apiError(code: 70, message: "Indexes not found")
        }
        return indexes
    }

    func getMusicDirectory(id: String) async throws -> MusicDirectory {
        let body = try await request(.getMusicDirectory(id: id))
        guard let directory = body.directory else {
            throw SubsonicError.apiError(code: 70, message: "Directory not found")
        }
        return directory
    }

    // MARK: - Jukebox

    func jukeboxGet() async throws -> JukeboxPlaylist {
        let body = try await request(.jukeboxControl(action: "get"))
        guard let playlist = body.jukeboxPlaylist else {
            throw SubsonicError.apiError(code: 0, message: "Jukebox not available")
        }
        return playlist
    }

    func jukeboxStart() async throws {
        try await performAction(.jukeboxControl(action: "start"))
    }

    func jukeboxStop() async throws {
        try await performAction(.jukeboxControl(action: "stop"))
    }

    func jukeboxSkip(index: Int, offset: Int = 0) async throws {
        try await performAction(.jukeboxControl(action: "skip", index: index, offset: offset))
    }

    func jukeboxAdd(ids: [String]) async throws {
        try await performAction(.jukeboxControl(action: "add", ids: ids))
    }

    func jukeboxClear() async throws {
        try await performAction(.jukeboxControl(action: "clear"))
    }

    func jukeboxRemove(index: Int) async throws {
        try await performAction(.jukeboxControl(action: "remove", index: index))
    }

    func jukeboxShuffle() async throws {
        try await performAction(.jukeboxControl(action: "shuffle"))
    }

    func jukeboxSetGain(_ gain: Float) async throws {
        try await performAction(.jukeboxControl(action: "setGain", gain: gain))
    }

    func jukeboxSet(ids: [String]) async throws {
        try await performAction(.jukeboxControl(action: "set", ids: ids))
    }

    // MARK: - Reconfigure

    func updateCredentials(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        self.auth = SubsonicAuth(username: username, password: password)
        self.isConnected = false
        Task { await clearCache() }
    }
}
