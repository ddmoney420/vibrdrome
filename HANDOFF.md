# Vibrdrome - Native Music Player for iOS/CarPlay/Mac

## Handoff Instructions for Claude Opus on Mac

This is a complete handoff document. Two files are provided:

1. **This file** (`HANDOFF.md`) - Architecture overview, key decisions, sprint plan
2. **`IMPLEMENTATION-GUIDE.md`** - Full 2,868-line guide with complete Swift code for every component (SubsonicAuth, SubsonicModels, AudioEngine, CarPlay templates, SwiftUI views, etc.)

**To start**: Create a new Xcode project called "Vibrdrome", then follow Sprint 1 in the Implementation Order section. The IMPLEMENTATION-GUIDE.md has copy-ready Swift code for each file.

**Server to test against**: `https://***REMOVED***` | Username: `dmoney`

---

## Context

Build **Vibrdrome**, a Swift-native music player that connects to Navidrome via the Subsonic/OpenSubsonic API. Replaces Aonsoku and existing Subsonic clients with a purpose-built app featuring CarPlay support, offline downloads, synced lyrics, internet radio, and full library management.

**Target server**: `https://***REMOVED***` (Navidrome, Subsonic API v1.16.1 + OpenSubsonic)
**Username**: `dmoney` | **Library**: ~1,129 tracks, 87 albums, 53 radio stations
**Platforms**: iOS 17+ (iPhone/iPad), CarPlay, macOS 14+ (native SwiftUI)

---

## Architecture Overview

```
[SwiftUI Views (iPhone/iPad/Mac)]     [CarPlay Templates (UIKit)]
              |                                    |
              v                                    v
    [AppState (@Observable) - DI container / shared state]
              |
    +---------+---------+
    |         |         |
    v         v         v
[SubsonicClient]  [AudioEngine]  [DownloadManager]
 (URLSession)    (AVPlayer)     (Background URLSession)
    |                |
    v                v
[Navidrome]    [MPNowPlayingInfoCenter]
               [MPRemoteCommandCenter]
```

Phone and CarPlay are **two separate scenes** sharing the same audio engine and API client.

---

## 1. Project Setup

### Xcode Project
- **Product**: Vibrdrome | **Interface**: SwiftUI | **Storage**: SwiftData
- **Deployment**: iOS 17.0+, macOS 14.0+
- **Swift 6** with strict concurrency

