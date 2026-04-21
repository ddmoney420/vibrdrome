# Regression Testing Checklist

Run through this checklist before every TestFlight build. Each item should be verified on a real device.

## Pre-Build (Automated)

- [ ] `swiftlint` — 0 violations
- [ ] Unit tests pass (`xcodebuild test -only-testing:VibrdromeTests`)
- [ ] UI rotation tests pass (`xcodebuild test -only-testing:VibrdromeUITests/RotationTests`)
- [ ] Build succeeds with 0 warnings
- [ ] watchOS build succeeds

## Core Playback

- [ ] Play a song from album detail
- [ ] Pause / resume from Now Playing
- [ ] Next / previous track
- [ ] Seek via progress slider
- [ ] Lock screen controls work (play/pause, next, previous)
- [ ] Audio continues when app is backgrounded
- [ ] Gapless playback (two tracks transition without gap)
- [ ] Crossfade works when enabled in settings
- [ ] Playback rate (speed) changes work
- [ ] Sleep timer "End of Track": after it pauses, pressing play advances to next track
- [ ] Recently Played in Queue shows only songs actually listened to (not unplayed queue entries)
- [ ] Spam-tap play/pause rapidly — no audio glitching or dropouts
- [ ] Spam-tap different track rows rapidly — audio settles on the last-tapped track without churn
- [ ] Now Playing: disable all toolbar items in Settings -> Player -> Controls; bottom row hides entirely (no empty pill)
- [ ] Settings -> Player -> Toolbar Background toggle: off = no pill behind bottom icons; on = pill visible
- [ ] Settings -> Player -> Controls -> Radio Mix toggle on; Now Playing shows the radio tower icon; tapping plays similar songs to current track
- [ ] iPad Radio tab (landscape grid view): long-press any station card -> "Delete Station" menu appears
- [ ] Radio -> Add URL: three labeled sections (Name, Stream URL, Homepage) with explainer footers
- [ ] Settings -> Appearance: Liquid Glass toggle shows subtitle "Tinted pill backgrounds and translucent tab bar..."
- [ ] iPad: with mini player visible, switch keyboard to floating mode; mini player stays pinned at screen bottom
- [ ] macOS: menu bar shows Navigate menu with "Go to Search ⌘K" and "Focus Search ⌘F"; both shortcuts fire without beeping
- [ ] Long-press any song/album/artist -> "Get Info" item; opens sheet (iOS) or window (macOS) with Overview and Raw metadata tabs

## Library & Navigation

- [ ] Library loads with carousels
- [ ] Pull to refresh on Library
- [ ] Search returns results (including fuzzy/acronym search)
- [ ] Recent searches appear (saved on submit, not on keystroke)
- [ ] Search filter chips (Genre, Year, Format) appear and filter results
- [ ] Navigate to artist detail (from search, album, or Now Playing)
- [ ] Navigate to album detail
- [ ] Tap album card in artist detail → opens album detail (no bounce back to artist)
- [ ] Search "beats" in Albums tab returns matches anywhere in the library (e.g. "Beats, Rhymes and Life"), not just loaded pages
- [ ] Genre containing a semicolon (e.g. "Hip Hop; Pop") renders without the semicolon, and tapping loads albums without error
- [ ] Library tab shows Playlists / Artists / Albums / Songs / Genres / Downloaded list + Recently Added carousel
- [ ] Favorites tab has Songs / Albums / Artists segmented picker and grid-list toggle on Albums/Artists
- [ ] Heart button on Album Detail toolbar favorites the album (verify in Favorites tab)
- [ ] Heart button on Artist Detail toolbar favorites the artist (verify in Favorites tab)
- [ ] Artists and Albums toolbar filter menu (All / Favorites / Downloaded) filters the list correctly
- [ ] Genres list shows real album artwork (not AI icons); no flickering when new artwork loads
- [ ] Home tab shows Favorite Albums and Featured Genre carousels when data is available
- [ ] CarPlay genres list shows album art
- [ ] After phone call or Siri-read text, CarPlay playback resumes automatically
- [ ] Artist detail shows biography (About section)
- [ ] Artist detail shows Similar Artists carousel
- [ ] Genre list shows artwork
- [ ] Generations shows decade cards
- [ ] Playlists load (grid and list view toggle)
- [ ] Playlist mosaic shows 2x2 album art grid
- [ ] Playlist context menu: Play, Shuffle, Play Next, Add to Queue, Delete (grid + list)
- [ ] Playlist detail: "More" menu with Play Next and Add to Queue
- [ ] Radio stations load (grid and list view toggle)
- [ ] Library folder switching (if multi-library server)
- [ ] Customizable library (add/remove/reorder pills and carousels)
- [ ] Play History shows stats (today/week/all-time, top artists/albums)
- [ ] Songs view shows count in title, Play All / Shuffle buttons work
- [ ] Favorites view Play All / Shuffle buttons work

