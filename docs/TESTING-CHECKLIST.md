# Vibrdrome Device Testing Checklist

## Unreleased — Small-iPhone layout & navigation (#69, #72, #70)

- [ ] **#69:** on a small iPhone (SE / 13 mini), the mini player clears the tab bar — icons and labels fully visible and tappable; notched phones unchanged
- [ ] **#72:** Now Playing → Quick Settings opens tall enough that Download and Share are reachable on a small iPhone; the sheet still drags down to medium
- [ ] **#70:** the bottom-right "More" tab opens an in-app More list, and More → Settings → Player shows a single back-chevron (no double arrow); More → Radio is also single-stacked
- [ ] **#70:** primary tabs and the top-right gear Settings path still work; reordering/hiding tabs moves items between the tab bar and More correctly

## Build 54 — OpenSubsonic metadata, security, download crash

- [ ] Multi-artist track shows each credited artist as a separate tappable link; each navigates to the right artist (iOS + macOS)
- [ ] Track on a Various Artists / compilation album shows the real per-track artist, not "Various Artists" (test both Subsonic and Navidrome-native paths)
- [ ] Single-artist track still shows one tappable artist link
- [ ] Album with an edition (e.g. "Deluxe Edition") shows the edition separately from the title
- [ ] Get Info → song shows Credits / Classical sections when the server provides them
- [ ] Get Info → album shows release dates, moods, compilation flag, disc titles
- [ ] macOS album filter sidebar "Is compilation" tristate filters correctly
- [ ] Opening Search is smooth with no transition hitch (#80)
- [ ] Settings → Artist External Links rejects a non-http(s) template (e.g. `javascript:`); existing http/https links still open (macOS) (#73, #74)
- [ ] **Download crash (#77):** start a download, background the app, lock the screen, let the download finish while suspended — reopen and confirm the track is downloaded with no crash. Repeat with several downloads finishing together.
- [ ] **Downloads grouping (#76):** Downloads screen shows albums (and a Playlists section) instead of one flat list; tapping opens the collection's tracks
- [ ] **Play Playlist (#57):** Shortcuts app → "Play Playlist" action → enter a playlist name → it plays
- [ ] **Internet lyrics (#82):** a track your server has no lyrics for shows lyrics from the internet; toggling off Settings → Player → "Fetch Lyrics from the Internet" disables it
- [ ] **Lyric timing (#86):** the bottom timing bar on synced lyrics nudges sync in 0.1s steps and is remembered per song

## Build 53 — Diagnostics (MetricKit)

- [ ] Settings → Diagnostics opens (iOS + macOS)
- [ ] Crash & Hang Reports shows empty-state text when there are no events
- [ ] Recent Logs populate from the current session
- [ ] Copy button puts crash reports + logs on the clipboard
- [ ] After a forced crash + relaunch, a crash report appears in Diagnostics
- [ ] Now Playing toolbar icons visible in light mode over light art (#79)
- [ ] Favorites empty state shows a single message (#67)
- [ ] Mini-player artwork resets to 0° when Spinning Art disabled (#71)
- [ ] Widget shows correct cover art

A lightweight smoke list. For the full build-by-build regression list, see [TESTING.md](../TESTING.md) in the repo root.

## Core Playback
- [ ] Play a song, skip forward/back, scrub the progress bar
- [ ] Let an album play through -- verify gapless transitions
- [ ] Enable crossfade in settings, play through a transition
- [ ] Try the EQ -- toggle presets, adjust bands
- [ ] Lock the phone -- verify lock screen controls work
- [ ] Play music, open another app -- confirm background audio continues

## Library Browsing
- [ ] Browse by artist, album, genre, folder
- [ ] Search for a song, album, and artist
- [ ] Check that album art loads correctly
- [ ] Star/favorite a song, verify it syncs to Navidrome
- [ ] Long-press any song / album / artist and open **Get Info**; Overview tab shows art, title, year, bitrate, ReplayGain, MusicBrainz + Last.fm links; Raw Metadata tab shows full Subsonic response and Navidrome rawTags

## Offline & Downloads
- [ ] Download an album for offline
- [ ] Turn on airplane mode, play the downloaded album
- [ ] Check storage usage in settings

## Playlists
- [ ] Create a playlist, add songs, reorder, delete
- [ ] Play a playlist start to finish

## Radio
- [ ] Search for a station in Find Stations
- [ ] Play a radio stream
- [ ] Add a custom stream URL -- verify the Add Station form shows three labeled sections (Name / Stream URL / Homepage)
- [ ] Long-press a radio station card and choose **Delete Station**; verify it works in portrait and landscape on both iPhone and iPad

## Now Playing Toolbar
- [ ] Open Settings > Player > Now Playing Toolbar and toggle items off; the toolbar pill disappears entirely when all items are off (no empty pill)
- [ ] Enable the **Radio Mix** item; while a song plays, tap Radio Mix and verify it queues songs similar to the current track (not the full artist radio)
- [ ] Toggle the optional toolbar background and verify the pill gets a frosted background

## macOS
- [ ] Menu bar shows a **Navigate** menu with **Go to Search (⌘K)** and **Focus Search (⌘F)**; both shortcuts fire without a system beep
- [ ] Long-press an item and open **Get Info**; it opens as its own window (not a sheet) and multiple can be open at once
- [ ] Enable Liquid Glass in Appearance and confirm the toolbar/mini player get a frosted background

## iPad
- [ ] On iPad, bring up the floating keyboard; the mini player stays pinned to the bottom and is not pushed off-screen

## CarPlay (Build 51)
- [ ] Connect to CarPlay with a library that has many artists starting with the same letter (e.g. "S")
- [ ] Open **Artists**; tap a first letter, then a second letter; verify you land in that 2-letter slice instead of a flat list
- [ ] Repeat for **Albums**
- [ ] Start a new track from CarPlay; verify the browse list stays on screen (no auto-push to Now Playing)
- [ ] While playing, trigger a short incoming call or text; resume playback and verify the track continues from where it was, not from 0

## CarPlay (Build 52)
- [ ] Open **Albums** with a library larger than 500 albums; verify the alphabet directory shows every letter the library actually has, not just `#` and one or two letters (#32)
- [ ] Force-quit Vibrdrome on iPhone, connect CarPlay; verify the system Now Playing button at the top-right appears immediately and the iOS lock-screen widget shows the last track (#45)
- [ ] In CarPlay, drill deep: **Library -> Artists -> letter -> Artists-in-letter -> Artist detail -> Album**, then tap the system Now Playing icon at the top right; app does not crash (template depth cap)

## macOS (Build 52)
- [ ] Cold-launch the macOS app; loading screen displays sync/cache progress, crossfades to home once cache is ready (#54)
- [ ] Home tab shows configurable discovery sections; open the customize sheet, toggle and reorder sections, relaunch the app, choices persist (#54)
- [ ] Open an artist; verify the new hero header layout with circular portrait, biography expand/collapse, genre pills, stats row, and external links row (#56)
- [ ] Open **Settings > Artist External Links**; toggle defaults, add a custom URL with `{artist}` placeholder, return to an artist and confirm the custom link appears (#56)
- [ ] Open an album; verify rich metadata layout, clickable genre and label pills that drill into the corresponding filter, copy-selectable MusicBrainz ID (#49)
- [ ] In **Songs / Album Detail / Playlist Detail**, toggle to the column table view; reorder and hide columns; relaunch and verify the layout persists (#31)
- [ ] On the Albums grid, hover a card; favorite and rating buttons fade in. Star or unstar the album from a different view, return to the grid, hover again -- state reflects the change (regression fix)
- [ ] Open the **Library Filter** sidebar; multi-select genre / label / artist; TriState favorites and downloaded toggles narrow the list (#21 / #47)

## Visualizer (Build 51)
- [ ] Open the visualizer from Now Playing; select **Spectrum** preset
- [ ] Play a bass-heavy track; verify the left side of the bar graph reacts harder than the right
- [ ] Play a cymbal-heavy track; verify the right side reacts harder
- [ ] Verify each bar has a white peak-hold cap that snaps up on transients and decays slowly
- [ ] Switch to **Waveform**; verify the mirrored ribbon bulges from real frequency content (silence collapses it to a flat line)
- [ ] Switch to **Aurora**; verify the ribbons bend with frequency content rather than pure sine patterns
- [ ] Test on both iPhone and macOS
- [ ] With Console.app filtered to `subsystem:com.vibrdrome.app`, confirm `Spectrum diag` fires once per second while audio plays

## Extras
- [ ] Try lyrics on a song that has them
- [ ] Set a sleep timer, let it fade out
- [ ] Adjust playback speed
- [ ] Try different themes/accent colors

## Edge Cases
- [ ] Kill the app mid-song, reopen -- does it remember state?
- [ ] Poor Wi-Fi / switch between Wi-Fi and cellular
- [ ] Incoming phone call during playback