### Capabilities & Entitlements
- Background Modes: Audio/AirPlay/PiP, Background fetch, Background processing
- CarPlay: `com.apple.developer.carplay-audio` (apply at https://developer.apple.com/contact/carplay/)
- App Groups (for future extensions)

### Critical Build Setting
**Generate Info.plist File: NO** - Must manually maintain Info.plist with both scene configs:

```xml
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key><true/>
    <key>UISceneConfigurations</key>
    <dict>
        <key>CPTemplateApplicationSceneSessionRoleApplication</key>
        <array><dict>
            <key>UISceneClassName</key><string>CPTemplateApplicationScene</string>
            <key>UISceneConfigurationName</key><string>CarPlay</string>
            <key>UISceneDelegateClassName</key><string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
        </dict></array>
        <key>UIWindowSceneSessionRoleApplication</key>
        <array><dict>
            <key>UISceneClassName</key><string>UIWindowScene</string>
            <key>UISceneConfigurationName</key><string>Phone</string>
        </dict></array>
    </dict>
</dict>
```

### Dependencies (SPM only)
| Package | Purpose |
|---------|---------|
| **Nuke** (`github.com/kean/Nuke`) | Image loading/caching (album art) |
| **KeychainAccess** (`github.com/kishikawakatsumi/KeychainAccess`) | Secure credential storage |

No Alamofire (URLSession async/await suffices), no third-party audio libs (AVPlayer suffices).

### Project Structure
```
Vibrdrome/
├── Vibrdrome.swift                     # @main App
├── Info.plist                         # Scene manifest (CarPlay + iPhone)
├── Vibrdrome.entitlements
├── Assets.xcassets/
├── App/
│   ├── AppState.swift                 # @Observable global state / DI
│   └── Theme.swift
├── CarPlay/
│   ├── CarPlaySceneDelegate.swift     # CPTemplateApplicationSceneDelegate
│   ├── CarPlayManager.swift           # Template hierarchy builder
│   └── CarPlaySearchHandler.swift     # CPSearchTemplate delegate
├── Features/
│   ├── Library/                       # Artists, Albums, Tracks, Genres, Favorites
│   ├── Player/                        # NowPlaying, MiniPlayer, Queue, Lyrics
│   ├── Search/
│   ├── Playlists/
│   ├── Radio/
│   ├── Downloads/
│   └── Settings/                      # Server config, quality, scrobbling
├── Core/
│   ├── Audio/
│   │   ├── AudioEngine.swift          # AVPlayer wrapper
│   │   ├── AudioSession.swift         # AVAudioSession config
│   │   ├── NowPlayingManager.swift    # MPNowPlayingInfoCenter
│   │   ├── RemoteCommandManager.swift # MPRemoteCommandCenter
│   │   └── PlaybackQueue.swift
│   ├── Networking/
│   │   ├── SubsonicClient.swift       # Full API client
│   │   ├── SubsonicAuth.swift         # MD5 token auth
│   │   ├── SubsonicModels.swift       # All Codable types
│   │   ├── SubsonicEndpoints.swift    # Endpoint enum + URL builder
│   │   └── SubsonicError.swift
│   ├── Persistence/
│   │   ├── Models/                    # SwiftData @Model classes
│   │   └── PersistenceController.swift
│   └── Downloads/
│       ├── DownloadManager.swift      # URLSession background downloads
│       └── DownloadStore.swift
└── Shared/
    ├── Components/                    # AlbumArtView, TrackRow, StarButton, etc.
    ├── Extensions/
    └── Constants.swift
```

---

## 2. Core: Subsonic API Client

### Authentication (SubsonicAuth.swift)
Per-request MD5 token auth using `CryptoKit.Insecure.MD5` (iOS 13+):
```swift
struct SubsonicAuth {
    let username: String
    let password: String
    let clientName = "vibrdrome"
    let apiVersion = "1.16.1"

    func authParameters() -> [URLQueryItem] {
        let salt = String((0..<12).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        let token = Insecure.MD5.hash(data: Data((password + salt).utf8))
            .map { String(format: "%02x", $0) }.joined()
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

### Response Models (SubsonicModels.swift)
JSON wraps everything in `{"subsonic-response": {...}}` with different keys per endpoint. Use per-endpoint wrapper structs:

**Core types**: Artist, Album, Song, Playlist, InternetRadioStation, SearchResult3, LyricsList, StructuredLyrics, LyricLine, PlayQueue, Genre, Bookmark, ReplayGain

**Key Song fields**: id, title, artist, album, albumId, artistId, coverArt, track, year, genre, duration, bitRate, suffix, contentType, size, discNumber, starred, path, bpm, replayGain, musicBrainzId

**OpenSubsonic extras on Song**: replayGain (trackGain/albumGain/trackPeak/albumPeak), bitDepth, samplingRate, musicBrainzId

### Endpoints (SubsonicEndpoints.swift)
Full enum with all endpoints and their parameters - see Appendix for complete list.

### Client (SubsonicClient.swift)
`@Observable` class with generic `request<T>(_ endpoint:) async throws -> T` method. URL builders for streaming (returns URL, not decoded data): `streamURL(id:maxBitRate:format:)`, `coverArtURL(id:size:)`, `downloadURL(id:)`.

**Decoding quirk**: Each endpoint wraps its payload in a different key (`"artists"`, `"album"`, `"searchResult3"`, etc.). Use per-endpoint response wrappers as the generic `T`.

---

## 3. Core: Audio Engine

### AudioSession
- Category `.playback` (continues in background, overrides silent switch)
- Handle interruptions (phone calls -> pause, resume after)
- Handle route changes (headphones unplugged -> pause)

### AudioEngine (@Observable)
- **AVPlayer**-based (not AVQueuePlayer initially - simpler)
- State: `isPlaying`, `currentSong`, `currentTime`, `duration`, `isBuffering`
- Queue: `queue: [Song]`, `currentIndex`, `shuffleEnabled`, `repeatMode` (off/all/one)
- Playback: `play(song:from:at:)`, `pause()`, `resume()`, `next()`, `previous()`, `seek(to:)`
- Queue ops: `addToQueue`, `addToQueueNext`, `removeFromQueue`, `moveInQueue`, `clearQueue`
- Time observer: `addPeriodicTimeObserver` at 0.5s intervals, updates `currentTime` and NowPlayingManager
- Track ended: `.AVPlayerItemDidPlayToEndTime` notification -> `next()` or restart if repeat-one
- **Radio playback**: Separate `playRadio(station:)` method - streams external URL, sets `MPNowPlayingInfoPropertyIsLiveStream = true`
- **Offline resolution**: Check `DownloadedSong` in SwiftData first, fall back to streaming URL

### NowPlayingManager
Updates `MPNowPlayingInfoCenter.default()` with title, artist, album, duration, elapsed time, artwork, playback rate. Cover art loaded async from `getCoverArt` endpoint. **CarPlay reads from this automatically** - no separate CarPlay metadata handling needed.

### RemoteCommandManager
Single set of `MPRemoteCommandCenter` handlers serves phone Lock Screen, Control Center, CarPlay, AirPods, and Bluetooth simultaneously:
- play, pause, togglePlayPause, nextTrack, previousTrack
- changePlaybackPosition (scrubbing), skipForward/Backward (15s)
- likeCommand (-> star), dislikeCommand (-> unstar) - shows thumbs in CarPlay

### Scrobbling Strategy
- `scrobble(id, submission: false)` immediately when track starts ("now playing")
- `scrobble(id, submission: true)` when track completes or user skips after 50%+
- Navidrome only increments play count on `submission=true`

---

## 4. Core: Persistence (SwiftData)

### Models
- **CachedSong** (@Model): id, title, artist, albumName, albumId, artistId, coverArtId, track, discNumber, year, genre, duration, bitRate, suffix, contentType, size, isStarred, rating, lastPlayed, playCount, cachedAt. Relationships: album, download, playlists
- **CachedAlbum** (@Model): id, name, artistName, artistId, coverArtId, year, genre, songCount, duration, isStarred, cachedAt. Has: songs[]
- **CachedArtist** (@Model): id, name, coverArtId, albumCount, isStarred, cachedAt
- **CachedPlaylist** (@Model): id, name, songCount, duration, coverArtId, owner, isPublic, cachedAt. Has: songs[]
- **DownloadedSong** (@Model): songId (unique), localFilePath, fileSize, downloadedAt, isComplete. Has: song
- **PlayHistory** (@Model): songId, songTitle, artistName, playedAt, wasScrobbled
- **ServerConfig** (@Model): id (UUID), name, url, username, isActive, maxBitRateWifi (0=unlimited), maxBitRateCellular (320), scrobblingEnabled, lastConnected. **Password stored in Keychain, NOT SwiftData.**

### Cache Strategy
- Cache on first load, refresh on pull-to-refresh or app foreground
- 1-hour soft TTL: show cached immediately, fetch fresh in background
- Cover art: Nuke disk cache (up to 500MB configurable)
- Offline mode: detect via NWPathMonitor, serve only from SwiftData + downloaded files

---

## 5. Core: Download Manager

**MUST use delegate-based URLSession** (not async/await) for background downloads:

```swift
let config = URLSessionConfiguration.background(withIdentifier: "com.vibrdrome.downloads")
config.isDiscretionary = false  // Start immediately
config.sessionSendsLaunchEvents = true  // Wake app on completion
```

- `download(song:client:)` -> creates `URLSessionDownloadTask` with `taskDescription = songId`
- `urlSession(_:downloadTask:didFinishDownloadingTo:)` -> move from temp to Documents/Downloads/{artist}/{album}/{track}.{ext}
- Progress callback via `didWriteData` delegate
- AppDelegate must handle `application(_:handleEventsForBackgroundURLSession:completionHandler:)` to reconnect
- Bulk download: iterate album/playlist songs, download each

---

## 6. CarPlay Integration

### CarPlaySceneDelegate
Implements `CPTemplateApplicationSceneDelegate`. On `didConnect`: create `CarPlayManager`, call `setupRootTemplate()`. On `didDisconnect`: nil out references (audio keeps playing).

### Template Hierarchy (4 tabs max for audio apps)

```
CPTabBarTemplate (root)
├── Tab 1: Library (CPListTemplate)
│   ├── Artists -> Artist -> Albums -> Album (tracks) [max 5 deep]
│   ├── Albums (newest/alpha/etc.)
│   ├── Recently Added
│   ├── Favorites
│   └── Random (immediate playback)
├── Tab 2: Playlists (CPListTemplate)
│   └── Playlist -> Songs
├── Tab 3: Radio (CPListTemplate)
│   └── 53 stations, tap to stream
├── Tab 4: Search (CPSearchTemplate)
│   └── Results: songs (tap to play)

CPNowPlayingTemplate (singleton, system-managed, auto-appears)
```

### Key Constraints
- Max 4 tabs in CPTabBarTemplate
- Max 5 templates deep in navigation stack
- CPNowPlayingTemplate reads from MPNowPlayingInfoCenter automatically - DO NOT push manually
- No custom views - template-based only
- Handlers must complete quickly - fetch data in background

---

## 7. UI: Phone App (SwiftUI)

### Main Structure
```
TabView {
    LibraryView     -> NavigationStack: Artists, Albums, Genres, Favorites, Recent, Most Played, Random, Downloads
    SearchView      -> .searchable with debounced search3, sections for Artists/Albums/Songs
    PlaylistsView   -> List + create button, drill into playlist detail
    RadioView       -> List of 53 stations, tap to stream, playing indicator
    SettingsView    -> Server config, playback quality, scrobbling, downloads, cache
}

// Persistent MiniPlayerView above tab bar when audio playing
// Full-screen NowPlayingView via fullScreenCover
```

### NowPlayingView
- Large album art (800px), song/artist/album text
- Progress slider with elapsed/remaining
- Controls: shuffle, previous, play/pause (large), next, repeat
- Bottom: lyrics toggle, star, AirPlay picker, queue
- Lyrics sheet: synced from `getLyricsBySongId` with auto-scroll

### AlbumDetailView
- Header with art, action buttons: Play All, Shuffle, Heart, Download
- Track list with tap-to-play, context menus

### Mac Support
- `NavigationSplitView` instead of `TabView`
- `#if os(iOS)` for CarPlay code
- Keyboard shortcuts: Space, Cmd+arrows, Cmd+F, Cmd+L

---

## 8. Implementation Order (Sprint Plan)

### Sprint 1: Foundation
SubsonicAuth -> SubsonicModels -> SubsonicEndpoints -> SubsonicClient -> AppState -> ServerConfigView -> ArtistsView/AlbumDetailView -> test against server

### Sprint 2: Audio Playback
AudioSession -> AudioEngine -> PlaybackQueue -> NowPlayingManager -> RemoteCommandManager -> NowPlayingView -> MiniPlayerView -> QueueView -> scrobbling

### Sprint 3: Library & Search
GenresView -> AlbumsView (all list types) -> SearchView -> star/unstar -> FavoritesView -> RatingView -> context menus -> components

### Sprint 4: Playlists & Radio
PlaylistsView -> PlaylistDetailView -> PlaylistEditorView -> RadioView -> radio playback -> play queue save/restore

### Sprint 5: Lyrics & Persistence
LyricsView (synced) -> SwiftData models -> cache layer -> Nuke image caching -> PlayHistory -> pull-to-refresh

### Sprint 6: Downloads & Offline
DownloadManager -> DownloadedSong -> DownloadsView -> download buttons -> offline playback -> bulk download

### Sprint 7: CarPlay
CarPlaySceneDelegate -> CarPlayManager -> drill-down -> search -> radio tab -> playlists tab -> test in simulator -> apply for entitlement

### Sprint 8: Mac & Polish
macOS destination -> NavigationSplitView -> keyboard shortcuts -> Theme -> error handling -> settings -> app icon -> bookmarks

---

## Appendix: Subsonic API Endpoints

All require auth: `u`, `t`, `s`, `v=1.16.1`, `c=vibrdrome`, `f=json`

| Endpoint | Parameters | Feature |
|----------|-----------|---------|
| `ping` | - | Connection test |
| `getArtists` | `musicFolderId?` | Artist index |
| `getArtist` | `id` | Artist + albums |
| `getAlbum` | `id` | Album + songs |
| `getSong` | `id` | Song metadata |
| `search3` | `query`, `artistCount?`, `albumCount?`, `songCount?`, offsets | Search |
| `getAlbumList2` | `type` (random/newest/frequent/recent/starred/alpha/byYear/byGenre), `size?`, `offset?`, `fromYear?`, `toYear?`, `genre?` | Browse |
| `getRandomSongs` | `size?`, `genre?`, `fromYear?`, `toYear?` | Random |
| `getStarred2` | `musicFolderId?` | Favorites |
| `getGenres` | - | Genre list |
| `star` | `id?`, `albumId?`, `artistId?` | Favorite |
| `unstar` | `id?`, `albumId?`, `artistId?` | Unfavorite |
| `setRating` | `id`, `rating` (0-5) | Rate |
| `scrobble` | `id`, `time?`, `submission?` | Play tracking |
| `getPlaylists` | - | List playlists |
| `getPlaylist` | `id` | Playlist + songs |
| `createPlaylist` | `name`, `songId[]` | Create |
| `updatePlaylist` | `playlistId`, `name?`, `comment?`, `public?`, adds, removes | Edit |
| `deletePlaylist` | `id` | Delete |
| `stream` | `id`, `maxBitRate?`, `format?` | Audio stream |
| `download` | `id` | Original file |
| `getCoverArt` | `id`, `size?` | Album art |
| `getLyricsBySongId` | `id` | Synced lyrics |
| `getInternetRadioStations` | - | Radio |
| `getPlayQueue` / `savePlayQueue` | `id[]`, `current?`, `position?` | Queue persist |
| `getBookmarks` / `createBookmark` / `deleteBookmark` | `id`, `position`, `comment?` | Resume |

### Key Decisions
1. AVPlayer over third-party audio libs
2. SwiftData over Core Data
3. URLSession over Alamofire
4. @Observable over ObservableObject
5. Password in Keychain, NOT SwiftData
6. Nuke for cover art caching

### Prerequisites
- Mac with Xcode 16+
- Apple Developer Program ($99/yr)
- CarPlay entitlement (1-4 week Apple approval; simulator works without it)

### Reference
- **Amperfy** (github.com/BLeeEZ/amperfy) - GPLv3 Swift CarPlay+Subsonic app. Study, don't copy.

### Detailed Code Examples
Full 2,868-line implementation guide with Swift code for every component:
**`docs/vibrdrome/IMPLEMENTATION-GUIDE.md`** (in the Docker workspace)

Copy both files to the Mac project:
```
docs/vibrdrome/HANDOFF.md               <- This file (overview + sprint plan)
docs/vibrdrome/IMPLEMENTATION-GUIDE.md  <- Complete Swift code for all components
```