## Now Playing

- [ ] Album art displays
- [ ] Tap album art navigates to album detail
- [ ] Fade/scale transition on present
- [ ] Song title tappable (navigates to album)
- [ ] Artist name tappable (navigates to artist)
- [ ] Album name tappable (navigates to album)
- [ ] Heart / 5-star rating on one row (no more menu)
- [ ] Star rating works (tap to rate, tap same to clear)
- [ ] No back button (pull-down to dismiss only)
- [ ] Streaming info shows below progress (WiFi icon + bitrate + format)
- [ ] ReplayGain info shows below streaming info when RG tags present (T: +X.X dB / A: +X.X dB)
- [ ] Progress slider has small dot thumb (not blob)
- [ ] Circular progress ring around play/pause button
- [ ] "Playing from" label shows playlist/shuffle context (not album)
- [ ] Volume slider has no thumb (thin bar)
- [ ] Shuffle / repeat flank transport controls (prev/play/next)
- [ ] Volume slider adjusts playback volume
- [ ] Bottom toolbar: Queue, EQ, AirPlay, Visualizer, Lyrics, Settings (6 icons)
- [ ] AirPlay button opens system route picker
- [ ] Settings gear opens Quick Settings sheet
- [ ] Quick Settings: sleep timer, speed, crossfade, download, share all work
- [ ] Sleep timer: no volume pop on expire (smooth volume fade to silence)
- [ ] Landscape layout: art left, controls right (iPhone and iPad)
- [ ] EQ sheet opens from toolbar
- [ ] Lyrics sheet opens (synced lyrics auto-scroll and tap-to-seek)
- [ ] Lyrics with negative offset don't break sync
- [ ] Visualizer opens (if not disabled)
- [ ] Visualizer does not cause audio stutter on open
- [ ] Queue opens
- [ ] Long-press album art shows save/share options
- [ ] Drag to dismiss works
- [ ] Rotation keeps player open

## Mini Player

- [ ] Shows spinning album art with progress ring
- [ ] Dominant color tint from album art
- [ ] Swipe left to skip next
- [ ] Swipe right to go previous
- [ ] Tap opens full Now Playing
- [ ] Long-press shows context menu (Go to Album, Go to Artist, Play Next, Start Radio)

## Queue

- [ ] Tap to jump to track (plays audio, all other tracks remain visible)
- [ ] Passed-over tracks shown dimmed (50% opacity)
- [ ] After tapped track finishes, next track plays
- [ ] Swipe left to remove
- [ ] Drag to reorder
- [ ] Long-press context menu: full track menu with Remove from Queue
- [ ] Save as Playlist from menu
- [ ] Total duration shows in "Queue" header
- [ ] Recently Played section shows songs that actually played
- [ ] Brief skips (<30s) do not appear in Recently Played
- [ ] Smart shuffle avoids consecutive same-artist tracks
- [ ] Auto-Suggest toggle: when off, playback stops at end of queue

