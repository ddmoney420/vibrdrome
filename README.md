# Veydrune

A native iOS/macOS music player for Navidrome servers (Subsonic API compatible).

## Features

- **Library browsing** -- artists, albums, songs, genres, and playlists
- **Full playback controls** -- queue management, shuffle, repeat modes, gapless playback (coming soon)
- **CarPlay support** -- browse, search, and control playback from your car
- **Offline mode** -- download songs and albums for offline listening
- **Internet radio** -- add and play streaming radio stations
- **Synced lyrics display**
- **Audio visualizer** with Metal shaders
- **Bookmarks** -- save and resume positions in long tracks
- **Smart playlists** -- auto-generated playlists based on criteria
- **Scrobbling support**
- **Multi-server support** with per-server Keychain credentials
- **macOS native app** -- NavigationSplitView sidebar, keyboard shortcuts, pop-out player
- **Theming** -- dark/light mode, custom accent colors, Dynamic Type support
- **Accessibility** -- VoiceOver support throughout

## Requirements

- Xcode 16+ (Swift 6.0)
- iOS 17.0+ / macOS 14.0+
- A Navidrome server (or any Subsonic API-compatible server)

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI |
| Persistence | SwiftData |
| Audio | AVPlayer |
| CarPlay | CPTemplate |
| Build System | XcodeGen |
| Image Loading | NukeUI |
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
  Audio/             AudioEngine (AVPlayer), NowPlayingManager, RemoteCommandManager
  Downloads/         Background URLSession download manager
  Networking/        SubsonicClient, auth, models, endpoints
  Persistence/       SwiftData models and controller
Features/            SwiftUI views organized by feature
  Library/           Artist, album, song, and genre browsing
  Player/            Now playing, mini player, lyrics, visualizer
  Playlists/         Playlist management and smart playlists
  Radio/             Internet radio stations
  Search/            Global search
  Settings/          Server config, appearance, playback settings
  Visualizer/        Metal shader-based audio visualizer
  Downloads/         Download management UI
Shared/              Reusable components (TrackRow, AlbumCard, StarButton) and extensions
```

## Contributing

Contributions are welcome. Please run `make lint` before submitting pull requests.

## License

Not yet specified.
