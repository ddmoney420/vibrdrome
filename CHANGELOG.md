# Changelog

All notable changes to Vibrdrome (iOS/macOS) are documented here.

## v1.0.0

### Build 32 — April 9, 2026
- Library: compact inline header with settings gear, folder switcher, and customize in top bar
- Always-visible search bars on Albums, Artists, Genres, Playlists, Favorites, Songs
- Now playing indicator: animated waveform + accent color on currently playing track
- "Playing from" context label: shows Playlist name or Shuffle (not album)
- Swipe actions on tracks: right = Play Next (blue), left = Add to Queue (orange)
- Toolbar drag-to-reorder in Settings (plus show/hide toggles)
- Crossfade audible preview: volume dip when changing crossfade duration
- Playlist public/private toggle with globe icon on shared playlists
- iOS 26 Liquid Glass on mini player, album buttons, Now Playing toolbar
- iOS 26 floating tab bar (.sidebarAdaptable) with iPad sidebar morph
- macOS: keyboard shortcuts (Space, Cmd+arrows, Cmd+P), single-instance prevention
- Discord Rich Presence with real Application ID
- Smart shuffle: avoids consecutive same-artist tracks
- Recently Played section in Queue view
- Mini player long-press context menu
- 15 new tests — 510 unit tests in 37 suites

**TestFlight Notes:**
> Massive feature build: always-visible search, now playing indicator, swipe
> actions, toolbar reorder, iOS 26 glass + floating tab bar, playlist sharing,
> crossfade preview, macOS keyboard shortcuts, Discord RPC. 510 tests.

### Build 31 — April 8, 2026
- Now Playing toolbar: bold white icons, reordered (Visualizer, EQ, AirPlay, Lyrics, Settings), 44pt touch targets
- Customizable Now Playing toolbar in Settings (show/hide each icon)
- Mini player tint reduced (0.35→0.15 opacity) to match system tab bar
- Album detail: Apple Music style action buttons (Shuffle circle, Play pill, Download circle)
- Lossless badge in album metadata for FLAC/ALAC/WAV albums
- Track row: always-visible tappable heart, bigger download icon, inline "..." menu
- Text contrast improved (.tertiary→.secondary) for light mode readability
- 495 unit tests in 34 suites

**TestFlight Notes:**
> Now Playing toolbar redesigned with bold white icons and customizable layout.
> Album detail reworked: Apple Music style buttons, lossless badge, per-track
> hearts and menus. Mini player tint reduced. Text contrast improved.

### Build 30 — April 7, 2026
- Smart shuffle: avoids consecutive same-artist tracks when shuffling
- Recently Played section in Queue view (last 20 played songs)
- Mini player long-press context menu (Go to Album, Go to Artist, Play Next, Start Radio)
- Queue icon moved to heart row for symmetry (heart | stars | queue)
- Bottom toolbar reordered: AirPlay, EQ, Visualizer, Lyrics, Settings
- Search result counts in section headers
- Haptics added to radio, queue, and search taps
- 495 unit tests in 34 suites

**TestFlight Notes:**
> Smart shuffle avoids same-artist repeats. Queue shows recently played history.
> Long-press mini player for quick actions. Haptics throughout.

### Build 29 — April 7, 2026
- Now Playing: back button removed (pull-down to dismiss only)
- Bottom toolbar: 6 bigger icons — Queue, EQ, AirPlay, Visualizer, Lyrics, Settings
- AirPlay button uses native route picker directly in toolbar
- Quick Settings sheet: sleep timer, playback speed, crossfade, download, share
- Three-dot more menu removed from heart row (all actions in Quick Settings)
- Spacing redistributed for better visual balance
- 495 unit tests in 34 suites

**TestFlight Notes:**
> Now Playing toolbar redesigned with 6 larger icons including native AirPlay
> and a new Quick Settings sheet. Back button removed — swipe down to dismiss.

### Build 28 — April 6, 2026
- Now Playing polish: all titles tappable (song→album, artist→artist, album→album)
- Album name restored below artist in Now Playing
- Bigger heart and star icons
- Sleep timer moved into "..." more menu (with speed, AirPlay, share, download)
- Progress slider: small dot thumb instead of system blob
- Volume slider: thin bar without thumb knob
- WiFi/download icon in streaming info
- Bottom toolbar tighter spacing
- Playlist Play button matches Shuffle style
- Reduced gap between album art and song title
- 495 unit tests in 34 suites

**TestFlight Notes:**
> Now Playing UI polish based on user feedback. All titles tappable,
> bigger icons, smaller slider thumbs, sleep timer in more menu,
> tighter spacing throughout.

### Build 27 — April 6, 2026
- Jukebox mode: remote control for server-side audio playback (play/stop/skip/shuffle/volume)
- Jukebox pill in Library and "Play on Jukebox" in song context menus
- Visualizer sync: asymmetric smoothing (fast attack, slow decay) and increased gain for better beat reactivity
- Playlist Play button: fixed icon blending with background
- Now Playing spacing: redistributed with Spacers for even breathing room
- Album art tap: navigates to album detail page
- 495 unit tests in 34 suites

**TestFlight Notes:**
> Jukebox mode — play music through your Navidrome server's speakers.
> Add the Jukebox pill to your Library or long-press any song > Play on Jukebox.
> Visualizer is now much more reactive to beats. Now Playing spacing improved.

