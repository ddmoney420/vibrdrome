# Regression Testing Checklist

Run through this checklist before every TestFlight build. Each item should be verified on a real device.

## Pre-Build (Automated)

- [ ] `swiftlint` — 0 violations
- [ ] Unit tests pass (`xcodebuild test -only-testing:VibrdromeTests`)
- [ ] UI rotation tests pass (`xcodebuild test -only-testing:VibrdromeUITests/RotationTests`)
- [ ] Build succeeds with 0 warnings

## Core Playback

- [ ] Play a song from album detail
- [ ] Pause / resume from Now Playing
- [ ] Next / previous track
- [ ] Seek via progress slider
- [ ] Lock screen controls work (play/pause, next, previous)
- [ ] Audio continues when app is backgrounded
- [ ] Gapless playback (two tracks transition without gap)
- [ ] Crossfade works when enabled in settings

## Library & Navigation

- [ ] Library loads with carousels
- [ ] Pull to refresh on Library
- [ ] Search returns results
- [ ] Recent searches appear
- [ ] Navigate to artist detail (from search, album, or Now Playing)
- [ ] Navigate to album detail
- [ ] Genre list shows artwork
- [ ] Generations shows decade cards
- [ ] Playlists load (grid and list view toggle)
- [ ] Radio stations load (grid and list view toggle)
- [ ] Library folder switching (if multi-library server)
- [ ] Customizable library (add/remove/reorder pills and carousels)

## Now Playing

- [ ] Album art displays
- [ ] Artist name tappable (navigates to artist)
- [ ] Album name tappable (navigates to album)
- [ ] 5-star rating works (tap to rate, tap same to clear)
- [ ] Sleep timer countdown shows next to moon icon
- [ ] Shuffle / repeat toggles work
- [ ] EQ sheet opens
- [ ] Lyrics sheet opens
- [ ] Visualizer opens (if not disabled)
- [ ] Queue opens
- [ ] Long-press album art shows save/share options
- [ ] Drag to dismiss works
- [ ] Rotation keeps player open

## Queue

- [ ] Tap to jump to track
- [ ] Swipe left to remove
- [ ] Drag to reorder
- [ ] Long-press context menu works
- [ ] Save as Playlist from menu

## Widget

- [ ] Small widget shows album art and title
- [ ] Medium widget shows controls
- [ ] Large widget shows full layout
- [ ] Widget updates on track change
- [ ] Widget updates on pause/resume

## CarPlay

- [ ] App appears on CarPlay dashboard
- [ ] Browse library
- [ ] Search works (Library > Search)
- [ ] Play/pause/skip from CarPlay
- [ ] No logout on CarPlay connect/disconnect

## Radio

- [ ] Play a radio station
- [ ] Station artwork shows (if Navidrome 0.61+)
- [ ] Mini player shows radio artwork
- [ ] Find Stations search works

## Downloads & Offline

- [ ] Download a song
- [ ] Downloaded song shows green arrow indicator
- [ ] Offline banner appears when network disconnected
- [ ] Downloaded songs play while offline

## Settings

- [ ] WiFi/Cellular quality pickers work
- [ ] Theme switching works (dark/light/system)
- [ ] Accent color changes apply
- [ ] Disable Visualizer hides visualizer button
- [ ] Multi-server: add/switch/delete servers

## Accessibility

- [ ] VoiceOver navigates main screens
- [ ] Dynamic type (larger text) adjusts properly
- [ ] Reduce motion disables animations

## Platform

- [ ] Device rotation doesn't dismiss any views
- [ ] HTTP server connection works with warning
- [ ] HTTPS server connection works
