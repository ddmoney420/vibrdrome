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

## Library & Navigation

- [ ] Library loads with carousels
- [ ] Pull to refresh on Library
- [ ] Search returns results (including fuzzy/acronym search)
- [ ] Recent searches appear (saved on submit, not on keystroke)
- [ ] Navigate to artist detail (from search, album, or Now Playing)
- [ ] Navigate to album detail
- [ ] Artist detail shows biography (About section)
- [ ] Artist detail shows Similar Artists carousel
- [ ] Genre list shows artwork
- [ ] Generations shows decade cards
- [ ] Playlists load (grid and list view toggle)
- [ ] Playlist mosaic shows 2x2 album art grid
- [ ] Radio stations load (grid and list view toggle)
- [ ] Library folder switching (if multi-library server)
- [ ] Customizable library (add/remove/reorder pills and carousels)
- [ ] Play History shows stats (today/week/all-time, top artists/albums)
- [ ] Songs view shows count in title, Play All / Shuffle buttons work
- [ ] Favorites view Play All / Shuffle buttons work

## Now Playing

- [ ] Album art displays
- [ ] Fade/scale transition on present
- [ ] Artist name tappable (navigates to artist)
- [ ] Heart / 5-star rating / sleep timer on one row
- [ ] Star rating works (tap to rate, tap same to clear)
- [ ] Sleep timer countdown shows next to moon icon
- [ ] Streaming info shows below progress (bitrate, format, WiFi/Downloaded)
- [ ] Shuffle / repeat flank transport controls (prev/play/next)
- [ ] Volume slider adjusts playback volume
- [ ] Bottom toolbar: Queue, EQ, Visualizer, Lyrics, More(...)
- [ ] More menu: Speed, AirPlay, Share, Download all work
- [ ] EQ sheet opens from toolbar
- [ ] Lyrics sheet opens (synced lyrics auto-scroll and tap-to-seek)
- [ ] Visualizer opens (if not disabled)
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

## Queue

- [ ] Tap to jump to track
- [ ] Swipe left to remove
- [ ] Drag to reorder
- [ ] Long-press context menu works
- [ ] Save as Playlist from menu
- [ ] Total duration shows in "Up Next" header

## Context Menus

- [ ] Play / Play Next / Add to Queue
- [ ] Start Radio from song
- [ ] Download
- [ ] Add to Playlist
- [ ] Favorite / Unfavorite
- [ ] Go to Album / Go to Artist
- [ ] Share (sends "Title — Artist" text)

## Album Detail

- [ ] Parallax album art header (shrinks/fades on scroll)
- [ ] Circular action buttons: Heart, Play, Shuffle, More(...)
- [ ] More menu: Download, Start Radio, Share
- [ ] Heart/favorite toggles correctly
- [ ] Multi-disc separator shows for multi-disc albums
- [ ] Similar Albums carousel at bottom

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
- [ ] Browse library
- [ ] Search works (Library > Search)
- [ ] Play/pause/skip from CarPlay
- [ ] No logout on CarPlay connect/disconnect
- [ ] Artwork shows on all lists

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

## Scrobbling

- [ ] Subsonic scrobbling works (check server play count)
- [ ] ListenBrainz scrobbling (enable toggle, enter token, verify at listenbrainz.org)
- [ ] Now Playing notification sent on track start

## Settings

- [ ] WiFi/Cellular quality pickers work
- [ ] Theme switching works (dark/light/system)
- [ ] Accent color changes apply
- [ ] Text size picker works (Small/Default/Large/Extra Large)
- [ ] Tab bar customization (toggle Search/Playlists/Radio)
- [ ] Disable Visualizer hides visualizer button
- [ ] Multi-server: add/switch/delete servers
- [ ] ListenBrainz toggle and token field
- [ ] Auto-sync playlists toggle

## macOS Specific

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
