```
 _   _  _____ ______ ______ ______ ______  _____ ___  ___ _____
| | | ||_   _|| ___ \| ___ \|  _  \| ___ \|  _  ||  \/  ||  ___|
| | | |  | |  | |_/ /| |_/ /| | | || |_/ /| | | || .  . || |__
| | | |  | |  | ___ \|    / | | | ||    / | | | || |\/| ||  __|
\ \_/ / _| |_ | |_/ /| |\ \ | |/ / | |\ \ \ \_/ /| |  | || |___
 \___/  \___/ \____/ \_| \_||___/  \_| \_| \___/ \_|  |_/\____/
```

> *A native iOS/macOS music player for Navidrome servers* ♪♫(◕‿◕)♫♪

<p align="center">
  <a href="https://vibrdrome.io">Website</a> •
  <a href="https://vibrdrome.io/privacy-policy">Privacy Policy</a> •
  <a href="https://github.com/ddmoney420/vibrdrome/issues">Issues</a>
</p>

```
∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾
```

## ╭─────────────────────────────╮
## │           100% Vibe Coded  ᕙ(⇀‸↼‶)ᕗ            │
## ╰─────────────────────────────╯

This entire project was **vibe coded** — designed, built, and shipped using [Claude Code](https://claude.ai/claude-code) (Anthropic's AI coding agent). Every line of Swift, every SwiftUI view, every audio engine architecture decision, every CI pipeline — all of it.

**What does that mean?**
- A human ([@ddmoney420](https://github.com/ddmoney420)) directed the vision, made decisions, and tested on real devices
- An AI (Claude) wrote the code, debugged the issues, and iterated on the architecture
- The result is a real, functional, App Store-ready music player

We're not hiding it — we're proud of it. This is what vibe coding looks like when you push it to its limits. ✧･ﾟ:*✧･ﾟ:*

**Want to contribute?** We'd love that. This project is open for development — whether you're a human, an AI, or somewhere in between. See [Contributing](#contributing) below.

```
∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾
```

## Features (ﾉ◕ヮ◕)ﾉ*:・゚✧

```
  _____   _____      _      _____   _   _   ____    _____   ____
 |  ___| | ____|    / \    |_   _| | | | | |  _ \  | ____| / ___|
 | |_    |  _|     / _ \     | |   | | | | | |_) | |  _|   \___ \
 |  _|   | |___   / ___ \    | |   | |_| | |  _ <  | |___   ___) |
 |_|     |_____| /_/   \_\   |_|    \___/  |_| \_\ |_____| |____/
```

### Playback ♪～(´ε｀ )
- **Gapless playback** — AVQueuePlayer with lookahead for seamless transitions
- **Crossfade** — configurable 0-12s overlap between tracks using dual-player architecture
- **10-band equalizer** — parametric EQ with presets for downloaded tracks (AVAudioEngine)
- **ReplayGain** — track/album volume normalization from server metadata
- **Playback speed** — 0.5x to 2.0x with pitch preservation
- **Sleep timer** — 15m to 2h or end-of-track with volume fade

### Library ♬♩♪♩
- **Library browsing** — artists, albums, songs, genres, playlists, and folder hierarchy
- **Artist radio** — continuous auto-play seeded from any artist or track
- **Smart playlists** — 6 auto-generated playlist types
- **Search** — full-text search across artists, albums, and songs
- **Synced lyrics** — scrolling lyrics with seek-to-line

### Offline & Downloads (⌐■_■)
- **Offline mode** — download songs, albums, and entire playlists
- **Offline playlists** — batch download with full metadata preservation
- **Cache management** — configurable size limits with LRU eviction (pinned playlists protected)
- **Offline star/scrobble queue** — actions sync automatically on reconnect

### Platform ᕦ(ò_óˇ)ᕤ
- **CarPlay support** — browse, search, artist radio, and playback controls
- **macOS native app** — NavigationSplitView sidebar, keyboard shortcuts, pop-out player
- **Internet radio** — streaming radio stations with HTTP media support
- **Multi-server support** — per-server Keychain credentials with server switching
- **Audio visualizer** — Metal shader-based with 6 presets
- **Bookmarks** — save and resume positions in long tracks

### Customization ─=≡Σ((( つ◕ل͜◕)つ
- **Theming** — dark/light/system mode with 10 accent color themes
- **Accessibility** — VoiceOver support throughout, bold text, reduce motion
- **Scrobbling** — automatic scrobble submission with offline queuing

```
∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾
```

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

### Playback Architecture

Three mutually exclusive playback topologies, selected by mode priority:

```
Mode Priority (highest wins):
1. EQ Mode    — eqEnabled + downloaded  →  AVAudioEngine + EQ + TimePitch
2. Crossfade  — crossfadeDuration > 0   →  Dual AVPlayer with volume ramps
3. Gapless    — crossfadeDuration == 0  →  AVQueuePlayer with lookahead
```

`AudioEngine.shared` is the single facade. All UI, CarPlay, and remote commands talk only to AudioEngine — never to backends directly.

```
∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾
```

## Contributing

```
 __     __  ___   ____    _____      ____    ___    ____    _____   ____
 \ \   / / |_ _| | __ )  | ____|    / ___|  / _ \  |  _ \  | ____| |  _ \
  \ \ / /   | |  |  _ \  |  _|     | |     | | | | | | | | |  _|   | | | |
   \ V /    | |  | |_) | | |___    | |___  | |_| | | |_| | | |___  | |_| |
    \_/    |___| |____/  |_____|    \____|  \___/  |____/  |_____| |____/
```

Contributions are welcome and encouraged! This is a community project — whether you want to fix a bug, add a feature, improve the UI, or just clean up some code, we'd love to have you.

**How to contribute:**

1. Fork the repo
2. Create a feature branch (`git checkout -b my-feature`)
3. Run `make lint` before committing
4. Open a PR with a description of what you changed and why

**Ideas for contributions:**
- New EQ presets
- Additional themes and accent colors
- Playlist import/export
- Widget support
- Localization / translations
- Performance optimizations
- Bug fixes (check [Issues](https://github.com/ddmoney420/vibrdrome/issues))

No contribution is too small. Even fixing a typo helps. ¯\\\_(ツ)\_/¯

## License

This project is licensed under the **GNU General Public License v3.0** — see the [LICENSE](LICENSE) file for details.

You're free to use, modify, and distribute this software. If you distribute modified versions, they must also be open source under GPL-3.0. Your music stays yours, and the code stays open.

```
∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾∿∾
```

<p align="center">
  <i>Built with vibes, shipped with love</i> ✧･ﾟ:*✧･ﾟ:*
  <br><br>
  <a href="https://vibrdrome.io">vibrdrome.io</a>
</p>