### Build 26 — April 5, 2026
- Tap album art in Now Playing to navigate to album detail page (long-press still saves/shares)

**TestFlight Notes:**
> Tap album art to jump to the album page. Long-press still saves or shares artwork.

### Build 25 — April 5, 2026
- Now Playing redesign: heart/stars/sleep on one row, shuffle/repeat flank transport controls, visible volume slider, streaming info (bitrate/format), simplified bottom toolbar with More menu
- Album Detail redesign: full-bleed parallax album art header with shrink/fade on scroll, circular frosted glass action buttons (heart/play/shuffle/more)
- Watch app: album artwork now displayed, auto-reconnect when watch app installs
- Songs view performance: 1 API call instead of 51 per page
- Playlist share button added
- TrackRow download button accessibility identifier

**TestFlight Notes:**
> Major Now Playing and Album Detail UI redesign based on user feedback.
> Now Playing: shuffle/repeat alongside transport, visible volume slider,
> streaming info, simplified toolbar. Album Detail: parallax art header,
> circular action buttons. Watch app now shows album artwork.

### Build 24 — April 5, 2026
- Offline mode fix: downloaded songs now playable and discoverable when offline
- Offline banner tappable — navigates directly to Downloads
- Offline search — searches downloaded songs locally when server unreachable
- Bottom padding fix on 7 views (mini player no longer covers content)

**TestFlight Notes:**
> Offline playback fully fixed — tap the offline banner to browse downloads,
> search works offline against downloaded songs, mini player no longer covers
> list content on any screen.

### Build 22 — April 5, 2026
- ListenBrainz scrobbling: full integration with settings toggle and token input
- Discord Rich Presence (macOS): shows song/artist/album in Discord status
- watchOS companion app: Now Playing with progress, Queue browser, Library access (favorites, playlists, albums), sleep timer, star/shuffle/repeat controls
- Similar Artists section on Artist Detail with horizontal scroll bubbles
- Artist biography display from Last.fm/MusicBrainz (expandable "About" section)
- Mini player swipe gestures: swipe left/right for next/previous with haptics
- Favorites Play All / Shuffle buttons
- Downloads Play All / Shuffle buttons + tap-to-play
- Songs view: infinite scroll (loads all songs), Play All / Shuffle, song count in title
- Queue: total duration in "Up Next" header
- Album Detail: Start Radio, Share, and Download action buttons
- Song sharing in context menus ("🎵 Title — Artist / Album")
- Search API pagination with offset support
- Now Playing fade/scale transition on present
- Accessibility: 35+ identifiers, contrast improved (0.4→0.5), WCAG AA compliant
- Audio clipping fix: EQ pre-gain attenuation prevents boost overflow, ReplayGain cap 2.0→1.5
- AirPlay 2 multi-room verified working (native AVPlayer + AVRoutePickerView)
- 482 unit tests in 33 suites, 0 SwiftLint violations

**TestFlight Notes:**
> ListenBrainz scrobbling, Discord Rich Presence (macOS), watchOS companion app
> with library browsing and playback controls. Similar Artists, artist biography,
> mini player swipe gestures, favorites/downloads play buttons, infinite songs
> scroll, audio clipping fix for AirPlay casting. 482 tests passing.

### Build 21 — March 28, 2026
- Remove Dynamic Island Live Activity (duplicate of system Now Playing, caused double lock screen and zombie notifications)
- CarPlay login: improved Keychain retry with 3 attempts at increasing delays (1s, 2s, 5s)
- CarPlay radio: add DuckDuckGo favicon fallback for stations without Navidrome 0.61 server artwork
- 448 unit tests in 29 suites

**TestFlight Notes:**
> Removed Dynamic Island Live Activity (duplicated system Now Playing),
> improved CarPlay Keychain retry with graduated delays, added DuckDuckGo
> favicon fallback for radio stations. See full list above.

### Build 20 — April 5, 2026
- Mini player redesign: capsule shape with spinning album art and circular progress ring
- Tappable genre badge on Now Playing navigates to genre albums
- Inline download button on every track row
- Smart Playlists pill added to Library
- Playlist and Radio grid/list view toggle
- Widget overhaul: album art blur background, large size, interactive controls
- Dynamic Island Live Activity for now playing
- Smart queue: auto-continues with similar songs when queue ends
- Queue sharing: save current queue as playlist
- Album detail: disc separators for multi-disc albums, Similar Albums carousel
- Artist page: Top Songs section with expand/collapse
- CarPlay artwork on all lists, radio stale art fix
- Text Size picker (Small/Default/Large/Extra Large)
- Offline mode banner when server unreachable
- Long-press album art to save to photos or share
- Toolbar spacing increased, underlines removed
- 451 unit tests, security fixes, performance optimizations

**TestFlight Notes:**
> Mini player redesign with spinning vinyl and progress ring, tappable genre,
> inline download button, Smart Playlists pill, text size picker, CarPlay art
> fixes, toolbar polish. See full list above.

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

**TestFlight Notes:**
> Dynamic Island, smart queue, queue sharing, album/artist polish, download
> indicators, offline banner, playlist/radio grid toggle, widget overhaul.
> See full list above.

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
