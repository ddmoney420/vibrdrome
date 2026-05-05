import Foundation
import os.log

private let ndLog = Logger(subsystem: "com.vibrdrome.app", category: "NavidromeNative")

// MARK: - Errors

enum NavidromeNativeError: LocalizedError {
    case notNavidrome
    case authFailed(String)
    case httpError(Int)
    case decodingError(Error)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notNavidrome:       return "Server does not appear to be Navidrome"
        case .authFailed(let m):  return "Navidrome authentication failed: \(m)"
        case .httpError(let c):   return "HTTP \(c)"
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        case .invalidURL:         return "Invalid URL"
        }
    }
}

// MARK: - Response models

private struct NDLoginResponse: Decodable {
    let token: String
    let id: String?
}

struct NDSmartPlaylist: Decodable, Sendable {
    let id: String
    let name: String
    let comment: String?
    let rules: NSPCriteria?
    let sync: Bool?
}

// MARK: - Song / Album response models

struct NDSong: Decodable, Sendable {
    let id: String
    let title: String
    let album: String?
    let albumId: String?
    let artist: String?
    let albumArtist: String?
    let artistId: String?
    let albumArtistId: String?
    let trackNumber: Int?
    let discNumber: Int?
    let year: Int?
    let genre: String?
    let size: Int?
    let suffix: String?
    let contentType: String?          // maps to `suffix` mime — not present, use `suffix`
    let duration: Double?
    let bitRate: Int?
    let bitDepth: Int?
    let sampleRate: Int?
    let channels: Int?
    let bpm: Int?
    let comment: String?
    let path: String?
    let compilation: Bool?
    let hasCoverArt: Bool?
    let starred: Bool?
    let starredAt: String?
    let rating: Int?
    let playCount: Int?
    let playDate: String?
    let createdAt: String?
    let mbzRecordingId: String?       // not in ND API directly — use mbzReleaseTrackId
    let mbzReleaseTrackId: String?
    let mbzAlbumId: String?
    let mbzArtistId: String?
    let mbzAlbumArtistId: String?
    let rgTrackGain: Double?
    let rgTrackPeak: Double?
    let rgAlbumGain: Double?
    let rgAlbumPeak: Double?
    let smallImageUrl: String?
    let largeImageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, album, albumId, artist, albumArtist, artistId, albumArtistId
        case trackNumber, discNumber, year, genre, size, suffix, duration
        case bitRate, bitDepth, sampleRate, channels, bpm, comment, path
        case compilation, hasCoverArt, starred, starredAt, rating, playCount, playDate, createdAt
        case mbzReleaseTrackId, mbzAlbumId, mbzArtistId, mbzAlbumArtistId
        case rgTrackGain, rgTrackPeak, rgAlbumGain, rgAlbumPeak
        case smallImageUrl, largeImageUrl
        case contentType
        case mbzRecordingId
    }
}

struct NDAlbum: Decodable, Sendable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let albumArtistId: String?
    let genre: String?
    let year: Int?
    let songCount: Int?
    let duration: Double?
    let size: Int?
    let starred: Bool?
    let starredAt: String?
    let rating: Int?
    let playCount: Int?
    let playDate: String?
    let createdAt: String?
    let compilation: Bool?
    let mbzAlbumId: String?
    let mbzAlbumArtistId: String?
    let mbzReleaseGroupId: String?
    let smallImageUrl: String?
    let largeImageUrl: String?
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case id, name, artist, artistId, albumArtistId, genre, year, songCount, duration, size
        case starred, starredAt, rating, playCount, playDate, createdAt, compilation
        case mbzAlbumId, mbzAlbumArtistId, mbzReleaseGroupId
        case smallImageUrl, largeImageUrl, comment
    }
}

// MARK: - NavidromeNativeClient

/// Thin client for Navidrome's own REST API (`/api/…`), used for smart-playlist
/// create/update/delete with embedded NSP criteria rules.
///
/// Auth flow: POST /auth/login → JWT → X-ND-Authorization: Bearer <token>
/// The JWT is cached in memory until invalidated.
@Observable
@MainActor
final class NavidromeNativeClient {

    private let baseURL: URL
    private let username: String
    private let password: String
    private let session: URLSession

    /// Cached JWT token. Nil until first login; cleared on 401.
    private var token: String?

    var isAvailable: Bool = false

