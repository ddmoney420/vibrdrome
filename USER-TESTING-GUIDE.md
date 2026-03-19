# Vibrdrome User Testing Guide

Complete testing checklist for real-device validation. Test on iPhone first, then macOS.

---

## 1. First Launch & Server Setup

- [ ] App launches without crash on fresh install
- [ ] Server config screen shows URL, Username, Password fields
- [ ] Enter Navidrome server URL, username, password
- [ ] "Sign In" button disabled until all fields filled
- [ ] Successful login navigates to main Library tab
- [ ] Credentials persist after force-quit and relaunch
- [ ] Invalid URL shows error message
- [ ] Wrong password shows error message

## 2. Library Tab

### Quick Access Bar
- [ ] **Artists** button opens alphabetical artist index
- [ ] **Albums** button opens all albums
- [ ] **Favorites** button shows starred songs
- [ ] **Genres** button shows genre list
- [ ] **Downloads** button opens offline tracks
- [ ] **Bookmarks** button opens saved resume points
- [ ] **Folders** button opens file browser

### Featured Sections
- [ ] **Recently Added** carousel shows albums with art
- [ ] **Most Played** carousel shows frequently played albums
- [ ] **Rediscover** shows shuffled starred songs
- [ ] **Random Picks** shows random albums
- [ ] **Recently Played** navigation opens recently played albums
- [ ] **Random Mix** button starts random playback
- [ ] "See All" links open filtered album views
- [ ] Tap album card opens album detail

### Artist Detail
- [ ] Artist page shows all albums
- [ ] Tap album opens album detail
- [ ] Album art loads from server
- [ ] **Start Radio** button generates artist-based radio queue

### Album Detail
- [ ] Header: album art, name, artist, year, genre, song count, duration
- [ ] **Play** button plays from track 1
- [ ] **Shuffle** button plays in random order
- [ ] **Download** button downloads all tracks
- [ ] **Star** button toggles favorite (heart icon updates)
- [ ] Track list shows number, title, duration
- [ ] Tap track plays immediately
- [ ] Long-press track shows context menu (Play Next, Add to Queue, Download, Star, Go to Artist)

### Bookmarks
- [ ] Bookmarks view shows saved resume points
- [ ] Each bookmark shows song, position timestamp
- [ ] Tap bookmark resumes playback from saved position
- [ ] Swipe to delete individual bookmarks
- [ ] Bookmarks auto-created when pausing/backgrounding mid-track

### Folders
- [ ] Folder browser shows server directory structure
- [ ] Navigate into subfolders
- [ ] Songs in folder are playable
- [ ] Back navigation works through folder hierarchy

## 3. Search Tab

- [ ] Search field appears at top
- [ ] Typing 2+ characters triggers search (debounced)
- [ ] Results show Artists (horizontal), Albums (horizontal), Songs (list)
- [ ] Tap artist opens artist detail
- [ ] Tap album opens album detail
- [ ] Tap song plays immediately
- [ ] Favorited songs show indicator
- [ ] Empty search shows no results message
- [ ] Search works with partial matches

## 4. Playlists Tab

### Playlist List
- [ ] Shows all playlists with cover art, name, song count
- [ ] Tap playlist opens detail view
- [ ] **New Playlist** button opens editor
- [ ] **Smart Mix** button opens smart playlist generator
- [ ] Long-press/context menu on playlist: Play, Shuffle, Delete
- [ ] Pull-to-refresh updates playlist list

### New Playlist
- [ ] Name field accepts input
- [ ] Can search and add songs (2+ characters)
- [ ] Can remove songs before saving (swipe)
- [ ] Can reorder songs (drag)
- [ ] Cancel dismisses without saving
- [ ] Create saves and shows new playlist

### Smart Mix
- [ ] Shows 6 mix types: Artist Mix, Genre Mix, Similar Songs, Random Mix, B-Sides & Obscure, Curated Weekly
- [ ] **Artist Mix**: search and select an artist, generates mix
- [ ] **Genre Mix**: select from available genres, generates mix
- [ ] **Similar Songs**: uses currently playing track as seed
- [ ] **Random Mix**: generates immediately (no parameters)
- [ ] **B-Sides & Obscure**: generates immediately
- [ ] **Curated Weekly**: generates immediately
- [ ] Generated songs can be played
- [ ] Option to save as named playlist

