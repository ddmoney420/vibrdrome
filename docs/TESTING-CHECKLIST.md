# Vibrdrome Device Testing Checklist

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