    init(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth

    /// Authenticate and cache the JWT. Throws NavidromeNativeError.authFailed on bad credentials.
    func login() async throws {
        let url = baseURL.appendingPathComponent("auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["username": username, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            throw NavidromeNativeError.authFailed("HTTP \(statusCode)")
        }

        do {
            let decoded = try JSONDecoder().decode(NDLoginResponse.self, from: data)
            token = decoded.token
            isAvailable = true
            ndLog.info("Navidrome native auth OK (user: \(self.username))")
        } catch {
            throw NavidromeNativeError.authFailed("Could not decode login response")
        }
    }

    /// Probe the server to confirm it is Navidrome, and authenticate.
    /// Safe to call repeatedly — returns quickly if already available.
    func probe() async {
        guard !isAvailable else { return }
        do {
            try await login()
        } catch {
            isAvailable = false
            ndLog.info("Navidrome native API not available: \(error.localizedDescription)")
        }
    }

    // MARK: - Playlist CRUD

    /// Create a new smart playlist on the server. Returns the new playlist ID.
    @discardableResult
    func createSmartPlaylist(name: String, comment: String = "", rules: NSPCriteria) async throws -> String {
        let body = buildPlaylistBody(name: name, comment: comment, rules: rules)
        let data = try await nativeRequest(method: "POST", path: "api/playlist", body: body)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw NavidromeNativeError.decodingError(
                NSError(domain: "NavidromeNative", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Missing id in createPlaylist response"])
            )
        }
        ndLog.info("Created smart playlist '\(name)' (id: \(id))")
        return id
    }

    /// Update rules (and optionally name/comment) of an existing playlist.
    func updateSmartPlaylist(id: String, name: String, comment: String = "", rules: NSPCriteria) async throws {
        let body = buildPlaylistBody(name: name, comment: comment, rules: rules)
        _ = try await nativeRequest(method: "PUT", path: "api/playlist/\(id)", body: body)
        ndLog.info("Updated smart playlist '\(name)' (id: \(id))")
    }

    /// Delete a playlist.
    func deletePlaylist(id: String) async throws {
        _ = try await nativeRequest(method: "DELETE", path: "api/playlist/\(id)", body: nil)
        ndLog.info("Deleted playlist id: \(id)")
    }

    /// Fetch all playlists (both smart and regular).
    func getPlaylists() async throws -> [NDSmartPlaylist] {
        let data = try await nativeRequest(method: "GET", path: "api/playlist?_end=500&_start=0", body: nil)
        do {
            return try JSONDecoder().decode([NDSmartPlaylist].self, from: data)
        } catch {
            throw NavidromeNativeError.decodingError(error)
        }
    }

    // MARK: - Song / Album fetch

    /// Fetch a page of songs from the Navidrome native API.
    /// Returns `(items, totalCount)` where totalCount comes from the `x-total-count` header.
    func getSongs(start: Int, end: Int) async throws -> (items: [NDSong], total: Int) {
        let path = "api/song?_start=\(start)&_end=\(end)&_sort=title&_order=ASC"
        let (data, response) = try await nativeRequestWithResponse(method: "GET", path: path, body: nil)
        let total = (response as? HTTPURLResponse)
            .flatMap { $0.value(forHTTPHeaderField: "x-total-count") }
            .flatMap { Int($0) } ?? 0
        do {
            let items = try JSONDecoder().decode([NDSong].self, from: data)
            return (items, total)
        } catch {
            throw NavidromeNativeError.decodingError(error)
        }
    }

    /// Fetch a page of albums from the Navidrome native API.
    func getAlbums(start: Int, end: Int) async throws -> (items: [NDAlbum], total: Int) {
        let path = "api/album?_start=\(start)&_end=\(end)&_sort=name&_order=ASC"
        let (data, response) = try await nativeRequestWithResponse(method: "GET", path: path, body: nil)
        let total = (response as? HTTPURLResponse)
            .flatMap { $0.value(forHTTPHeaderField: "x-total-count") }
            .flatMap { Int($0) } ?? 0
        do {
            let items = try JSONDecoder().decode([NDAlbum].self, from: data)
            return (items, total)
        } catch {
            throw NavidromeNativeError.decodingError(error)
        }
    }

    // MARK: - Private helpers

    private func buildPlaylistBody(name: String, comment: String, rules: NSPCriteria) -> [String: Any] {
        var body: [String: Any] = [
            "name": name,
            "comment": comment,
            "sync": true,
        ]
        if let rulesJSON = rules.toJSON() {
            body["rules"] = rulesJSON
        }
        return body
    }

    private func nativeRequest(method: String, path: String, body: [String: Any]?) async throws -> Data {
        let (data, _) = try await nativeRequestWithResponse(method: method, path: path, body: body)
        return data
    }

    private func nativeRequestWithResponse(method: String, path: String, body: [String: Any]?) async throws -> (Data, URLResponse) {
        // Ensure we have a token
        if token == nil {
            try await login()
        }

        guard let tok = token else {
            throw NavidromeNativeError.authFailed("No token after login")
        }

        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw NavidromeNativeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(tok)", forHTTPHeaderField: "X-ND-Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 401 {
            // Token expired — clear and retry once
            token = nil
            isAvailable = false
            try await login()
            guard let newTok = token else {
                throw NavidromeNativeError.authFailed("Re-login failed")
            }
            request.setValue("Bearer \(newTok)", forHTTPHeaderField: "X-ND-Authorization")
            let (retryData, retryResponse) = try await session.data(for: request)
            let retryStatus = (retryResponse as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(retryStatus) else {
                throw NavidromeNativeError.httpError(retryStatus)
            }
            return (retryData, retryResponse)
        }

        guard (200...299).contains(statusCode) else {
            throw NavidromeNativeError.httpError(statusCode)
        }

        return (data, response)
    }
}
