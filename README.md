```
 _   _  _____ __   ________ ______  _   _  _   _  _____
| | | ||  ___|\ \ / /|  _  \| ___ \| | | || \ | ||  ___|
| | | || |__   \ V / | | | || |_/ /| | | ||  \| || |__
| | | ||  __|   \ /  | | | ||    / | | | || . ` ||  __|
\ \_/ /| |___   | |  | |/ / | |\ \ | |_| || |\  || |___
 \___/ \____/   \_/  |___/  \_| \_| \___/ \_| \_/\____/
```

> *A native iOS/macOS music player for Navidrome servers* ♪♫(◕‿◕)♫♪

---

## Features

### Playback (ﾉ◕ヮ◕)ﾉ*:・゚✧
- **Gapless playback** -- AVQueuePlayer with lookahead for seamless transitions
- **Crossfade** -- configurable 0-12s overlap between tracks using dual-player architecture
- **10-band equalizer** -- parametric EQ with presets for downloaded tracks (AVAudioEngine)
- **ReplayGain** -- track/album volume normalization from server metadata
- **Playback speed** -- 0.5x to 2.0x with pitch preservation
- **Sleep timer** -- 15m to 2h or end-of-track with volume fade

### Library
- **Library browsing** -- artists, albums, songs, genres, playlists, and folder hierarchy
- **Artist radio** -- continuous auto-play seeded from any artist or track
- **Smart playlists** -- 6 auto-generated playlist types
- **Search** -- full-text search across artists, albums, and songs
- **Synced lyrics** -- scrolling lyrics with seek-to-line

### Offline & Downloads
- **Offline mode** -- download songs, albums, and entire playlists
- **Offline playlists** -- batch download with full metadata preservation
- **Cache management** -- configurable size limits with LRU eviction (pinned playlists protected)
- **Offline star/scrobble queue** -- actions sync automatically on reconnect

### Platform
- **CarPlay support** -- browse, search, artist radio, and playback controls
- **macOS native app** -- NavigationSplitView sidebar, keyboard shortcuts, pop-out player
- **Internet radio** -- streaming radio stations with HTTP media support
- **Multi-server support** -- per-server Keychain credentials with server switching
- **Audio visualizer** -- Metal shader-based with 6 presets
- **Bookmarks** -- save and resume positions in long tracks

### Customization
- **Theming** -- dark/light/system mode with 10 accent color themes
- **Accessibility** -- VoiceOver support throughout, bold text, reduce motion
- **Scrobbling** -- automatic scrobble submission with offline queuing

---

## Requirements

- Xcode 16+ (Swift 6.0)
- iOS 17.0+ / macOS 14.0+
- A Navidrome server (or any Subsonic API-compatible server)

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI |
| Persistence | SwiftData |
| Audio | AVQueuePlayer (gapless), AVPlayer (crossfade), AVAudioEngine (EQ) |
| CarPlay | CPTemplate |
| Build System | XcodeGen |
| Image Loading | NukeUI (with disk caching) |
| Credentials | KeychainAccess |

## Build Instructions

```bash
# Prerequisites: Xcode 16+, XcodeGen (brew install xcodegen)

# Generate Xcode project
make generate

# Build
make build-ios     # iOS Simulator
make build-macos   # macOS native

# Test
make test

# Lint
make lint
```

## Architecture

```
App/                 App entry, AppState singleton, Theme
CarPlay/             CarPlay scene delegate and template manager
Core/
  Audio/             AudioEngine (3 backends), EQEngine, CrossfadeController,
                     SleepTimer, NowPlayingManager, RemoteCommandManager
  Downloads/         Background URLSession download manager, CacheManager
  Networking/        SubsonicClient, auth, models, endpoints, OfflineActionQueue
  Persistence/       SwiftData models (DownloadedSong, OfflinePlaylist, PendingAction, etc.)
Features/            SwiftUI views organized by feature
  Library/           Artist, album, song, genre, and folder browsing
  Player/            Now playing, mini player, lyrics, visualizer
  Playlists/         Playlist management and smart playlists
  Radio/             Internet radio stations
  Search/            Global search
  Settings/          Server config, appearance, playback, EQ settings
  Visualizer/        Metal shader-based audio visualizer
  Downloads/         Download management UI
Shared/              Reusable components (TrackRow, AlbumCard, StarButton) and extensions
```

### Playback Architecture (⌐■_■)

Three mutually exclusive playback topologies, selected by mode priority:

```
Mode Priority (highest wins):
1. EQ Mode    -- eqEnabled + downloaded  -->  AVAudioEngine + EQ + TimePitch
2. Crossfade  -- crossfadeDuration > 0   -->  Dual AVPlayer with volume ramps
3. Gapless    -- crossfadeDuration == 0  -->  AVQueuePlayer with lookahead
```

`AudioEngine.shared` is the single facade. All UI, CarPlay, and remote commands talk only to AudioEngine -- never to backends directly.

## Contributing

Contributions are welcome. Please run `make lint` before submitting pull requests.

## License

Not yet specified.

✧･ﾟ:*✧･ﾟ:*
