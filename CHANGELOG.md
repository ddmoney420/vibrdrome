# Changelog

All notable changes to Vibrdrome (iOS/macOS) are documented here.

## v1.0.0

### Build 19 — April 4, 2026
- Dynamic Island Live Activity: now playing in Dynamic Island and lock screen banner
- Smart queue suggestions: auto-continues with similar songs when queue ends
- Queue sharing: save current queue as playlist from queue menu
- Album detail: disc separators for multi-disc albums, Similar Albums carousel
- Artist page: Top Songs section with expand/collapse before albums list
- Download indicators: green arrow icon on downloaded tracks
- Offline mode banner: orange indicator when server unreachable
- Long-press album art: save to photos or share from Now Playing
- Playlist view: grid/list toggle with toolbar button
- Radio view: grid/list toggle with two-column card layout
- Recently Played carousel: new customizable carousel option
- Widget overhaul: album art blur background, large size with controls, interactive play/pause and skip
- Widget command relay via App Group shared storage
- Security: add NSPhotoLibraryAddUsageDescription, recursion guard on auto-suggest
- Performance: cache download status in TrackRow, fix Live Activity cleanup on stop
- 451 unit tests in 30 suites

### Build 18 — April 3, 2026
- Now Playing redesign: controls toolbar moved above progress bar, actions below
- 5-star ratings with Subsonic setRating API
- Sleep timer countdown visible next to moon icon
- Fade/scale animation on Now Playing open
- Genre artwork thumbnails in genres list
- Decades card layout with album art backgrounds
- Playlist artwork mosaic (2x2 grid for playlists without server artwork)
- Play History screen with today/week/all-time stats, top artists, top albums
- Accessibility audit: identifiers added to 17 views, star rating contrast improved
- Performance: stop unnecessary MPNowPlayingInfoCenter updates, use Nuke cache for dominant color
- 442 unit tests in 27 suites

### Build 17 — April 3, 2026
- Tappable artist/album names on Now Playing (dismiss and navigate to detail)
- Queue context menu on long-press (Play Now, Play Next, Remove)
- Queue swipe-left to remove
- CarPlay credential retry with 1s delay

### Build 16 — April 3, 2026
- Home screen widget (Now Playing, small and medium sizes)
- Siri Shortcuts (Play Favorites, Play Random Mix, Toggle Playback, Skip Track, Artist Radio)
- Mini player background tints with album art dominant color
- Up Next subtitle on mini player
- Haptic feedback on playback controls and star
- Pull to refresh on Library
- Search history (saves on submit, shows recent searches)
- Radio station artwork in mini player and CarPlay

### Build 15 — April 2, 2026
- Fix radio artwork crash (MPMediaItemArtwork closure isolation)

### Build 14 — April 2, 2026
- Navidrome 0.61 radio station artwork (coverArt with ra-{id} workaround)
- Security: switch favicon service from Google to DuckDuckGo
- Security: fix isLocalAddress for full RFC 1918 range
- 392 unit tests, security audit, privacy policy updated

### Build 13 — April 2, 2026
- Fix CarPlay logout when connecting (Keychain accessibility change)

### Build 12 — March 31, 2026
- Allow HTTP connections to non-local servers (DuckDNS, dynamic DNS)
- Security warning shown for HTTP URLs recommending HTTPS

### Build 11 — March 31, 2026
- Fix lock screen showing 15-second skip buttons instead of previous/next track

### Build 10 — March 31, 2026
- Library folder switching for multi-library Navidrome servers
- musicFolderId support added to album list, search, starred, and random songs API calls

### Build 9 — March 31, 2026
- Fix CarPlay crash caused by CPSearchTemplate in tab bar
- Search moved to Library > Search in CarPlay

### Build 8 — March 30, 2026
- Radio station favicons from homepage domain and radio-browser.info
- CarPlay threading improvements (@MainActor on scene delegate and search handler)

### Build 7 — March 30, 2026
- CarPlay audio entitlement enabled

### Build 6 — March 29, 2026
- Customizable Library layout (show/hide/reorder pills and carousels)
- 6 new visualizer presets: Lava Lamp, Starfield, Ripple, Fireflies, Prism, Ocean (18 total)
- Smoother visualizer audio reactivity (reduced FFT gain, lower smoothing factor, lerp interpolation)
- Photosensitivity warning on first visualizer launch with "Don't Show Again" option
- Disable Visualizer toggle in Settings > Accessibility
- Epilepsy notice and prefers-reduced-motion CSS on website

### Build 5 — March 28, 2026
- Fix device rotation dismissing player, visualizer, and lyrics views
- Move fullScreenCover for NowPlayingView to ContentView for rotation stability
- Lift showNowPlaying, showVisualizer, showLyrics state to AppState
- Remove unused Metal shader variable
- Rotation UI tests verifying player/visualizer/lyrics stay open

### Build 4 — March 20, 2026
- Audio-reactive visualizer with FFT spectrum analysis
- 12 Metal shader presets
- Library quick access pills and carousels

### Build 3 — March 19, 2026
- Bug fixes and stability improvements

### Build 2 — March 19, 2026
- Initial feature set

### Build 1 — March 18, 2026
- Initial TestFlight release