## Swipe Actions

- [ ] Swipe right on track = Play Next (blue)
- [ ] Swipe left on track = Add to Queue (orange)
- [ ] Haptic feedback on both swipe actions

## Context Menus

- [ ] Play / Play Next / Add to Queue
- [ ] Start Radio from song
- [ ] Download
- [ ] Add to Playlist
- [ ] Favorite / Unfavorite
- [ ] Go to Album / Go to Artist
- [ ] Share (sends "Title — Artist" text with vibrdrome:// deep link)
- [ ] Deep link `vibrdrome://song/{id}` opens song

## Album Detail

- [ ] Parallax album art header (shrinks/fades on scroll)
- [ ] Apple Music style buttons: Shuffle (circle), Play (white pill), Download (circle)
- [ ] Lossless badge shows for FLAC/ALAC/WAV albums
- [ ] Per-track tappable heart (empty when not starred, pink when starred)
- [ ] Per-track download icon (bigger, .callout size)
- [ ] Per-track inline "..." menu (Play Next, Add to Queue, Start Radio, Share)
- [ ] Text contrast readable in light mode
- [ ] Tappable artist name in album header navigates to artist page
- [ ] Tapping any part of a song row (title, artist text, whitespace) plays the track — does NOT navigate to artist
- [ ] Long-press on song row shows "Go to Album" and "Go to Artist" in context menu
- [ ] Multi-disc separator shows for multi-disc albums
- [ ] Similar Albums carousel at bottom
- [ ] Album sort: Name, Artist, Year, Recently Added all work
- [ ] Multi-select batch actions (Download All, Add to Playlist, Add to Queue)

## Widget

- [ ] Small widget shows album art and title
- [ ] Medium widget shows controls
- [ ] Large widget shows full layout
- [ ] Widget updates on track change
- [ ] Widget updates on pause/resume

## Jukebox

- [ ] Jukebox pill appears in Library (add via Customize)
- [ ] JukeboxView loads and shows error if jukebox not enabled on server
- [ ] Play/Stop controls work (audio plays from server speakers)
- [ ] Skip next/previous works
- [ ] Gain slider adjusts server volume
- [ ] Shuffle and Clear queue work
- [ ] Tap song in queue skips to it
- [ ] Long-press any song > "Play on Jukebox" adds and starts

## CarPlay

- [ ] App appears on CarPlay dashboard
- [ ] Browse library (Artists, Albums, Favorites, etc.)
- [ ] Discover shows random songs (Library > Discover)
- [ ] Play/pause/skip from CarPlay
- [ ] No logout on CarPlay connect/disconnect
- [ ] Artwork shows on all lists
- [ ] Now Playing template shows current track with progress
- [ ] Shuffle and repeat buttons work in Now Playing
- [ ] Up Next queue shows upcoming tracks
- [ ] Auto-navigates to Now Playing when a track starts
- [ ] State refreshes correctly on CarPlay reconnect

## Radio

- [ ] Play a radio station
- [ ] Station artwork shows (if Navidrome 0.61+)
- [ ] Mini player shows radio artwork
- [ ] Find Stations search works

## Downloads & Offline

- [ ] Download a song
- [ ] Downloaded song shows green arrow indicator
- [ ] Offline banner appears when network disconnected
- [ ] Tap offline banner navigates to Downloads view
- [ ] Downloaded songs play while offline
- [ ] Downloads view Play All / Shuffle buttons work
- [ ] Tap a downloaded song to play from that point
- [ ] Search works offline (finds downloaded songs by title/artist/album)
- [ ] Download concurrency capped at 3 (no more than 3 simultaneous downloads)

## Scrobbling

- [ ] Subsonic scrobbling works (check server play count)
- [ ] ListenBrainz scrobbling (enable toggle, enter token, verify at listenbrainz.org)
- [ ] Last.fm: enter API Key + Shared Secret, then username + password, tap Sign In
- [ ] Last.fm: "Signed in as [username]" appears with green checkmark after auth
- [ ] Last.fm: Sign Out clears session and shows login fields again
- [ ] Last.fm: scrobble appears on last.fm profile after playing 50%+ of a track
- [ ] Last.fm: special characters in password don't break auth (URL encoding)
- [ ] Last.fm: error messages shown in UI on auth failure
- [ ] Offline scrobble queue: scrobbles queued while offline
- [ ] Offline scrobble queue: queued scrobbles flush on reconnect (ListenBrainz and Last.fm)
- [ ] Now Playing notification sent on track start

## Settings 2.0

- [ ] Settings > Player sub-page opens (behavior, playback, scrobbling, controls, song display)
- [ ] Settings > Appearance sub-page opens (theme, glass, accent, text, mini player)
- [ ] Settings > Tab Bar sub-page opens (reorder tabs, toggle show/hide, settings location)
- [ ] Tab Bar: optional dock tabs for Artists, Albums, Songs, Genres, Favorites (all default OFF)
- [ ] All settings pages scrollable to bottom (mini player doesn't block)
- [ ] Disable Spinning Art toggle stops mini player rotation
- [ ] Reduce Motion also stops spinning art
- [ ] Volume Slider toggle hides/shows volume in Now Playing
- [ ] Audio Quality Info toggle hides/shows streaming info
- [ ] Heart/Rating/Queue toggles hide/show in Now Playing
- [ ] Liquid Glass toggle enables/disables glass effects
- [ ] Mini Player Tint toggle enables/disables color tint
- [ ] Swipe Gestures toggle enables/disables mini player swipe
- [ ] Now Playing Toolbar drag-to-reorder
- [ ] Tab Bar drag-to-reorder with Downloads tab option
- [ ] Settings in Navigation Bar moves Settings to top-right gear
- [ ] Toolbar shows only 2 buttons: + and profile
- [ ] Profile menu shows server name with green connection dot, music folders, downloads
- [ ] + button shows New Playlist / New Smart Playlist
- [ ] Haptic on tab switch
- [ ] Backup Settings exports named file (vibrdrome-backup-DATE.json)
- [ ] Restore Settings imports from JSON file and applies settings
- [ ] Crossfade Curve picker appears when crossfade > 0

## Playlists

- [ ] Playlist delete swipe targets correct song when search is active
- [ ] Make Public / Make Private toggle in playlist menu
- [ ] Globe icon shows on public playlists in list

## macOS Specific

- [ ] Keyboard shortcuts: Space (play/pause), Cmd+arrows (skip), Cmd+P
- [ ] Single instance prevention (second launch activates existing)

- [ ] Discord Rich Presence (enable toggle, verify Discord shows "Listening to...")
- [ ] Sidebar navigation works
- [ ] Pop-out mini player
- [ ] Volume slider in bottom bar

## watchOS Companion

- [ ] Watch app shows current song title and artist
- [ ] Play/Pause button works
- [ ] Next/Previous buttons work
- [ ] Digital Crown adjusts volume
- [ ] Updates in real-time when track changes on phone

## Accessibility

- [ ] VoiceOver navigates main screens
- [ ] Dynamic type (larger text) adjusts properly
- [ ] Reduce motion disables animations
- [ ] All interactive elements have accessibility identifiers
- [ ] Toolbar icon contrast is sufficient (opacity >= 0.5)

## AirPlay

- [ ] AirPlay button in Now Playing opens route picker
- [ ] Audio routes to AirPlay speaker
- [ ] Multi-room grouping works through system UI
- [ ] Playback pauses on AirPlay disconnect

## Platform

- [ ] Device rotation doesn't dismiss any views
- [ ] HTTP server connection works with warning
- [ ] HTTPS server connection works
- [ ] Adaptive Bitrate adjusts quality on constrained networks (iOS)
- [ ] No white flash when returning from background