### Playlist Detail
- [ ] Shows all tracks with Play/Shuffle buttons
- [ ] Tap track plays from that position
- [ ] Can reorder tracks (drag)
- [ ] Can delete individual tracks (swipe)
- [ ] **Edit Playlist** button opens editor
- [ ] **Add All to Queue** button queues all tracks
- [ ] **Download Playlist** button downloads all tracks for offline
- [ ] **Remove Offline** button appears for downloaded playlists

## 5. Radio Tab

### Station List
- [ ] Shows configured internet radio stations
- [ ] Search bar filters stations by name
- [ ] Tap station starts streaming
- [ ] **Find Stations** opens station directory search
- [ ] **Add URL** opens custom station form
- [ ] Long-press/context menu: Delete station

### Station Search (Find Stations)
- [ ] Search field queries radio-browser.info
- [ ] Genre tags shown for quick browse (jazz, rock, electronic, etc.)
- [ ] Results show station name, country, codec, bitrate
- [ ] Can add stations to library
- [ ] Can preview/play station from results

### Add Custom Station
- [ ] Name field (required)
- [ ] Stream URL field (required)
- [ ] Homepage URL field (optional)
- [ ] Add button saves station
- [ ] Cancel dismisses

### Radio Playback
- [ ] Station streams audio
- [ ] Now Playing shows station name and radio indicator badge
- [ ] No progress slider (continuous stream)
- [ ] Mini player shows station info

### Song/Artist Radio
- [ ] Long-press track → **Start Radio** generates radio queue from that song
- [ ] Artist detail → **Start Radio** generates radio from artist
- [ ] Queue view shows radio indicator badge
- [ ] **Stop Radio** button in queue view ends radio mode
- [ ] Radio seed artist name displayed in queue

## 6. Now Playing (Full Player)

### Visual Elements
- [ ] Large album artwork with blurred background
- [ ] Song title, artist, album displayed
- [ ] Audio quality badges (year, genre, bitrate, format)
- [ ] Progress slider shows elapsed/remaining time
- [ ] Radio indicator badge when in radio mode

### Playback Controls
- [ ] **Play/Pause** toggles playback
- [ ] **Next** skips to next track
- [ ] **Previous** goes to previous track (or restarts if >3s in)
- [ ] **Shuffle** toggles shuffle mode (icon highlights)
- [ ] **Repeat** cycles: Off → All → One → Off (icon changes)

### Progress Slider
- [ ] Drag to seek to any position
- [ ] Time labels update in real-time
- [ ] Slider doesn't fight with playback updates while dragging

### Bottom Toolbar
- [ ] **Lyrics** button opens lyrics view
- [ ] **Star** button toggles favorite (heart fills/unfills)
- [ ] **EQ** button opens equalizer settings
- [ ] **AirPlay** picker shows available devices (iOS)
- [ ] **Queue** button opens queue view
- [ ] **Visualizer** button opens full-screen visualizer (iOS)

### Playback Speed
- [ ] Speed button shows current rate
- [ ] Menu: 0.5x, 0.75x, 1.0x, 1.25x, 1.5x, 1.75x, 2.0x
- [ ] Audio pitch changes with speed

### Sleep Timer
- [ ] Timer button opens duration picker
- [ ] Options: 15, 30, 45, 60, 120 minutes, End of Track
- [ ] Active timer shows countdown
- [ ] Fades volume in final 10 seconds
- [ ] Pauses playback when timer expires
- [ ] Cancel option available

## 7. Mini Player

### iOS
- [ ] Appears at bottom when music is playing
- [ ] Shows album art, song title, artist
- [ ] Play/Pause button works
- [ ] Next button skips track
- [ ] Tap song info area opens full Now Playing view
- [ ] Thin progress bar at top animates
- [ ] Disappears when no music active

### macOS
- [ ] Shows album art, song title, artist
- [ ] Transport controls: Previous, Play/Pause, Next
- [ ] Volume slider adjusts playback volume
- [ ] Pop-out button opens floating mini player window
- [ ] Full-width playback progress bar

### Pop-Out Player (macOS)
- [ ] Floating compact window (320x76)
- [ ] Shows album art, song info
- [ ] Transport controls work
- [ ] Stays on top of other windows

## 8. Queue View

