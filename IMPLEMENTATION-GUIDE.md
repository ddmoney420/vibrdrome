I notice that `dmoney-player` is already registered as a DuckDNS subdomain. The infrastructure is partially prepared. Now I have everything needed to design the comprehensive implementation plan. Let me compile it.

---

# Veydrune -- Comprehensive Implementation Plan

## Handoff Document for Claude Opus (Mac Development Environment)

---

## Table of Contents

1. Project Setup
2. Core: Subsonic API Client
3. Core: Audio Engine
4. Core: Persistence (SwiftData)
5. Core: Download Manager
6. CarPlay Integration
7. UI: Library Browsing
8. UI: Now Playing
9. UI: Search
10. UI: Playlists
11. UI: Radio
12. UI: Downloads/Offline
13. UI: Settings
14. Mac Support
15. Implementation Order (Sprint Plan)

---

## 0. Infrastructure Context

The target Navidrome server is already running and accessible:

- **Internal URL**: `http://localhost:4533` (local Docker network)
- **External URL**: `https://***REMOVED***` (Caddy reverse proxy with Let's Encrypt)
- **DuckDNS subdomain `dmoney-player`** is already registered (in `docker-compose.yml` line 646) -- this could be used for a future web app or API gateway
- **Subsonic API version**: `1.16.1` with OpenSubsonic extensions
- **Username**: `dmoney`
- **Library size**: ~1,129 tracks / 87 albums, with 53 internet radio stations
- **Navidrome scans hourly** (`ND_SCANSCHEDULE=1h`)
- **Navidrome enables sharing** (`ND_ENABLESHARING=true`)
- **Songs are marked as played ONLY via `/scrobble`** -- never through `/stream` calls

---

## 1. Project Setup

### 1.1 Xcode Project Creation

Create a new Xcode project:

- **Product Name**: Veydrune
- **Team**: Your Apple Developer account
- **Organization Identifier**: `com.veydrune` (or a personal domain)
- **Interface**: SwiftUI
- **Language**: Swift
- **Storage**: SwiftData
- **Platforms**: iOS 17.0+ (for SwiftData), macOS 14.0+
- **Deployment target**: iOS 17.0, macOS 14.0

Use a single Xcode project (not workspace/SPM package initially -- keep it simple).

### 1.2 Capabilities & Entitlements

In Xcode Target > Signing & Capabilities, add:

1. **Background Modes**:
   - Audio, AirPlay, and Picture in Picture
   - Background fetch
   - Background processing
2. **App Groups** (for sharing data between app and potential extensions)
3. **CarPlay** (requires entitlement application -- see 1.4)

In `Veydrune.entitlements`:
```xml
<key>com.apple.developer.carplay-audio</key>
<true/>
<key>aps-environment</key>
<string>development</string>
```

### 1.3 Build Settings

Critical build settings:

- **Generate Info.plist File**: NO (use custom Info.plist for scene manifest)
- **Swift Language Version**: Swift 6
- **Strict Concurrency Checking**: Complete (Swift 6 mode)

In Info.plist, disable auto-generated scene manifest:
```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <true/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>CPTemplateApplicationScene</string>
                <key>UISceneConfigurationName</key>
                <string>CarPlay</string>
                <key>UISceneDelegateClassName</key>
                <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
            </dict>
        </array>
        <key>UIWindowSceneSessionRoleApplication</key>
        <array>
            <dict>
                <key>UISceneClassName</key>
                <string>UIWindowScene</string>
                <key>UISceneConfigurationName</key>
                <string>Phone</string>
            </dict>
        </array>
    </dict>
</dict>
```

### 1.4 CarPlay Entitlement Application

The `com.apple.developer.carplay-audio` entitlement requires:

1. An active Apple Developer Program membership ($99/year)
2. Applying at https://developer.apple.com/contact/carplay/
3. Apple approval (can take 1-4 weeks)
4. Until approved, test using Xcode CarPlay Simulator (no entitlement needed for simulator)

### 1.5 Dependencies (Swift Package Manager)

Add these packages in Xcode > Project > Package Dependencies:

| Package | URL | Purpose |
|---------|-----|---------|
| **Nuke** | `https://github.com/kean/Nuke` | Image loading/caching (album art) |
| **KeychainAccess** | `https://github.com/kishikawakatsumi/KeychainAccess` | Secure credential storage |

Avoid heavy dependencies. Use native frameworks wherever possible:
- **URLSession** (not Alamofire) -- Apple's networking is sufficient
- **SwiftData** (not Core Data or Realm)
- **AVFoundation** (not third-party audio libraries initially)
- **CryptoKit** (for MD5 auth hashing)

### 1.6 Project Directory Structure

```
Veydrune/
|-- Veydrune.swift                      # @main App entry point
|-- Info.plist                          # Scene manifest (CarPlay + iPhone)
|-- Veydrune.entitlements               # CarPlay audio entitlement
|-- Assets.xcassets/                    # App icon, accent colors, images
|-- Preview Content/
|-- App/
|   |-- AppState.swift                  # @Observable global state / DI
|   |-- Theme.swift                     # Colors, fonts, spacing constants
|   |-- VeydruneApp+Scene.swift         # Scene configuration helper
|-- CarPlay/
|   |-- CarPlaySceneDelegate.swift      # CPTemplateApplicationSceneDelegate
|   |-- CarPlayManager.swift            # Build/manage template hierarchy
|   |-- CarPlaySearchHandler.swift      # CPSearchTemplate delegate
|-- Features/
|   |-- Library/
|   |   |-- ArtistsView.swift
|   |   |-- ArtistDetailView.swift
|   |   |-- AlbumsView.swift
|   |   |-- AlbumDetailView.swift
|   |   |-- TracksView.swift
|   |   |-- GenresView.swift
|   |-- Player/
|   |   |-- NowPlayingView.swift        # Full-screen player
|   |   |-- MiniPlayerView.swift        # Persistent mini player bar
|   |   |-- QueueView.swift             # Up next / queue management
|   |   |-- LyricsView.swift            # Synced lyrics overlay
|   |-- Search/
|   |   |-- SearchView.swift
|   |-- Playlists/
|   |   |-- PlaylistsView.swift
|   |   |-- PlaylistDetailView.swift
|   |   |-- PlaylistEditorView.swift
|   |-- Radio/
|   |   |-- RadioStationsView.swift
|   |   |-- RadioPlayerView.swift
|   |-- Downloads/
|   |   |-- DownloadsView.swift
|   |   |-- DownloadProgressView.swift
|   |-- Settings/
|       |-- SettingsView.swift
|       |-- ServerConfigView.swift
|       |-- PlaybackSettingsView.swift
|       |-- ScrobblingSettingsView.swift
|-- Core/
|   |-- Audio/
|   |   |-- AudioEngine.swift           # AVPlayer/AVQueuePlayer wrapper
|   |   |-- AudioSession.swift          # AVAudioSession configuration
|   |   |-- NowPlayingManager.swift     # MPNowPlayingInfoCenter
|   |   |-- RemoteCommandManager.swift  # MPRemoteCommandCenter
|   |   |-- PlaybackQueue.swift         # Queue logic, shuffle, repeat
|   |-- Networking/
|   |   |-- SubsonicClient.swift        # Full Subsonic API client
|   |   |-- SubsonicAuth.swift          # MD5 token auth generation
|   |   |-- SubsonicModels.swift        # Codable response/request types
|   |   |-- SubsonicEndpoints.swift     # Endpoint URL builder
|   |   |-- SubsonicError.swift         # Error types
|   |   |-- ImageLoader.swift           # Cover art caching integration
|   |-- Persistence/
|   |   |-- Models/
|   |   |   |-- CachedArtist.swift      # @Model
|   |   |   |-- CachedAlbum.swift       # @Model
|   |   |   |-- CachedSong.swift        # @Model
|   |   |   |-- CachedPlaylist.swift    # @Model
|   |   |   |-- DownloadedSong.swift    # @Model
|   |   |   |-- PlayHistory.swift       # @Model
|   |   |   |-- ServerConfig.swift      # @Model
|   |   |-- PersistenceController.swift # ModelContainer setup
|   |-- Downloads/
|       |-- DownloadManager.swift       # URLSession background downloads
|       |-- DownloadStore.swift         # Download state tracking
|-- Shared/
    |-- Components/
    |   |-- AlbumArtView.swift          # Reusable cover art component
    |   |-- TrackRow.swift              # Song list row
    |   |-- AlbumCard.swift             # Album grid card
    |   |-- ArtistRow.swift             # Artist list row
    |   |-- StarButton.swift            # Favorite toggle
    |   |-- RatingView.swift            # 5-star rating
    |   |-- LoadingView.swift           # Loading states
    |-- Extensions/
    |   |-- Duration+Formatted.swift
    |   |-- Color+Theme.swift
    |   |-- String+MD5.swift
    |-- Constants.swift                 # App-wide constants
```

---

## 2. Core: Subsonic API Client

This is the most foundational piece. Every feature depends on it.

### 2.1 Authentication (`SubsonicAuth.swift`)

Subsonic uses per-request token auth:

```swift
import Foundation
import CryptoKit

struct SubsonicAuth {
    let username: String
    let password: String
    let clientName = "veydrune"
    let apiVersion = "1.16.1"

    /// Generate a random salt string
    private func generateSalt(length: Int = 12) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    /// Generate MD5 hash of password + salt
    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Build auth query parameters for any request
    func authParameters() -> [URLQueryItem] {
        let salt = generateSalt()
        let token = md5Hash(password + salt)
        return [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: "json"),
        ]
    }
}
```

Important: `CryptoKit.Insecure.MD5` is available on iOS 13+. No third-party MD5 library needed.

### 2.2 Response Models (`SubsonicModels.swift`)

The Subsonic JSON response wraps everything in `subsonic-response`. Here are the core Codable models:

```swift
// Top-level wrapper
struct SubsonicResponse<T: Decodable>: Decodable {
    let subsonicResponse: SubsonicResponseBody<T>

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct SubsonicResponseBody<T: Decodable>: Decodable {
    let status: String          // "ok" or "failed"
    let version: String
    let type: String?           // Server type (e.g., "navidrome")
    let serverVersion: String?
    let openSubsonic: Bool?
    let error: SubsonicAPIError?

    // The actual payload -- decoded dynamically based on T
    // Subsonic uses different keys for different endpoints
}

struct SubsonicAPIError: Decodable {
    let code: Int
    let message: String
}

// ---- Artist/Album/Song Models ----

struct ArtistIndex: Decodable, Identifiable {
    let name: String            // Index letter: "A", "B", "#", etc.
    let artist: [Artist]
    var id: String { name }
}

struct ArtistsResponse: Decodable {
    let index: [ArtistIndex]
    let ignoredArticles: String?    // "The El La"
}

struct Artist: Decodable, Identifiable {
    let id: String
    let name: String
    let coverArt: String?
    let albumCount: Int?
    let starred: String?        // ISO date if starred, nil if not
    let album: [Album]?         // Present in getArtist response
}

struct Album: Decodable, Identifiable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?          // Total seconds
    let year: Int?
    let genre: String?
    let starred: String?
    let created: String?
    let song: [Song]?           // Present in getAlbum response
    let replayGain: ReplayGain? // OpenSubsonic extension
}

struct Song: Decodable, Identifiable {
    let id: String
    let parent: String?
    let title: String
    let album: String?
    let artist: String?
    let albumId: String?
    let artistId: String?
    let track: Int?
    let year: Int?
    let genre: String?
    let coverArt: String?
    let size: Int?              // File size in bytes
    let contentType: String?    // "audio/flac", "audio/mpeg"
    let suffix: String?         // "flac", "mp3"
    let duration: Int?          // Seconds
    let bitRate: Int?           // kbps
    let path: String?
    let discNumber: Int?
    let created: String?
    let starred: String?
    let bpm: Int?               // OpenSubsonic
    let replayGain: ReplayGain? // OpenSubsonic
    let musicBrainzId: String?  // OpenSubsonic
}

struct ReplayGain: Decodable {
    let trackGain: Double?
    let albumGain: Double?
    let trackPeak: Double?
    let albumPeak: Double?
    let baseGain: Double?
}

// ---- Playlist Models ----

struct Playlist: Decodable, Identifiable {
    let id: String
    let name: String
    let songCount: Int?
    let duration: Int?
    let created: String?
    let changed: String?
    let coverArt: String?
    let owner: String?
    let isPublic: Bool?         // "public" in XML, "isPublic" in JSON
    let entry: [Song]?          // Songs when fetching single playlist

    enum CodingKeys: String, CodingKey {
        case id, name, songCount, duration, created, changed
        case coverArt, owner, entry
        case isPublic = "public"
    }
}

// ---- Search Results ----

struct SearchResult3: Decodable {
    let artist: [Artist]?
    let album: [Album]?
    let song: [Song]?
}

// ---- Internet Radio ----

struct InternetRadioStation: Decodable, Identifiable {
    let id: String
    let name: String
    let streamUrl: String
    let homePageUrl: String?
}

// ---- Lyrics (OpenSubsonic) ----

struct LyricsList: Decodable {
    let structuredLyrics: [StructuredLyrics]?
}

struct StructuredLyrics: Decodable {
    let displayArtist: String?
    let displayTitle: String?
    let lang: String
    let synced: Bool
    let offset: Int?            // Milliseconds offset
    let line: [LyricLine]
}

struct LyricLine: Decodable, Identifiable {
    let start: Int?             // Milliseconds (nil for unsynced)
    let value: String
    var id: String { "\(start ?? 0)-\(value)" }
}

// ---- Play Queue ----

struct PlayQueue: Decodable {
    let current: String?        // Currently playing song ID
    let position: Int?          // Position in ms
    let changed: String?
    let changedBy: String?
    let entry: [Song]?
}

// ---- Genres ----

struct Genre: Decodable, Identifiable {
    let songCount: Int
    let albumCount: Int
    let value: String           // Genre name

    var id: String { value }
}

// ---- Bookmarks ----

struct Bookmark: Decodable {
    let position: Int           // Milliseconds
    let username: String
    let comment: String?
    let created: String
    let changed: String
    let entry: Song
}

// ---- Album List Response ----

struct AlbumList2Response: Decodable {
    let album: [Album]?
}
```

### 2.3 Endpoint Builder (`SubsonicEndpoints.swift`)

```swift
enum SubsonicEndpoint {
    case ping
    case getArtists(musicFolderId: String? = nil)
    case getArtist(id: String)
    case getAlbum(id: String)
    case getSong(id: String)
    case search3(query: String, artistCount: Int = 20, albumCount: Int = 20,
                 songCount: Int = 20, artistOffset: Int = 0, albumOffset: Int = 0,
                 songOffset: Int = 0)
    case getAlbumList2(type: AlbumListType, size: Int = 20, offset: Int = 0,
                       fromYear: Int? = nil, toYear: Int? = nil, genre: String? = nil)
    case getRandomSongs(size: Int = 20, genre: String? = nil,
                        fromYear: Int? = nil, toYear: Int? = nil)
    case getStarred2
    case getGenres
    case star(id: String? = nil, albumId: String? = nil, artistId: String? = nil)
    case unstar(id: String? = nil, albumId: String? = nil, artistId: String? = nil)
    case setRating(id: String, rating: Int)  // 0-5
    case scrobble(id: String, time: Int? = nil, submission: Bool = true)
    case getPlaylists
    case getPlaylist(id: String)
    case createPlaylist(name: String, songIds: [String])
    case updatePlaylist(id: String, name: String? = nil, comment: String? = nil,
                       isPublic: Bool? = nil, songIdsToAdd: [String] = [],
                       songIndexesToRemove: [Int] = [])
    case deletePlaylist(id: String)
    case stream(id: String, maxBitRate: Int? = nil, format: String? = nil)
    case download(id: String)
    case getCoverArt(id: String, size: Int? = nil)
    case getLyricsBySongId(id: String)
    case getInternetRadioStations
    case getPlayQueue
    case savePlayQueue(ids: [String], current: String? = nil, position: Int? = nil)
    case getBookmarks
    case createBookmark(id: String, position: Int, comment: String? = nil)
    case deleteBookmark(id: String)

    var path: String {
        switch self {
        case .ping: return "/rest/ping"
        case .getArtists: return "/rest/getArtists"
        case .getArtist: return "/rest/getArtist"
        case .getAlbum: return "/rest/getAlbum"
        case .getSong: return "/rest/getSong"
        case .search3: return "/rest/search3"
        case .getAlbumList2: return "/rest/getAlbumList2"
        case .getRandomSongs: return "/rest/getRandomSongs"
        case .getStarred2: return "/rest/getStarred2"
        case .getGenres: return "/rest/getGenres"
        case .star: return "/rest/star"
        case .unstar: return "/rest/unstar"
        case .setRating: return "/rest/setRating"
        case .scrobble: return "/rest/scrobble"
        case .getPlaylists: return "/rest/getPlaylists"
        case .getPlaylist: return "/rest/getPlaylist"
        case .createPlaylist: return "/rest/createPlaylist"
        case .updatePlaylist: return "/rest/updatePlaylist"
        case .deletePlaylist: return "/rest/deletePlaylist"
        case .stream: return "/rest/stream"
        case .download: return "/rest/download"
        case .getCoverArt: return "/rest/getCoverArt"
        case .getLyricsBySongId: return "/rest/getLyricsBySongId"
        case .getInternetRadioStations: return "/rest/getInternetRadioStations"
        case .getPlayQueue: return "/rest/getPlayQueue"
        case .savePlayQueue: return "/rest/savePlayQueue"
        case .getBookmarks: return "/rest/getBookmarks"
        case .createBookmark: return "/rest/createBookmark"
        case .deleteBookmark: return "/rest/deleteBookmark"
        }
    }

    /// Endpoint-specific query parameters (auth params added by SubsonicClient)
    var queryItems: [URLQueryItem] {
        // Each case returns its specific params
        // (Implementation: large switch mapping each case to its URLQueryItems)
    }
}

enum AlbumListType: String {
    case random, newest, frequent, recent, starred
    case alphabeticalByName, alphabeticalByArtist
    case byYear, byGenre
}
```

### 2.4 API Client (`SubsonicClient.swift`)

```swift
@Observable
final class SubsonicClient {
    private let session: URLSession
    private var auth: SubsonicAuth
    private var baseURL: URL

    var isConnected: Bool = false

    init(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        self.auth = SubsonicAuth(username: username, password: password)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Generic request method
    func request<T: Decodable>(_ endpoint: SubsonicEndpoint) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = auth.authParameters() + endpoint.queryItems

        let (data, response) = try await session.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SubsonicError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoded = try JSONDecoder().decode(SubsonicResponse<T>.self, from: data)

        if decoded.subsonicResponse.status == "failed",
           let error = decoded.subsonicResponse.error {
            throw SubsonicError.apiError(code: error.code, message: error.message)
        }

        // Extract the actual payload from the response body
        // This requires custom decoding logic because Subsonic uses
        // different keys for different response types
        return try extractPayload(from: data, for: endpoint)
    }

    // MARK: - URL builders for streaming (returns URL, not decoded data)
    func streamURL(id: String, maxBitRate: Int? = nil, format: String? = nil) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/rest/stream"),
            resolvingAgainstBaseURL: false)!
        var items = auth.authParameters()
        items.append(URLQueryItem(name: "id", value: id))
        if let maxBitRate { items.append(URLQueryItem(name: "maxBitRate", value: "\(maxBitRate)")) }
        if let format { items.append(URLQueryItem(name: "format", value: format)) }
        components.queryItems = items
        return components.url!
    }

    func coverArtURL(id: String, size: Int? = nil) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/rest/getCoverArt"),
            resolvingAgainstBaseURL: false)!
        var items = auth.authParameters()
        items.append(URLQueryItem(name: "id", value: id))
        if let size { items.append(URLQueryItem(name: "size", value: "\(size)")) }
        components.queryItems = items
        return components.url!
    }

    func downloadURL(id: String) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/rest/download"),
            resolvingAgainstBaseURL: false)!
        var items = auth.authParameters()
        items.append(URLQueryItem(name: "id", value: id))
        components.queryItems = items
        return components.url!
    }

    // MARK: - Convenience methods
    func ping() async throws -> Bool { ... }
    func getArtists() async throws -> [ArtistIndex] { ... }
    func getArtist(id: String) async throws -> Artist { ... }
    func getAlbum(id: String) async throws -> Album { ... }
    func search(query: String, songCount: Int = 40) async throws -> SearchResult3 { ... }
    func getAlbumList(type: AlbumListType, size: Int = 20,
                      offset: Int = 0) async throws -> [Album] { ... }
    func star(id: String) async throws { ... }
    func unstar(id: String) async throws { ... }
    func scrobble(id: String) async throws { ... }
    func getLyrics(songId: String) async throws -> LyricsList? { ... }
    func getRadioStations() async throws -> [InternetRadioStation] { ... }
    // ... etc for all endpoints
}
```

**Important Subsonic JSON decoding quirk**: The response body uses different keys for different data types. For example, `getArtists` returns `{"subsonic-response": {"artists": {"index": [...]}}}` while `getAlbum` returns `{"subsonic-response": {"album": {...}}}`. The decoding strategy needs a custom approach -- either use `AnyCodingKey` dynamic decoding or write endpoint-specific response wrappers.

Recommended approach: Create per-endpoint response wrapper structs:

```swift
struct ArtistsResponseWrapper: Decodable {
    let artists: ArtistsResponse
}

struct AlbumResponseWrapper: Decodable {
    let album: Album
}

struct SearchResult3Wrapper: Decodable {
    let searchResult3: SearchResult3
}
// ... etc
```

Then the generic `request` method can use these wrappers as `T`.

### 2.5 Error Types (`SubsonicError.swift`)

```swift
enum SubsonicError: LocalizedError {
    case httpError(Int)
    case apiError(code: Int, message: String)
    case noServerConfigured
    case decodingError(Error)
    case networkUnavailable
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP error \(code)"
        case .apiError(_, let message): return message
        case .noServerConfigured: return "No server configured"
        case .decodingError(let error): return "Decoding error: \(error.localizedDescription)"
        case .networkUnavailable: return "Network unavailable"
        case .invalidURL: return "Invalid server URL"
        }
    }
}
```

Subsonic API error codes to handle:
- 0: Generic error
- 10: Required parameter missing
- 20: Incompatible client version
- 30: Incompatible server version
- 40: Wrong username or password
- 41: Token auth not supported
- 50: User not authorized
- 60: Trial expired
- 70: Data not found

---

## 3. Core: Audio Engine

### 3.1 Audio Session (`AudioSession.swift`)

```swift
import AVFoundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()

    func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback = audio continues in background, respects silent switch
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // Pause playback
            AudioEngine.shared.pause()
        case .ended:
            guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                AudioEngine.shared.play()
            }
        @unknown default: break
        }
    }

    func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        if reason == .oldDeviceUnavailable {
            // Headphones unplugged -- pause
            AudioEngine.shared.pause()
        }
    }
}
```

### 3.2 Audio Engine (`AudioEngine.swift`)

```swift
import AVFoundation
import MediaPlayer
import Combine

enum RepeatMode {
    case off, all, one
}

@Observable
final class AudioEngine {
    static let shared = AudioEngine()

    // State
    var isPlaying = false
    var currentSong: Song?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isBuffering = false

    // Queue
    private(set) var queue: [Song] = []
    private(set) var currentIndex: Int = 0
    var shuffleEnabled = false
    var repeatMode: RepeatMode = .off

    // Internal
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private let client: SubsonicClient  // Injected

    // MARK: - Playback Control

    func play(song: Song, from queue: [Song]? = nil, at index: Int = 0) {
        if let queue {
            self.queue = queue
            self.currentIndex = index
        }

        currentSong = song
        let url = client.streamURL(id: song.id, format: "raw")  // Original quality
        let item = AVPlayerItem(url: url)
        playerItem = item

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }

        setupTimeObserver()
        setupItemObservers(item)
        player?.play()
        isPlaying = true

        NowPlayingManager.shared.update(song: song, isPlaying: true)

        // Scrobble "now playing"
        Task { try? await client.scrobble(id: song.id, submission: false) }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        NowPlayingManager.shared.updatePlaybackState(isPlaying: false)
    }

    func resume() {
        player?.play()
        isPlaying = true
        NowPlayingManager.shared.updatePlaybackState(isPlaying: true)
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func next() {
        guard !queue.isEmpty else { return }

        // Scrobble current track as "submitted" play
        if let current = currentSong {
            Task { try? await client.scrobble(id: current.id, submission: true) }
        }

        if shuffleEnabled {
            currentIndex = Int.random(in: 0..<queue.count)
        } else {
            currentIndex += 1
            if currentIndex >= queue.count {
                if repeatMode == .all {
                    currentIndex = 0
                } else {
                    pause()
                    return
                }
            }
        }
        play(song: queue[currentIndex])
    }

    func previous() {
        // If >3 seconds in, restart; otherwise go to previous
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        currentIndex = max(0, currentIndex - 1)
        play(song: queue[currentIndex])
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime)
    }

    // MARK: - Queue Management

    func addToQueue(_ song: Song) { queue.append(song) }
    func addToQueueNext(_ song: Song) { queue.insert(song, at: currentIndex + 1) }
    func removeFromQueue(at index: Int) { queue.remove(at: index) }
    func moveInQueue(from: Int, to: Int) { queue.move(fromOffsets: IndexSet(integer: from),
                                                        toOffset: to) }
    func clearQueue() { queue.removeAll() }

    // MARK: - Observers

    private func setupTimeObserver() {
        if let existing = timeObserver { player?.removeTimeObserver(existing) }
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
            NowPlayingManager.shared.updateElapsedTime(time.seconds)
        }
    }

    private func setupItemObservers(_ item: AVPlayerItem) {
        // Duration
        item.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                if dur.isNumeric { self?.duration = dur.seconds }
            }
            .store(in: &cancellables)

        // Buffering state
        item.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] empty in self?.isBuffering = empty }
            .store(in: &cancellables)

        // Track ended
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if self?.repeatMode == .one {
                    self?.seek(to: 0)
                    self?.player?.play()
                } else {
                    self?.next()
                }
            }
            .store(in: &cancellables)
    }
}
```

### 3.3 Now Playing Manager (`NowPlayingManager.swift`)

This updates the system Lock Screen / Control Center / CarPlay Now Playing display.

```swift
import MediaPlayer

final class NowPlayingManager {
    static let shared = NowPlayingManager()
    private let infoCenter = MPNowPlayingInfoCenter.default()

    func update(song: Song, isPlaying: Bool) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artist ?? "Unknown Artist"
        info[MPMediaItemPropertyAlbumTitle] = song.album ?? ""
        info[MPMediaItemPropertyPlaybackDuration] = song.duration ?? 0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        // Load cover art asynchronously
        if let coverArtId = song.coverArt {
            let client = AppState.shared.subsonicClient
            let url = client.coverArtURL(id: coverArtId, size: 600)
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    info[MPMediaItemPropertyArtwork] = artwork
                    await MainActor.run {
                        self.infoCenter.nowPlayingInfo = info
                    }
                }
            }
        }

        infoCenter.nowPlayingInfo = info
    }

    func updateElapsedTime(_ time: TimeInterval) {
        infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
    }

    func updatePlaybackState(isPlaying: Bool) {
        infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    }
}
```

### 3.4 Remote Command Manager (`RemoteCommandManager.swift`)

This is shared between phone, Lock Screen, Control Center, and CarPlay.

```swift
import MediaPlayer

final class RemoteCommandManager {
    static let shared = RemoteCommandManager()
    private let commandCenter = MPRemoteCommandCenter.shared()

    func setup() {
        let engine = AudioEngine.shared

        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            engine.resume()
            return .success
        }

        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            engine.pause()
            return .success
        }

        // Toggle play/pause
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            engine.togglePlayPause()
            return .success
        }

        // Next track
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            engine.next()
            return .success
        }

        // Previous track
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            engine.previous()
            return .success
        }

        // Seek (scrubbing)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            engine.seek(to: event.positionTime)
            return .success
        }

        // Skip forward/backward (15 seconds)
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            engine.seek(to: engine.currentTime + event.interval)
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            engine.seek(to: max(0, engine.currentTime - event.interval))
            return .success
        }

        // Like/dislike (star/unstar) -- these show up as thumbs in CarPlay
        commandCenter.likeCommand.isEnabled = true
        commandCenter.likeCommand.addTarget { _ in
            if let song = engine.currentSong {
                Task { try? await AppState.shared.subsonicClient.star(id: song.id) }
            }
            return .success
        }

        commandCenter.dislikeCommand.isEnabled = true
        commandCenter.dislikeCommand.addTarget { _ in
            if let song = engine.currentSong {
                Task { try? await AppState.shared.subsonicClient.unstar(id: song.id) }
            }
            return .success
        }
    }
}
```

### 3.5 Internet Radio Playback

Radio stations stream from external URLs, not the Subsonic `stream` endpoint. The AudioEngine needs a separate path:

```swift
extension AudioEngine {
    func playRadio(station: InternetRadioStation) {
        guard let url = URL(string: station.streamUrl) else { return }

        currentSong = nil  // Radio is not a song
        let item = AVPlayerItem(url: url)
        playerItem = item

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }

        player?.play()
        isPlaying = true

        // Update Now Playing with station info
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = station.name
        info[MPMediaItemPropertyArtist] = "Internet Radio"
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
```

---

## 4. Core: Persistence (SwiftData)

### 4.1 Model Container Setup (`PersistenceController.swift`)

```swift
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    init() {
        let schema = Schema([
            CachedArtist.self,
            CachedAlbum.self,
            CachedSong.self,
            CachedPlaylist.self,
            DownloadedSong.self,
            PlayHistory.self,
            ServerConfig.self,
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        container = try! ModelContainer(for: schema, configurations: [config])
    }
}
```

### 4.2 SwiftData Models

**CachedSong** (the most important model):

```swift
import SwiftData

@Model
final class CachedSong {
    @Attribute(.unique) var id: String      // Navidrome song ID
    var title: String
    var artist: String?
    var albumName: String?
    var albumId: String?
    var artistId: String?
    var coverArtId: String?
    var track: Int?
    var discNumber: Int?
    var year: Int?
    var genre: String?
    var duration: Int?                       // Seconds
    var bitRate: Int?
    var suffix: String?                      // "flac", "mp3"
    var contentType: String?
    var size: Int?
    var isStarred: Bool = false
    var rating: Int = 0                      // 0-5
    var lastPlayed: Date?
    var playCount: Int = 0
    var cachedAt: Date = Date()

    // Relationships
    @Relationship(inverse: \CachedAlbum.songs) var album: CachedAlbum?
    @Relationship(inverse: \DownloadedSong.song) var download: DownloadedSong?
    @Relationship(inverse: \CachedPlaylist.songs) var playlists: [CachedPlaylist] = []

    init(from song: Song) {
        self.id = song.id
        self.title = song.title
        self.artist = song.artist
        self.albumName = song.album
        self.albumId = song.albumId
        self.artistId = song.artistId
        self.coverArtId = song.coverArt
        self.track = song.track
        self.discNumber = song.discNumber
        self.year = song.year
        self.genre = song.genre
        self.duration = song.duration
        self.bitRate = song.bitRate
        self.suffix = song.suffix
        self.contentType = song.contentType
        self.size = song.size
        self.isStarred = song.starred != nil
    }
}

@Model
final class CachedAlbum {
    @Attribute(.unique) var id: String
    var name: String
    var artistName: String?
    var artistId: String?
    var coverArtId: String?
    var year: Int?
    var genre: String?
    var songCount: Int?
    var duration: Int?
    var isStarred: Bool = false
    var cachedAt: Date = Date()

    var songs: [CachedSong] = []

    init(from album: Album) { ... }
}

@Model
final class CachedArtist {
    @Attribute(.unique) var id: String
    var name: String
    var coverArtId: String?
    var albumCount: Int?
    var isStarred: Bool = false
    var cachedAt: Date = Date()

    init(from artist: Artist) { ... }
}

@Model
final class CachedPlaylist {
    @Attribute(.unique) var id: String
    var name: String
    var songCount: Int?
    var duration: Int?
    var coverArtId: String?
    var owner: String?
    var isPublic: Bool = false
    var cachedAt: Date = Date()

    var songs: [CachedSong] = []

    init(from playlist: Playlist) { ... }
}

@Model
final class DownloadedSong {
    @Attribute(.unique) var songId: String   // Navidrome song ID
    var localFilePath: String                // Relative to app's documents dir
    var fileSize: Int64 = 0
    var downloadedAt: Date = Date()
    var isComplete: Bool = false

    var song: CachedSong?

    init(songId: String, localFilePath: String) {
        self.songId = songId
        self.localFilePath = localFilePath
    }
}

@Model
final class PlayHistory {
    var songId: String
    var songTitle: String
    var artistName: String?
    var playedAt: Date = Date()
    var wasScrobbled: Bool = false

    init(songId: String, songTitle: String, artistName: String?) {
        self.songId = songId
        self.songTitle = songTitle
        self.artistName = artistName
    }
}

@Model
final class ServerConfig {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = "My Server"
    var url: String                          // "https://***REMOVED***"
    var username: String
    // Password stored in Keychain, not SwiftData
    var isActive: Bool = true
    var maxBitRateWifi: Int = 0              // 0 = no limit (original)
    var maxBitRateCellular: Int = 320        // kbps
    var scrobblingEnabled: Bool = true
    var lastConnected: Date?

    init(url: String, username: String) {
        self.url = url
        self.username = username
    }
}
```

### 4.3 Cache Strategy

- **Artists/Albums/Songs**: Cache on first load, refresh on pull-to-refresh or app foreground
- **Cache TTL**: 1 hour soft expiry (show cached data immediately, fetch fresh in background)
- **Cover art**: Use Nuke library's built-in disk cache (up to 500MB configurable)
- **Offline mode detection**: Check network reachability; if offline, serve only from SwiftData + downloaded files

---

## 5. Core: Download Manager

### 5.1 Background Download Architecture

Background downloads MUST use the delegate-based URLSession API (not async/await) because background sessions require a delegate to deliver results even when the app is suspended/terminated.

```swift
import Foundation

final class DownloadManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = DownloadManager()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.veydrune.downloads"
        )
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var activeDownloads: [String: URLSessionDownloadTask] = [:]  // songId: task
    var progressHandler: ((String, Double) -> Void)?  // songId, progress 0-1
    var completionHandler: (() -> Void)?  // For AppDelegate background completion

    // MARK: - Public API

    func download(song: Song, client: SubsonicClient) {
        let url = client.downloadURL(id: song.id)
        let task = session.downloadTask(with: url)
        task.taskDescription = song.id  // Store songId for identification
        activeDownloads[song.id] = task
        task.resume()

        // Create DownloadedSong record (incomplete)
        Task { @MainActor in
            let modelContext = PersistenceController.shared.container.mainContext
            let download = DownloadedSong(songId: song.id,
                                          localFilePath: Self.localPath(for: song))
            modelContext.insert(download)
            try? modelContext.save()
        }
    }

    func cancelDownload(songId: String) {
        activeDownloads[songId]?.cancel()
        activeDownloads.removeValue(forKey: songId)
    }

    static func localPath(for song: Song) -> String {
        // Organize: artist/album/track_title.suffix
        let artist = song.artist?.sanitizedFileName ?? "Unknown"
        let album = song.album?.sanitizedFileName ?? "Unknown"
        let suffix = song.suffix ?? "mp3"
        let filename = "\(song.track ?? 0) - \(song.title.sanitizedFileName).\(suffix)"
        return "\(artist)/\(album)/\(filename)"
    }

    static func absoluteURL(for relativePath: String) -> URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir.appendingPathComponent("Downloads/\(relativePath)")
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let songId = downloadTask.taskDescription else { return }

        // Move from temp to permanent location
        Task { @MainActor in
            let modelContext = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<DownloadedSong>(
                predicate: #Predicate { $0.songId == songId }
            )
            guard let download = try? modelContext.fetch(descriptor).first else { return }

            let destURL = Self.absoluteURL(for: download.localFilePath)

            try? FileManager.default.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.moveItem(at: location, to: destURL)

            download.isComplete = true
            download.fileSize = Int64((try? FileManager.default.attributesOfItem(
                atPath: destURL.path))?[.size] as? Int ?? 0)
            try? modelContext.save()
        }

        activeDownloads.removeValue(forKey: songId)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let songId = downloadTask.taskDescription else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(songId, progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            print("Download failed: \(error)")
            if let songId = task.taskDescription {
                activeDownloads.removeValue(forKey: songId)
            }
        }
    }

    // Required for background session app relaunch
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.completionHandler?()
            self?.completionHandler = nil
        }
    }
}
```

### 5.2 Offline Playback Integration

When the AudioEngine plays a song, check for local download first:

```swift
extension AudioEngine {
    func resolveURL(for song: Song) -> URL {
        // Check if song is downloaded
        let modelContext = PersistenceController.shared.container.mainContext
        let songId = song.id
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
        )
        if let download = try? modelContext.fetch(descriptor).first {
            return DownloadManager.absoluteURL(for: download.localFilePath)
        }
        // Fall back to streaming
        return client.streamURL(id: song.id, format: "raw")
    }
}
```

---

## 6. CarPlay Integration

### 6.1 CarPlay Scene Delegate (`CarPlaySceneDelegate.swift`)

```swift
import CarPlay

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    private var carPlayManager: CarPlayManager?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        self.carPlayManager = CarPlayManager(interfaceController: interfaceController)
        carPlayManager?.setupRootTemplate()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        self.carPlayManager = nil
    }
}
```

### 6.2 CarPlay Manager (`CarPlayManager.swift`)

This builds and manages the entire CarPlay template hierarchy.

```swift
import CarPlay

final class CarPlayManager {
    private let interfaceController: CPInterfaceController
    private let client: SubsonicClient

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        self.client = AppState.shared.subsonicClient
    }

    func setupRootTemplate() {
        // CPTabBarTemplate: max 4 tabs + Now Playing (auto)
        let tabs: [CPTemplate] = [
            makeLibraryTab(),
            makePlaylistsTab(),
            makeRadioTab(),
            makeSearchTab(),
        ]

        let tabBar = CPTabBarTemplate(templates: tabs)
        interfaceController.setRootTemplate(tabBar, animated: false)
    }

    // MARK: - Library Tab

    private func makeLibraryTab() -> CPListTemplate {
        let items = [
            CPListItem(text: "Artists", detailText: nil, image: UIImage(systemName: "music.mic")),
            CPListItem(text: "Albums", detailText: nil, image: UIImage(systemName: "square.stack")),
            CPListItem(text: "Recently Added", detailText: nil, image: UIImage(systemName: "clock")),
            CPListItem(text: "Favorites", detailText: nil, image: UIImage(systemName: "heart.fill")),
            CPListItem(text: "Random", detailText: nil, image: UIImage(systemName: "shuffle")),
        ]

        items[0].handler = { [weak self] _, completion in
            self?.showArtists()
            completion()
        }
        items[1].handler = { [weak self] _, completion in
            self?.showAlbums(type: .alphabeticalByName)
            completion()
        }
        items[2].handler = { [weak self] _, completion in
            self?.showAlbums(type: .newest)
            completion()
        }
        items[3].handler = { [weak self] _, completion in
            self?.showStarred()
            completion()
        }
        items[4].handler = { [weak self] _, completion in
            self?.playRandom()
            completion()
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Library", sections: [section])
        template.tabImage = UIImage(systemName: "music.note.house")
        return template
    }

    // MARK: - Artists drill-down

    private func showArtists() {
        Task {
            let indexes = try await client.getArtists()
            let sections = indexes.map { index in
                let items = index.artist.map { artist in
                    let item = CPListItem(text: artist.name,
                                          detailText: "\(artist.albumCount ?? 0) albums")
                    item.handler = { [weak self] _, completion in
                        self?.showArtistDetail(id: artist.id)
                        completion()
                    }
                    return item
                }
                return CPListSection(items: items, header: index.name, sectionIndexTitle: index.name)
            }
            let template = CPListTemplate(title: "Artists", sections: sections)
            await MainActor.run {
                interfaceController.pushTemplate(template, animated: true)
            }
        }
    }

    private func showArtistDetail(id: String) {
        Task {
            let artist = try await client.getArtist(id: id)
            let items = (artist.album ?? []).map { album in
                let item = CPListItem(text: album.name,
                                      detailText: album.year.map { "\($0)" })
                // Load cover art
                if let coverArtId = album.coverArt {
                    loadImage(id: coverArtId, size: 120) { image in
                        item.setImage(image)
                    }
                }
                item.handler = { [weak self] _, completion in
                    self?.showAlbumDetail(id: album.id)
                    completion()
                }
                return item
            }
            let template = CPListTemplate(title: artist.name,
                                          sections: [CPListSection(items: items)])
            await MainActor.run {
                interfaceController.pushTemplate(template, animated: true)
            }
        }
    }

    private func showAlbumDetail(id: String) {
        Task {
            let album = try await client.getAlbum(id: id)
            guard let songs = album.song else { return }

            let items = songs.map { song in
                let item = CPListItem(text: song.title,
                                      detailText: song.artist ?? album.artist ?? "")
                item.handler = { [weak self] _, completion in
                    AudioEngine.shared.play(song: song, from: songs,
                                            at: songs.firstIndex(where: { $0.id == song.id }) ?? 0)
                    completion()
                }
                item.playingIndicatorLocation = .trailing
                return item
            }

            // "Play All" and "Shuffle" at top
            let playAll = CPListItem(text: "Play All", detailText: "\(songs.count) songs",
                                     image: UIImage(systemName: "play.fill"))
            playAll.handler = { _, completion in
                AudioEngine.shared.play(song: songs[0], from: songs)
                completion()
            }

            let shuffle = CPListItem(text: "Shuffle", detailText: nil,
                                     image: UIImage(systemName: "shuffle"))
            shuffle.handler = { _, completion in
                var shuffled = songs
                shuffled.shuffle()
                AudioEngine.shared.play(song: shuffled[0], from: shuffled)
                completion()
            }

            let sections = [
                CPListSection(items: [playAll, shuffle]),
                CPListSection(items: items, header: album.name),
            ]
            let template = CPListTemplate(title: album.name, sections: sections)
            await MainActor.run {
                interfaceController.pushTemplate(template, animated: true)
            }
        }
    }

    // MARK: - Playlists Tab

    private func makePlaylistsTab() -> CPListTemplate {
        let template = CPListTemplate(title: "Playlists", sections: [])
        template.tabImage = UIImage(systemName: "music.note.list")

        // Load playlists
        Task {
            let playlists = try await client.getPlaylists()
            let items = playlists.map { playlist in
                let item = CPListItem(text: playlist.name,
                                      detailText: "\(playlist.songCount ?? 0) songs")
                item.handler = { [weak self] _, completion in
                    self?.showPlaylistDetail(id: playlist.id)
                    completion()
                }
                return item
            }
            await MainActor.run {
                template.updateSections([CPListSection(items: items)])
            }
        }

        return template
    }

    // MARK: - Radio Tab

    private func makeRadioTab() -> CPListTemplate {
        let template = CPListTemplate(title: "Radio", sections: [])
        template.tabImage = UIImage(systemName: "antenna.radiowaves.left.and.right")

        Task {
            let stations = try await client.getRadioStations()
            let items = stations.map { station in
                let item = CPListItem(text: station.name, detailText: nil,
                                      image: UIImage(systemName: "radio"))
                item.handler = { _, completion in
                    AudioEngine.shared.playRadio(station: station)
                    completion()
                }
                return item
            }
            await MainActor.run {
                template.updateSections([CPListSection(items: items)])
            }
        }

        return template
    }

    // MARK: - Search Tab

    private func makeSearchTab() -> CPTemplate {
        let handler = CarPlaySearchHandler(client: client)
        let template = CPSearchTemplate()
        template.delegate = handler
        template.tabImage = UIImage(systemName: "magnifyingglass")
        return template
    }

    // MARK: - Helpers

    private func loadImage(id: String, size: Int, completion: @escaping (UIImage) -> Void) {
        let url = client.coverArtURL(id: id, size: size)
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                completion(image)
            }
        }
    }
}
```

### 6.3 CarPlay Search Handler (`CarPlaySearchHandler.swift`)

```swift
import CarPlay

final class CarPlaySearchHandler: NSObject, CPSearchTemplateDelegate {
    private let client: SubsonicClient

    init(client: SubsonicClient) {
        self.client = client
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate,
                         updatedSearchText searchText: String,
                         completionHandler: @escaping ([CPListItem]) -> Void) {
        guard searchText.count >= 2 else {
            completionHandler([])
            return
        }

        Task {
            let results = try await client.search(query: searchText, songCount: 10)
            var items: [CPListItem] = []

            // Songs first
            for song in results.song ?? [] {
                let item = CPListItem(text: song.title,
                                      detailText: "\(song.artist ?? "") - \(song.album ?? "")")
                item.handler = { _, completion in
                    AudioEngine.shared.play(song: song, from: results.song)
                    completion()
                }
                items.append(item)
            }

            completionHandler(items)
        }
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate,
                         selectedResult item: CPListItem,
                         completionHandler: @escaping () -> Void) {
        // Item handler already set above
        completionHandler()
    }
}
```

### 6.4 Key CarPlay Constraints

- **Max 4 tabs** in CPTabBarTemplate
- **Max 5 templates** deep in navigation stack (CPInterfaceController enforces this)
- **CPNowPlayingTemplate** appears automatically when audio is playing -- do NOT push it manually
- **Item limits**: CPListTemplate content is limited by `CPListTemplate.maximumItemCount` (varies by car display)
- **No custom views** -- only Apple's template-based UI
- **Keep handlers fast** -- move data fetching to background, call completion handler promptly

---

## 7. UI: Library Browsing

### 7.1 Main Tab Structure (SwiftUI)

The phone app uses a standard TabView:

```swift
@main
struct VeydruneApp: App {
    @State private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .modelContainer(PersistenceController.shared.container)
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                LibraryView()
                    .tabItem { Label("Library", systemImage: "music.note.house") }
                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                PlaylistsView()
                    .tabItem { Label("Playlists", systemImage: "music.note.list") }
                RadioView()
                    .tabItem { Label("Radio", systemImage: "antenna.radiowaves.left.and.right") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gear") }
            }

            // Persistent mini player above tab bar
            if AudioEngine.shared.currentSong != nil {
                MiniPlayerView()
                    .padding(.bottom, 49) // Tab bar height
            }
        }
    }
}
```

### 7.2 Library View

```swift
struct LibraryView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Artists") { ArtistsView() }
                NavigationLink("Albums") { AlbumsView() }
                NavigationLink("Genres") { GenresView() }
                NavigationLink("Favorites") { FavoritesView() }
                NavigationLink("Recently Added") {
                    AlbumsView(listType: .newest)
                }
                NavigationLink("Most Played") {
                    AlbumsView(listType: .frequent)
                }
                NavigationLink("Recently Played") {
                    AlbumsView(listType: .recent)
                }
                NavigationLink("Random") {
                    AlbumsView(listType: .random)
                }
                NavigationLink("Downloads") { DownloadsView() }
            }
            .navigationTitle("Library")
        }
    }
}
```

### 7.3 Artists View

```swift
struct ArtistsView: View {
    @State private var indexes: [ArtistIndex] = []
    @State private var isLoading = true

    var body: some View {
        List {
            ForEach(indexes) { index in
                Section(header: Text(index.name)) {
                    ForEach(index.artist) { artist in
                        NavigationLink {
                            ArtistDetailView(artistId: artist.id)
                        } label: {
                            ArtistRow(artist: artist)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Artists")
        .task { await loadArtists() }
        .refreshable { await loadArtists() }
        .overlay { if isLoading { ProgressView() } }
    }

    private func loadArtists() async {
        isLoading = true
        defer { isLoading = false }
        do {
            indexes = try await AppState.shared.subsonicClient.getArtists()
        } catch {
            print("Failed to load artists: \(error)")
        }
    }
}
```

### 7.4 Album Detail View

```swift
struct AlbumDetailView: View {
    let albumId: String
    @State private var album: Album?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if let album {
                VStack(spacing: 0) {
                    // Header with album art
                    AlbumHeaderView(album: album)

                    // Action buttons
                    HStack(spacing: 20) {
                        Button("Play") {
                            if let songs = album.song, let first = songs.first {
                                AudioEngine.shared.play(song: first, from: songs)
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Shuffle") {
                            if var songs = album.song {
                                songs.shuffle()
                                if let first = songs.first {
                                    AudioEngine.shared.play(song: first, from: songs)
                                }
                            }
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task {
                                if album.starred != nil {
                                    try? await AppState.shared.subsonicClient.unstar(albumId: albumId)
                                } else {
                                    try? await AppState.shared.subsonicClient.star(albumId: albumId)
                                }
                            }
                        } label: {
                            Image(systemName: album.starred != nil ? "heart.fill" : "heart")
                        }

                        Button {
                            // Download album
                            if let songs = album.song {
                                for song in songs {
                                    DownloadManager.shared.download(
                                        song: song,
                                        client: AppState.shared.subsonicClient)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                    .padding()

                    // Song list
                    LazyVStack(spacing: 0) {
                        ForEach(album.song ?? []) { song in
                            TrackRow(song: song, album: album)
                                .onTapGesture {
                                    AudioEngine.shared.play(
                                        song: song,
                                        from: album.song,
                                        at: album.song?.firstIndex(where: { $0.id == song.id }) ?? 0)
                                }
                            Divider()
                        }
                    }
                }
            }
        }
        .navigationTitle(album?.name ?? "Album")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAlbum() }
    }

    private func loadAlbum() async {
        isLoading = true
        defer { isLoading = false }
        album = try? await AppState.shared.subsonicClient.getAlbum(id: albumId)
    }
}
```

---

## 8. UI: Now Playing

### 8.1 Full-Screen Now Playing

```swift
struct NowPlayingView: View {
    @Bindable var engine = AudioEngine.shared
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var lyrics: LyricsList?

    var body: some View {
        VStack(spacing: 24) {
            // Album art (large, centered)
            if let coverArtId = engine.currentSong?.coverArt {
                AsyncImage(url: AppState.shared.subsonicClient
                    .coverArtURL(id: coverArtId, size: 800)) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)
                .padding(.horizontal, 40)
            }

            // Song info
            VStack(spacing: 4) {
                Text(engine.currentSong?.title ?? "Not Playing")
                    .font(.title2).bold().lineLimit(1)
                Text(engine.currentSong?.artist ?? "")
                    .font(.body).foregroundStyle(.secondary).lineLimit(1)
                Text(engine.currentSong?.album ?? "")
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }

            // Progress slider
            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { engine.currentTime },
                    set: { engine.seek(to: $0) }
                ), in: 0...max(engine.duration, 1))

                HStack {
                    Text(formatDuration(engine.currentTime))
                    Spacer()
                    Text("-" + formatDuration(engine.duration - engine.currentTime))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Playback controls
            HStack(spacing: 40) {
                Button { engine.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundColor(engine.shuffleEnabled ? .accentColor : .secondary)
                }

                Button { engine.previous() } label: {
                    Image(systemName: "backward.fill").font(.title2)
                }

                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }

                Button { engine.next() } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }

                Button { engine.cycleRepeatMode() } label: {
                    Image(systemName: engine.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundColor(engine.repeatMode != .off ? .accentColor : .secondary)
                }
            }

            // Bottom toolbar
            HStack(spacing: 40) {
                Button { showLyrics.toggle() } label: {
                    Image(systemName: "text.quote")
                }
                StarButton(songId: engine.currentSong?.id ?? "")
                AirPlayButton()
                Button { showQueue.toggle() } label: {
                    Image(systemName: "list.bullet")
                }
            }
            .padding(.bottom)
        }
        .sheet(isPresented: $showLyrics) {
            if let song = engine.currentSong {
                LyricsView(songId: song.id)
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView()
        }
    }
}
```

### 8.2 AirPlay Button

Use `AVRoutePickerView` wrapped in UIViewRepresentable:

```swift
import AVKit

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .label
        picker.activeTintColor = .systemBlue
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
```

### 8.3 Mini Player

```swift
struct MiniPlayerView: View {
    @Bindable var engine = AudioEngine.shared
    @State private var showNowPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            // Cover art thumbnail
            if let coverArtId = engine.currentSong?.coverArt {
                AsyncImage(url: AppState.shared.subsonicClient
                    .coverArtURL(id: coverArtId, size: 120)) { image in
                    image.resizable()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.currentSong?.title ?? "")
                    .font(.subheadline).bold().lineLimit(1)
                Text(engine.currentSong?.artist ?? "")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }

            Button { engine.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .onTapGesture { showNowPlaying = true }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }
}
```

---

## 9. UI: Search

```swift
struct SearchView: View {
    @State private var query = ""
    @State private var results: SearchResult3?
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                if let results {
                    if let artists = results.artist, !artists.isEmpty {
                        Section("Artists") {
                            ForEach(artists) { artist in
                                NavigationLink {
                                    ArtistDetailView(artistId: artist.id)
                                } label: {
                                    ArtistRow(artist: artist)
                                }
                            }
                        }
                    }

                    if let albums = results.album, !albums.isEmpty {
                        Section("Albums") {
                            ForEach(albums) { album in
                                NavigationLink {
                                    AlbumDetailView(albumId: album.id)
                                } label: {
                                    AlbumCard(album: album)
                                }
                            }
                        }
                    }

                    if let songs = results.song, !songs.isEmpty {
                        Section("Songs") {
                            ForEach(songs) { song in
                                TrackRow(song: song)
                                    .onTapGesture {
                                        AudioEngine.shared.play(
                                            song: song, from: songs)
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Artists, albums, songs...")
            .onChange(of: query) { _, newValue in
                guard newValue.count >= 2 else { results = nil; return }
                Task {
                    isSearching = true
                    defer { isSearching = false }
                    // Debounce: wait 300ms
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    results = try? await AppState.shared.subsonicClient
                        .search(query: newValue)
                }
            }
        }
    }
}
```

---

## 10. UI: Playlists

```swift
struct PlaylistsView: View {
    @State private var playlists: [Playlist] = []
    @State private var showCreateSheet = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List(playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistId: playlist.id)
                } label: {
                    HStack {
                        if let coverArtId = playlist.coverArt {
                            AsyncImage(url: AppState.shared.subsonicClient
                                .coverArtURL(id: coverArtId, size: 120)) { image in
                                image.resizable()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        VStack(alignment: .leading) {
                            Text(playlist.name).font(.headline)
                            Text("\(playlist.songCount ?? 0) songs")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                PlaylistEditorView(mode: .create)
            }
            .task { await loadPlaylists() }
            .refreshable { await loadPlaylists() }
        }
    }

    private func loadPlaylists() async {
        isLoading = true
        defer { isLoading = false }
        playlists = (try? await AppState.shared.subsonicClient.getPlaylists()) ?? []
    }
}
```

---

## 11. UI: Radio

```swift
struct RadioView: View {
    @State private var stations: [InternetRadioStation] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List(stations) { station in
                Button {
                    AudioEngine.shared.playRadio(station: station)
                } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.accentColor)
                            .frame(width: 40)
                        VStack(alignment: .leading) {
                            Text(station.name).font(.headline)
                            if let url = station.homePageUrl {
                                Text(url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        // Show playing indicator if this station is active
                        if isCurrentStation(station) {
                            Image(systemName: "waveform")
                                .foregroundColor(.accentColor)
                                .symbolEffect(.variableColor)
                        }
                    }
                }
            }
            .navigationTitle("Radio")
            .task { await loadStations() }
            .refreshable { await loadStations() }
        }
    }

    private func isCurrentStation(_ station: InternetRadioStation) -> Bool {
        // Check if audio engine is playing this station's stream URL
        AudioEngine.shared.currentRadioStation?.id == station.id
    }

    private func loadStations() async {
        isLoading = true
        defer { isLoading = false }
        stations = (try? await AppState.shared.subsonicClient.getRadioStations()) ?? []
    }
}
```

The user has 53 radio stations configured in Navidrome. This view will display all of them, possibly grouped by genre or alphabetically.

---

## 12. UI: Downloads/Offline

```swift
struct DownloadsView: View {
    @Query private var downloads: [DownloadedSong]

    var body: some View {
        List {
            // Active downloads section
            Section("Downloading") {
                ForEach(downloads.filter { !$0.isComplete }) { download in
                    DownloadProgressRow(download: download)
                }
            }

            // Completed downloads
            Section("Downloaded (\(completedCount) songs)") {
                ForEach(downloads.filter { $0.isComplete }) { download in
                    if let song = download.song {
                        TrackRow(song: song, showDownloadBadge: true)
                            .onTapGesture {
                                // Play from local file
                                AudioEngine.shared.playLocal(download: download)
                            }
                    }
                }
                .onDelete(perform: deleteDownloads)
            }

            // Storage info
            Section {
                HStack {
                    Text("Storage Used")
                    Spacer()
                    Text(formatBytes(totalSize))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Downloads")
    }

    private var completedCount: Int {
        downloads.filter(\.isComplete).count
    }

    private var totalSize: Int64 {
        downloads.filter(\.isComplete).reduce(0) { $0 + $1.fileSize }
    }

    private func deleteDownloads(at offsets: IndexSet) {
        // Delete local files and SwiftData records
    }
}
```

---

## 13. UI: Settings

```swift
struct SettingsView: View {
    @Query private var servers: [ServerConfig]
    @State private var showAddServer = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    ForEach(servers) { server in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(server.name).font(.headline)
                                Text(server.url).font(.caption).foregroundStyle(.secondary)
                                Text("User: \(server.username)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if server.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    Button("Add Server") { showAddServer = true }
                }

                Section("Playback") {
                    Picker("WiFi Quality", selection: $wifiQuality) {
                        Text("Original (FLAC)").tag(0)
                        Text("320 kbps").tag(320)
                        Text("256 kbps").tag(256)
                        Text("192 kbps").tag(192)
                        Text("128 kbps").tag(128)
                    }
                    Picker("Cellular Quality", selection: $cellularQuality) {
                        Text("Original (FLAC)").tag(0)
                        Text("320 kbps").tag(320)
                        Text("256 kbps").tag(256)
                        Text("192 kbps").tag(192)
                        Text("128 kbps").tag(128)
                    }
                    Toggle("Gapless Playback", isOn: $gaplessEnabled)
                    Toggle("ReplayGain", isOn: $replayGainEnabled)
                }

                Section("Scrobbling") {
                    Toggle("Scrobble to Server", isOn: $scrobblingEnabled)
                    Text("Songs are scrobbled after 30 seconds or 50% playback")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Downloads") {
                    Toggle("Download on WiFi Only", isOn: $wifiOnlyDownloads)
                    HStack {
                        Text("Storage Used")
                        Spacer()
                        Text(downloadStorageUsed)
                    }
                    Button("Clear All Downloads", role: .destructive) {
                        // Clear all downloaded files
                    }
                }

                Section("Cache") {
                    HStack {
                        Text("Image Cache")
                        Spacer()
                        Text(imageCacheSize)
                    }
                    Button("Clear Cache") {
                        // Clear Nuke image cache + SwiftData cache
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                    Link("Source Code", destination: URL(string: "https://github.com/...")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

### 13.1 Server Configuration View

```swift
struct ServerConfigView: View {
    @State private var name = ""
    @State private var url = "https://***REMOVED***"
    @State private var username = "dmoney"
    @State private var password = ""
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section("Server Details") {
                TextField("Name", text: $name, prompt: Text("My Server"))
                TextField("URL", text: $url, prompt: Text("https://..."))
                    .textContentType(.URL)
                    .autocapitalization(.none)
                TextField("Username", text: $username)
                    .autocapitalization(.none)
                SecureField("Password", text: $password)
            }

            Section {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(url.isEmpty || username.isEmpty || password.isEmpty)

                if let testResult {
                    Text(testResult)
                        .foregroundColor(testResult.contains("Success") ? .green : .red)
                }
            }

            Section {
                Button("Save") {
                    saveServer()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Add Server")
    }

    private func testConnection() {
        isTesting = true
        Task {
            defer { isTesting = false }
            guard let serverURL = URL(string: url) else {
                testResult = "Invalid URL"
                return
            }
            let client = SubsonicClient(baseURL: serverURL, username: username, password: password)
            do {
                let ok = try await client.ping()
                testResult = ok ? "Success! Connected to server." : "Server responded but ping failed."
            } catch {
                testResult = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func saveServer() {
        // Save to SwiftData + store password in Keychain
        let config = ServerConfig(url: url, username: username)
        config.name = name.isEmpty ? "My Server" : name

        // Store password securely
        let keychain = Keychain(service: "com.veydrune")
        keychain[config.id.uuidString] = password

        let context = PersistenceController.shared.container.mainContext
        context.insert(config)
        try? context.save()
    }
}
```

---

## 14. Mac Support

### 14.1 Approach: Native SwiftUI (Not Catalyst)

Since the app is pure SwiftUI, Mac support comes relatively naturally via macOS destination in Xcode:

1. Add macOS as a destination in the Xcode project
2. Use `#if os(iOS)` / `#if os(macOS)` conditional compilation for platform-specific code
3. CarPlay code is iOS-only (wrap in `#if os(iOS)`)
4. No UIKit dependency in the main views

### 14.2 Mac-Specific Adaptations

```swift
#if os(macOS)
struct MacContentView: View {
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List {
                Section("Library") {
                    NavigationLink("Artists") { ArtistsView() }
                    NavigationLink("Albums") { AlbumsView() }
                    NavigationLink("Genres") { GenresView() }
                }
                Section("Playlists") {
                    PlaylistsSidebarView()
                }
                Section("Radio") {
                    NavigationLink("Stations") { RadioView() }
                }
            }
        } content: {
            // Detail area
            Text("Select something from the sidebar")
        } detail: {
            // Now Playing / secondary detail
            NowPlayingView()
        }
    }
}
#endif
```

### 14.3 Keyboard Shortcuts (Mac)

```swift
.keyboardShortcut(.space, modifiers: [])  // Play/Pause
.keyboardShortcut(.rightArrow, modifiers: .command)  // Next
.keyboardShortcut(.leftArrow, modifiers: .command)  // Previous
.keyboardShortcut("f", modifiers: .command)  // Search
.keyboardShortcut("l", modifiers: .command)  // Lyrics
```

### 14.4 Platform Differences

| Feature | iOS | macOS |
|---------|-----|-------|
| Audio session | AVAudioSession | Not needed (macOS handles it) |
| Remote commands | MPRemoteCommandCenter | MPRemoteCommandCenter (works on Mac too) |
| Now Playing info | MPNowPlayingInfoCenter | MPNowPlayingInfoCenter |
| CarPlay | Yes | N/A |
| Layout | TabView | NavigationSplitView |
| Downloads | URLSession background | URLSession (no background on Mac, but app stays running) |
| Keychain | KeychainAccess | KeychainAccess |

---

## 15. Implementation Order (Sprint Plan)

### Sprint 1: Foundation (Week 1-2)

**Goal**: Xcode project builds, connects to Navidrome, can browse artists/albums.

1. Create Xcode project with all settings from Section 1
2. Implement `SubsonicAuth.swift` (MD5 token auth)
3. Implement `SubsonicModels.swift` (all Codable types)
4. Implement `SubsonicEndpoints.swift` (URL builder)
5. Implement `SubsonicClient.swift` (async networking)
6. Implement `AppState.swift` (global state container)
7. Implement `ServerConfigView.swift` (server setup + Keychain)
8. Implement basic `ArtistsView` and `AlbumDetailView`
9. Test against `https://***REMOVED***`

**Deliverable**: App launches, connects to server, shows artist/album list.

### Sprint 2: Audio Playback (Week 3-4)

**Goal**: Play music, system integration (Lock Screen, Control Center).

1. Implement `AudioSession.swift`
2. Implement `AudioEngine.swift` (AVPlayer-based)
3. Implement `PlaybackQueue.swift` (queue/shuffle/repeat)
4. Implement `NowPlayingManager.swift` (MPNowPlayingInfoCenter)
5. Implement `RemoteCommandManager.swift` (MPRemoteCommandCenter)
6. Implement `NowPlayingView.swift` (full-screen player)
7. Implement `MiniPlayerView.swift` (persistent bar)
8. Implement `QueueView.swift`
9. Add scrobbling (after 30s or 50% play)

**Deliverable**: Full playback with Lock Screen controls, queue management.

### Sprint 3: Library & Search (Week 5-6)

**Goal**: Complete library browsing, search, favorites.

1. Implement `GenresView.swift`
2. Implement `AlbumsView.swift` with getAlbumList2 types (newest/random/frequent/etc.)
3. Implement `SearchView.swift` with debounced search3
4. Implement star/unstar across all views
5. Implement `FavoritesView.swift` (getStarred2)
6. Implement `RatingView.swift` (setRating)
7. Add context menus (add to queue, add to playlist, star, download)
8. Implement `TrackRow.swift` and `AlbumCard.swift` components

**Deliverable**: Full library browsing, search, starring, rating.

### Sprint 4: Playlists & Radio (Week 7-8)

**Goal**: Full playlist CRUD, internet radio.

1. Implement `PlaylistsView.swift`
2. Implement `PlaylistDetailView.swift` with song list
3. Implement `PlaylistEditorView.swift` (create/edit)
4. Implement playlist reordering (updatePlaylist)
5. Implement `RadioView.swift` with all 53 stations
6. Implement radio playback in AudioEngine
7. Implement play queue save/restore (savePlayQueue/getPlayQueue)

**Deliverable**: Full playlist management, radio station playback.

### Sprint 5: Lyrics & Persistence (Week 9-10)

**Goal**: Synced lyrics, offline cache, SwiftData models.

1. Implement `LyricsView.swift` with synced lyrics scrolling
2. Implement getLyricsBySongId API call
3. Implement SwiftData models (CachedSong, CachedAlbum, etc.)
4. Implement cache layer (fetch from network, persist to SwiftData)
5. Implement image caching with Nuke
6. Implement `PlayHistory.swift` model and recent plays view
7. Add pull-to-refresh across all views

**Deliverable**: Synced lyrics, persistent cache, play history.

### Sprint 6: Downloads & Offline (Week 11-12)

**Goal**: Background downloads, offline playback.

1. Implement `DownloadManager.swift` (URLSession background)
2. Implement `DownloadedSong.swift` model
3. Implement `DownloadsView.swift` with progress tracking
4. Implement download button on album/song views
5. Implement offline playback (local file resolution in AudioEngine)
6. Implement bulk download (album/playlist download)
7. Implement download cleanup / storage management

**Deliverable**: Download songs for offline, play without network.

### Sprint 7: CarPlay (Week 13-14)

**Goal**: Full CarPlay support.

1. Implement `CarPlaySceneDelegate.swift`
2. Implement `CarPlayManager.swift` with 4-tab hierarchy
3. Implement artist/album drill-down (max 5 levels)
4. Implement `CarPlaySearchHandler.swift`
5. Implement radio tab in CarPlay
6. Implement playlists tab in CarPlay
7. Test in CarPlay Simulator
8. Apply for CarPlay entitlement from Apple

**Deliverable**: Complete CarPlay experience with browsing, search, radio.

### Sprint 8: Mac & Polish (Week 15-16)

**Goal**: macOS support, UI refinements.

1. Add macOS destination, fix compilation errors
2. Implement `MacContentView.swift` (NavigationSplitView)
3. Add keyboard shortcuts
4. Implement `Theme.swift` (dark/light, accent colors)
5. Add error handling / retry UI across all views
6. Implement settings (playback quality, WiFi/cellular bitrate)
7. Performance optimization (image cache tuning, pagination)
8. Add app icon and launch screen
9. Implement bookmarks (createBookmark/getBookmarks) for resume

**Deliverable**: Polished Mac + iOS app ready for TestFlight.

---

## Key Architectural Decisions

1. **AVPlayer over AudioStreaming library**: AVPlayer is simpler, no third-party dependency, and sufficient for streaming from Subsonic endpoints. Revisit only if gapless becomes critical (AVQueuePlayer can help).

2. **SwiftData over Core Data**: SwiftData is declarative, works natively with SwiftUI, requires less boilerplate. Minimum iOS 17 is acceptable for a new app in 2026.

3. **No Alamofire**: URLSession with async/await is fully capable. One less dependency.

4. **@Observable over ObservableObject**: Swift 5.9+ `@Observable` macro is cleaner than Combine-based ObservableObject. Fewer `@Published` wrappers, better performance.

5. **Single SubsonicClient instance**: Shared via `AppState`, threadsafe via actor or Sendable. All views access the same authenticated client.

6. **Scrobble strategy**: Scrobble "now playing" (`submission=false`) immediately when a track starts. Scrobble "submitted" (`submission=true`) when the user moves to the next track OR when 50% of the track has been listened to. This matches standard Last.fm behavior and Navidrome's expectations.

7. **Password in Keychain, not SwiftData**: SwiftData/SQLite is not encrypted. Server passwords must be stored in the iOS Keychain (use KeychainAccess library).

8. **Cover art caching**: Use Nuke library for high-performance image loading with disk + memory cache. The Subsonic `getCoverArt` endpoint with size parameter handles server-side resizing.

---

## Appendix: Complete Subsonic API Endpoint Reference

For the developer's reference, here is every endpoint Veydrune will use, with parameters:

| Endpoint | Parameters | Used For |
|----------|-----------|----------|
| `ping` | (auth only) | Connection test |
| `getArtists` | `musicFolderId?` | Library: artist index |
| `getArtist` | `id` (required) | Artist detail + albums |
| `getAlbum` | `id` (required) | Album detail + songs |
| `getSong` | `id` (required) | Single song metadata |
| `search3` | `query`, `artistCount?`, `albumCount?`, `songCount?`, `*Offset?` | Search |
| `getAlbumList2` | `type` (required), `size?`, `offset?`, `fromYear?`, `toYear?`, `genre?` | Browse albums by category |
| `getRandomSongs` | `size?`, `genre?`, `fromYear?`, `toYear?` | Random play |
| `getStarred2` | `musicFolderId?` | Favorites |
| `getGenres` | (none) | Genre list |
| `star` | `id?`, `albumId?`, `artistId?` (multiple) | Add favorite |
| `unstar` | `id?`, `albumId?`, `artistId?` (multiple) | Remove favorite |
| `setRating` | `id`, `rating` (0-5) | Rate song |
| `scrobble` | `id`, `time?`, `submission?` | Track play history |
| `getPlaylists` | `username?` | List playlists |
| `getPlaylist` | `id` (required) | Playlist detail |
| `createPlaylist` | `name`/`playlistId`, `songId[]` | Create playlist |
| `updatePlaylist` | `playlistId`, `name?`, `comment?`, `public?`, `songIdToAdd[]`, `songIndexToRemove[]` | Edit playlist |
| `deletePlaylist` | `id` | Delete playlist |
| `stream` | `id`, `maxBitRate?`, `format?` | Audio streaming |
| `download` | `id` | Original file download |
| `getCoverArt` | `id`, `size?` | Album art |
| `getLyricsBySongId` | `id` | Synced lyrics (OpenSubsonic) |
| `getInternetRadioStations` | (none) | Radio stations |
| `getPlayQueue` | (none) | Restore queue |
| `savePlayQueue` | `id[]`, `current?`, `position?` | Save queue state |
| `getBookmarks` | (none) | Resume positions |
| `createBookmark` | `id`, `position`, `comment?` | Save resume position |
| `deleteBookmark` | `id` | Remove bookmark |

All endpoints require auth params: `u`, `t`, `s`, `v=1.16.1`, `c=veydrune`, `f=json`.

---

### Critical Files for Implementation

List of the 5 most critical files that must be implemented first, as they are dependencies for everything else:

- **`Core/Networking/SubsonicClient.swift`** - The entire app depends on this. Every feature needs API access. Implement this first with ping, getArtists, getAlbum, stream URL builder, and getCoverArt URL builder.
- **`Core/Networking/SubsonicModels.swift`** - All Codable response types (Song, Album, Artist, Playlist, etc.). Must match Navidrome's JSON output exactly. The custom decoding for the `subsonic-response` wrapper is non-trivial.
- **`Core/Audio/AudioEngine.swift`** - AVPlayer wrapper with play/pause/next/previous/seek/queue. This is the second highest dependency -- the Now Playing view, CarPlay, Lock Screen, and every playback trigger depends on it.
- **`App/AppState.swift`** - Global @Observable state container holding the SubsonicClient instance, current server config, and shared state. Every view needs this.
- **`CarPlay/CarPlaySceneDelegate.swift`** - The CarPlay entry point. Must be implemented correctly from the start because the Info.plist scene manifest references it by class name. Getting this wrong breaks both CarPlay and potentially the phone app's scene lifecycle.