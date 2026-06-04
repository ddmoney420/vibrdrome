# App Store Metadata -- Vibrdrome

## What's New (v1.0.0 Beta Build 54)

- Internet lyrics: when your server has no lyrics for a track, look them up on LRCLIB (synced when available). Toggle in Settings → Player.
- Lyric timing nudge: shift synced-lyric timing in 0.1s steps when a track runs a little ahead or behind; remembered per song.
- Downloads are now grouped by album, with a Playlists section, instead of one flat list of tracks.
- New "Play Playlist" Shortcuts/Siri action to play a playlist by name.
- Multi-artist tracks now show each credited artist as a tappable link to their page.
- Tracks on Various Artists / compilation albums show their real artist instead of "Various Artists".
- Album editions (e.g. "Deluxe Edition") are shown separately from the album title.
- Richer Get Info: credits, classical works/movements, release dates, moods, disc titles, bit depth, and more.
- Opening Search is smoother with no transition hitch.
- Security: artist external links are restricted to safe http/https schemes and encode artist names strictly (macOS).
- Fixed a crash that could occur when a download finished while the app was in the background.

## What's New (v1.0.0 Beta Build 53)

Build 53 focuses on stability and TestFlight fixes:

- Crash & hang diagnostics (MetricKit): the app records crash, hang, CPU, and disk-write reports from the system and shows them under Settings → Diagnostics, where you can copy a report to send it. Nothing is uploaded automatically.
- The Diagnostics screen is now reachable from Settings.
- Now Playing toolbar icons are visible in light mode over light album art.
- Fixed the Favorites empty-state overlap, mini-player rotation reset when Spinning Art is off, widget cover-art storage, and the Songs view card look.

## App Information

- **App Name:** Vibrdrome
- **Subtitle:** Music Player for Navidrome
- **Category:** Music
- **Secondary Category:** Entertainment
- **Content Rights:** Does not contain third-party content
- **Age Rating:** 4+ (no objectionable content)

## Description

Vibrdrome is a native music player for your Navidrome server. Stream your entire library, download for offline, and enjoy audiophile-grade playback -- all from a fast, beautiful interface built for iOS and macOS.

**Your Music, Your Server**
Connect to any Navidrome or Subsonic-compatible server. Browse by artist, album, genre, folder, or decade. Search your entire collection instantly. Smart caching means screens load instantly after your first visit.

**Audiophile Features**
- Gapless playback for seamless album listening
- Crossfade between tracks with adjustable duration
- 10-band parametric equalizer with custom presets
- ReplayGain with pre-gain and fallback for consistent volume across albums
- Adjustable playback speed (0.5x-2.0x)
- Adaptive bitrate streaming that reacts to your connection

**Smart Playlists & Radio**
- Artist radio and Random Mix built in
- Radio Mix: queue songs similar to the one currently playing
- B-Sides & Obscure, Curated Weekly, decade and genre mixes
- Browse thousands of internet radio stations or add your own stream URLs
- Long-press to delete any custom station

**Offline & Downloads**
Download albums, playlists, and individual tracks. Auto-download favorites. Resume interrupted downloads. Manage storage with configurable cache limits.

**Get Info**
Long-press any song, album, or artist to open a Get Info view with two tabs:
- Overview: cover art, year, duration, bitrate/format, ReplayGain, and links to MusicBrainz and Last.fm
- Raw Metadata: full Subsonic API payload plus Navidrome file tags (rawTags) for deep metadata diving

**Built for Mac**
- Get Info opens as its own window, not a modal
- Navigate menu with Go to Search (Command+K) and Focus Search (Command+F)
- Standalone Mini Player window and dedicated Settings window
- Native menu bar commands for Playback and Navigation

**And More**
- Metal-powered audio visualizer with 18 reactive presets
- Synced lyrics with tap-to-seek, an internet fallback (LRCLIB) when your server has none, and a per-song timing nudge
- Sleep timer with volume fade-out
- CarPlay support for hands-free listening, with genre and radio browsing
- Apple Watch companion for playback control from your wrist
- Home Screen widget and Siri shortcuts
- AirPlay 2 streaming with multi-room support
- Background audio with lock screen and Control Center controls
- Dark mode with customizable accent colors, Liquid Glass toolbar on iOS 26
- ListenBrainz and Last.fm scrobbling with offline queue
- Discord Rich Presence (macOS)

Vibrdrome is free, open source, and contains no ads or tracking.

## Keywords

navidrome,subsonic,music,player,streaming,self-hosted,gapless,offline,equalizer,carplay,watch,lyrics,radio,metadata

## What's New (v1.0.0 Beta Build 52)

- macOS artist detail page redesigned: hero header, expandable biography, customizable external-link row (Last.fm, MusicBrainz, Wikipedia, Google).
- macOS Home page with discovery sections (Quick Actions, Jump Back In, Recently Added, Most Played, Featured Genre, more), individually toggleable.
- Song pre-download: the next track in the queue is fetched in advance for gapless transitions on slow connections. Smart shuffle gets a cached-lookahead redesign.
- CarPlay: Albums alphabet directory now works for any library size and any server sort order; Now Playing button appears immediately on cold launch with a restored queue; deep-navigation crash fixed.
- Library filter UI + adaptive grids on macOS (multi-select genre / label / artist, TriState favorites and downloaded toggles), WebP cover art, multi-genre support.
- SwiftData `#Index` plus new AlbumGenre join table give fast filter and genre queries (requires iOS 18 / macOS 15 minimum).

## What's New (v1.0.0 Beta Build 51)

- Visualizer: Spectrum, Waveform, and Aurora now react to the real frequency content of your audio. Bass shows on the left, treble on the right. Spectrum gains classic peak-hold caps.
- CarPlay: two-letter drill-down for Artists and Albums so large collections are navigable without endless scrolling.
- CarPlay Now Playing no longer auto-pushes on track start, so the list you were browsing stays visible.
- Playback recovery: short call or text interruptions no longer restart the track from 0.
- Get Info Raw tab now handles SwiftData optional and foreignReference metadata styles (previously dropped those rows).

## Support URL

https://github.com/ddmoney420/vibrdrome/issues

## Privacy Policy URL

https://vibrdrome.io/privacy-policy

## Marketing URL (optional)

https://vibrdrome.io

## Screenshots Needed

| Device | Size | Required |
|--------|------|----------|
| iPhone 6.7" (15/16 Pro Max) | 1290 x 2796 | Yes |
| iPhone 6.1" (15/16 Pro) | 1179 x 2556 | Yes |
| iPad Pro 12.9" | 2048 x 2732 | If submitting for iPad |
| Mac | 2880 x 1800 or 1280 x 800 | If submitting for Mac |

**Suggested screenshots (in order):**
1. Library -- home screen with quick access pills and album carousels
2. Now Playing -- full player with album art, controls, progress, Radio Mix in toolbar
3. Get Info -- Overview tab with MusicBrainz/Last.fm links
4. Equalizer -- 10-band EQ with preset selector
5. Playlists -- smart mix or playlist detail
6. Radio -- internet radio stations grid
7. Visualizer -- full-screen audio visualizer
8. Lyrics -- synced lyrics during playback
9. Search -- search results with artists, albums, songs