- [ ] Shows "Now Playing" song at top
- [ ] "Up Next" list shows queued tracks with count
- [ ] Tap song jumps to that position
- [ ] Drag to reorder tracks
- [ ] Swipe to remove individual tracks
- [ ] **Clear** button removes all queued tracks
- [ ] **Shuffle** toggle randomizes queue
- [ ] Queue persists after app restart
- [ ] Radio mode: shows radio indicator badge
- [ ] Radio mode: **Stop Radio** button ends radio playback

## 9. Lyrics

### Synced Lyrics
- [ ] Current line highlighted in bold
- [ ] Auto-scrolls to follow playback
- [ ] Tap a line seeks to that timestamp
- [ ] Previous lines shown in secondary color

### Unsynced/No Lyrics
- [ ] Falls back to full text display
- [ ] "No Lyrics" message if none available

## 10. Visualizer (iOS only)

- [ ] Opens full-screen from Now Playing
- [ ] 6 presets: Plasma, Aurora, Nebula, Waveform, Tunnel, Kaleidoscope
- [ ] Swipe left/right changes preset
- [ ] Preset picker dropdown for direct selection
- [ ] Controls auto-hide after 4 seconds
- [ ] Tap screen toggles controls
- [ ] Song info overlay visible with controls
- [ ] Transport controls (previous, play/pause, next)
- [ ] Swipe down to close
- [ ] Responds to audio energy in real-time

## 11. Equalizer

- [ ] Toggle in Settings enables/disables EQ
- [ ] EQ Settings link opens full EQ view
- [ ] EQ button in Now Playing toolbar opens EQ view
- [ ] 10 band sliders (20Hz to 20kHz)
- [ ] Each slider: -12dB to +12dB range
- [ ] dB scale labels shown
- [ ] Gain value displayed per band
- [ ] Visual fill from center zero line
- [ ] Preset buttons: Flat + built-in presets
- [ ] Tap preset applies immediately
- [ ] Changes audible in real-time
- [ ] "Save as Preset" creates custom preset with name
- [ ] Custom presets appear in preset row
- [ ] Reset button returns all bands to 0dB
- [ ] EQ works on both streamed and local/downloaded audio

## 12. Audio Playback Quality

### Gapless Playback
- [ ] Enable in Settings → Playback
- [ ] Play an album end-to-end
- [ ] No silence gaps between tracks
- [ ] Crossfade toggle disabled when gapless is on

### Crossfade
- [ ] Disable gapless, enable crossfade
- [ ] Set duration (2/5/8/12 seconds)
- [ ] Tracks blend smoothly at transitions
- [ ] Volume fades naturally
- [ ] Short tracks (<2x fade duration) — fade clamped, no crash

### Replay Gain
- [ ] Set to Track mode
- [ ] Songs with loud/quiet mastering play at similar volume
- [ ] Set to Album mode — album tracks keep relative levels
- [ ] Off mode — no normalization applied

### Streaming Quality
- [ ] WiFi quality picker (Original/320/256/192/128 kbps)
- [ ] Switch to cellular — quality changes if configured differently
- [ ] Higher quality = better audio, more data usage

## 13. Downloads & Offline

### Downloading
- [ ] Long-press song → Download from context menu
- [ ] Album detail → Download All button
- [ ] Playlist detail → Download Playlist button
- [ ] Download progress shown in Downloads view
- [ ] Can cancel active downloads
- [ ] Downloads continue in background
- [ ] Interrupted downloads resume (HTTP Range support)

### Offline Playback
- [ ] Enable airplane mode
- [ ] Downloaded songs still play
- [ ] Non-downloaded songs show unavailable
- [ ] Downloads view shows all offline tracks with file sizes

### Storage Management
- [ ] Downloaded songs count shown in Settings
- [ ] Storage used progress bar in Settings
- [ ] "Delete All Downloads" works with confirmation
- [ ] Individual downloads deletable via swipe
- [ ] Cache limit picker in Settings
- [ ] Download over Cellular toggle (iOS)

## 14. Settings

### Server
- [ ] Server connection status indicator (checkmark)
- [ ] Server name and URL displayed
- [ ] Username displayed
- [ ] "Test Connection" pings server and shows result
- [ ] "Manage Servers" opens multi-server management
- [ ] Can add new server
- [ ] Can switch between servers (active indicator shown)
- [ ] Can remove servers
- [ ] "Sign Out" clears credentials and returns to login

### Playback
- [ ] WiFi Quality picker changes streaming bitrate
- [ ] Cellular Quality picker works separately (iOS)
- [ ] Scrobbling toggle sends/stops play events to server
- [ ] Gapless toggle affects track transitions
- [ ] Crossfade duration picker (only when gapless off)
- [ ] Replay Gain mode picker
- [ ] EQ toggle enables/disables equalizer
- [ ] EQ Settings link opens equalizer view

### Downloads
- [ ] Cache Limit picker
- [ ] Auto-Download Favorites toggle
- [ ] Download over Cellular toggle (iOS)
- [ ] Downloaded songs count accurate
- [ ] Storage used progress bar accurate

### Appearance
- [ ] Theme picker: System / Light / Dark
- [ ] Accent Color picker (10 colors with checkmark indicator, live preview)
- [ ] Show Album Art in Lists toggle

### CarPlay (iOS only)
- [ ] Recent Albums count picker (10/25/50)
- [ ] Show Genres toggle
- [ ] Show Radio toggle

### Accessibility
- [ ] Larger Text toggle scales fonts
- [ ] Bold Text toggle increases weight
- [ ] Reduce Motion toggle disables animations

### About
- [ ] Shows app version and build number
- [ ] API version info
- [ ] Offline queue status (pending/failed action counts)
- [ ] **Sync Now** button syncs pending actions
- [ ] **Retry Failed** button retries failed actions
- [ ] **Clear Failed** button clears failed action queue

## 15. Re-Authentication

- [ ] If server session expires (401), ReAuth modal appears
- [ ] Modal shows "Session Expired" with server URL and username (read-only)
- [ ] Password field (secure input)
- [ ] Sign In button with loading indicator
- [ ] Enter password → re-authenticates without losing navigation
- [ ] Sign Out option available from modal
- [ ] Error message displayed on auth failure

## 16. Track Context Menu

Long-press (iOS) or right-click (macOS) on any track:

### Playback Actions
- [ ] **Play** starts playback
- [ ] **Play Next** inserts after current track
- [ ] **Add to Queue** appends to end of queue
- [ ] **Start Radio** generates radio from this song
- [ ] **Download** saves track for offline

### Library Actions
- [ ] **Add to Playlist...** opens playlist picker
- [ ] **Favorite/Unfavorite** toggles star status

### Navigation Actions
- [ ] **Go to Album** opens album detail
- [ ] **Go to Artist** opens artist detail

## 17. Edge Cases

### Network
- [ ] Lose WiFi mid-song — playback handles gracefully
- [ ] Airplane mode — offline tracks work, online show error
- [ ] Switch WiFi → Cellular — streaming continues
- [ ] Server unreachable — error message, no crash

### Playback
- [ ] Play very short track (<5s) — no crash
- [ ] Skip rapidly through tracks — no crash or stuck state
- [ ] Background playback — music continues when app minimized
- [ ] Lock screen controls work (play/pause/skip)
- [ ] Control Center shows correct song info + art
- [ ] Headphone controls (play/pause, skip) work

### Memory & Performance
- [ ] Scroll through large library (1000+ songs) without lag
- [ ] Multiple downloads don't freeze UI
- [ ] Long listening session (1+ hour) — no memory growth

## 18. Device Rotation (iPhone)

- [ ] Library view adapts to landscape
- [ ] Now Playing view works in landscape
- [ ] Settings view scrollable in landscape
- [ ] Mini player visible in both orientations
- [ ] No layout clipping or overlapping

## 19. macOS-Specific

- [ ] Full-screen toggle in Now Playing view
- [ ] Pop-out mini player window
- [ ] Keyboard shortcut: Cmd+P for play/pause
- [ ] Right-click context menus on tracks
- [ ] Window resizing — layout adapts properly
- [ ] Menu bar integration

---

## Quick Smoke Test (5 minutes)

If short on time, hit these critical paths:

1. Launch app → verify Library loads
2. Play a song from album detail
3. Verify Now Playing shows correct info
4. Skip next/previous
5. Open queue → verify tracks listed
6. Try shuffle and repeat
7. Search for an artist → play from results
8. Go to Radio → stream a station
9. Open Settings → verify server connected
10. Force quit → relaunch → verify music state restored
