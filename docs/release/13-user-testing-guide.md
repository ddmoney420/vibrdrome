```
 _____  _____  _____  _____  _____  _   _  _____
|_   _||  ___|/  ___||_   _||_   _|| \ | ||  __ \
  | |  | |__  \ `--.   | |    | |  |  \| || |  \/
  | |  |  __|  `--. \  | |    | |  | . ` || | __
  | |  | |___ /\__/ /  | |   _| |_ | |\  || |_\ \
  \_/  \____/ \____/   \_/   \___/ \_| \_/ \____/
```

# User Testing Guide & Feature Walkthrough ♪♫(◕‿◕)♫♪

**App:** Vibrdrome — iOS/macOS Music Player for Navidrome
**Version:** 1.0.0
**Date:** 2026-02-21

This guide walks through every user-facing feature with step-by-step instructions for testing. Use it alongside the [Real-Device Testing Plan](09-user-testing-plan.md) for formal test execution.

---

```
 _    _   ___   _      _   __ _____  _   _ ______  _   _
| |  | | / _ \ | |    | | / /|_   _|| | | || ___ \| | | |
| |  | |/ /_\ \| |    | |/ /   | |  | |_| || |_/ /| | | |
| |/\| ||  _  || |    |    \   | |  |  _  ||    / | | | |
\  /\  /| | | || |____| |\  \  | |  | | | || |\ \ | |_| |
 \/  \/ \_| |_/\_____/\_| \_/  \_/  \_| |_/\_| \_| \___/
```

## 1. First Launch & Authentication

### Sign In
1. Launch Vibrdrome — the **Server Configuration** screen appears.
2. Enter your Navidrome server URL (e.g., `https://music.example.com`).
3. Enter username and password.
4. Tap **"Test Connection"** — should show a success indicator.
5. Tap **"Save"** — the app navigates to the main library.

### Multi-Server
1. Go to **Settings > Manage Servers**.
2. Tap **"Add Server"** to add a second Navidrome server.
3. Switch between servers — library content should update to reflect each server.
4. Verify offline playlists and pending actions are isolated per server.

---

## 2. Library Browsing

### Tab Bar (iOS) / Sidebar (macOS)

**iOS:** Bottom tab bar with Library, Search, Playlists, Radio, Settings.
**macOS:** NavigationSplitView sidebar with all sections.

### Artists
1. Open **Library > Artists**.
2. Scroll through the alphabetical list — section index on the right for quick jump.
3. Tap an artist to open **ArtistDetailView**.
4. See the artist's albums listed with artwork.
5. Tap **"Start Radio"** button in the toolbar to begin artist radio (see Section 7).

### Albums
1. Open **Library > Albums**.
2. Browse album grid with artwork loaded via NukeUI.
3. Tap an album to open **AlbumDetailView**.
4. See track list with track numbers, durations.
5. Buttons available: **Play All**, **Shuffle**, **Download Album**.
6. Long-press a track for context menu (see Section 10).

### Songs
1. Open **Library > Songs** (if available).
2. Browse all songs with artist/album metadata.
3. Tap a song to start playback.

### Genres
1. Open **Library > Genres**.
2. See genre names with song/album counts.
3. Tap a genre to see albums and songs in that genre.

### Favorites
1. Open **Library > Favorites**.
2. Three sections: Starred Artists, Starred Albums, Starred Songs.
3. Verify only starred items appear.
4. Star/unstar from other views — favorites should update.

### Folders
1. Open **Library > Folders**.
2. See the server's folder hierarchy (music folders).
3. Tap a folder to drill into subdirectories.
4. Tap a song file to play.
5. **"Play All"** and **"Shuffle"** buttons available per folder.

### Bookmarks
1. Open **Library > Bookmarks**.
2. See saved playback positions for long tracks.
3. Tap a bookmark to resume playback from that position.

---

## 3. Search

1. Tap the **Search** tab.
2. Type 3+ characters in the search bar.
3. Results are categorized: **Artists**, **Albums**, **Songs**.
4. Tap a result to navigate to that item's detail view.
5. Tap a song result to start playback immediately.

---

## 4. Playlists

### Browse Playlists
1. Open the **Playlists** tab.
2. See playlist grid with artwork and song counts.
3. Tap a playlist to open **PlaylistDetailView**.

### Playlist Detail
1. See the full track list with metadata.
2. **Play All** / **Shuffle** buttons at top.
3. **Download Playlist** button — downloads all tracks for offline play (see Section 9).
4. Offline badge shows if playlist is fully downloaded.

### Create / Edit Playlist
1. Tap **"+"** or **"Create Playlist"**.
2. Enter playlist name in **PlaylistEditorView**.
3. Add songs from the library.
4. Reorder tracks via drag handles.
5. Delete tracks by swiping.

### Smart Playlists
1. Tap **"Smart Mix"** button.
2. Choose from 6 auto-generated playlist types.
3. Verify the generated playlist loads with appropriate content.

---

## 5. Now Playing (⌐■_■)

### Opening Now Playing
- Tap the **mini player** at the bottom of any screen.
- Or tap a song to start playback — Now Playing appears.

### Layout
- **Album artwork** with blurred background.
- **Song title**, artist, album below the artwork.
- **Progress slider** with elapsed/remaining time.
- **Playback controls**: Previous, Play/Pause, Next.

### Bottom Toolbar (left to right)
| Button | Icon | Function |
|---|---|---|
| Shuffle | `shuffle` | Toggle shuffle mode (white when active) |
| Sleep Timer | `moon` | Menu: 15m, 30m, 45m, 1h, 2h, End of Track, Cancel |
| Speed | `1x` | Menu: 0.5x, 0.75x, Normal, 1.25x, 1.5x, 1.75x, 2.0x |
| EQ | `slider.vertical.3` | Opens 10-band equalizer sheet |
| Lyrics | `quote.bubble` | Opens synced lyrics sheet |
| Visualizer | `waveform.path` | Opens fullscreen Metal visualizer (iOS only) |
| Favorite | `heart` | Star/unstar current track (pink when starred) |
| AirPlay | AirPlay icon | AirPlay device picker (iOS only) |
| Queue | `list.bullet` | Opens queue management sheet |
| Repeat | `repeat` / `repeat.1` | Cycle: Off → All → One |
| Fullscreen | arrows | Toggle fullscreen (macOS only) |

### Mini Player
- Shows at bottom of all screens while music plays.
- Displays: album art thumbnail, song title, artist.
- Controls: Play/Pause, Next.
- Progress bar along the top.
- Tap to expand to full Now Playing view.

---

## 6. Playback Modes

### Gapless Playback (Default)
1. Go to **Settings > Playback > Gapless Playback** — ensure enabled.
2. Set **Crossfade** to "Off" (0s).
3. Play an album with multiple tracks.
4. Listen at track boundaries — transitions should be seamless, no audible gap.
5. Verify with both downloaded and streaming tracks.

### Crossfade
1. Go to **Settings > Playback > Crossfade Duration**.
2. Set to **5 seconds**.
3. Play an album — listen for smooth volume overlap at track transitions.
4. The outgoing track fades out while the incoming track fades in.
5. Try different durations: 2s, 8s, 12s.
6. **Edge case:** Set crossfade on a very short track (< 10s) — fade should auto-clamp to 50% of track duration.

### EQ Mode
1. Go to **Settings > Playback > Equalizer** — enable it.
2. Play any track (downloaded or streaming).
3. Open **EQ** from the Now Playing toolbar.
4. Try presets: Flat, Bass Boost, Treble Boost, Rock, Pop, Jazz, Classical, Vocal, Late Night.
5. Adjust individual band sliders (32Hz to 16kHz).
6. Save a custom preset.
7. **Streaming tracks:** EQ activates after a brief buffer (music plays immediately via gapless while the stream downloads to a temp file, then seamlessly switches to EQ mode).
8. **Downloaded tracks:** EQ applies instantly with no delay.

### Mode Priority
The app automatically selects the playback mode:
1. **EQ Mode** — if EQ enabled (works for all tracks; streams buffered to temp file)
2. **Crossfade** — if crossfade duration > 0
3. **Gapless** — default (crossfade = 0)

Test by toggling settings and observing which mode activates.

---

## 7. Artist Radio ♪♫(◕‿◕)♫♪

### Starting Radio
There are 4 entry points:

1. **ArtistDetailView** — tap **"Start Radio"** in the toolbar.
2. **NowPlayingView** — use the overflow menu **"Start Radio"**.
3. **Track Context Menu** — long-press a song, tap **"Start Artist Radio"**.
4. **CarPlay** — **"Artist Radio"** option in CarPlay browse menu.

### Testing Radio
1. Start radio from an artist with a large catalog (100+ songs).
2. Verify the queue fills with ~40 tracks initially.
3. Let it play — when approaching the end (< 5 tracks remaining), verify the queue auto-refills with similar songs.
4. Open the **Queue view** — should show a **"Radio Mode"** badge with a stop button.
5. Tap **"Skip & Block"** on a track — it should never reappear in this radio session.
6. Let radio play 20+ tracks unattended to verify continuous playback.

### Fallback Testing
1. Start radio from an artist with a **sparse catalog** (< 5 songs).
2. Verify fallback: samples from artist's albums, then random songs by genre.
3. Start radio from an artist with **no songs** — should show "No radio tracks found" and not enter radio mode.

### Exiting Radio
1. Tap **"Stop Radio"** in the Queue view.
2. Or select a new album/playlist to play — radio mode exits automatically.
3. Verify shuffle/repeat settings are restored after exiting radio.

---

## 8. Sleep Timer

1. Open Now Playing → tap the **moon icon** in the bottom toolbar.
2. Select a duration: **15 min**, **30 min**, **45 min**, **1 hr**, **2 hr**, or **End of Track**.
3. The moon icon fills when timer is active.
4. For timed modes: in the last 30 seconds, volume should gradually fade to zero, then pause.
5. For **End of Track**: playback pauses when the current track finishes.
6. Tap the moon icon again → **"Cancel Timer"** to stop early.

---

## 9. Downloads & Offline Mode

### Downloading Content
1. **Single song**: Long-press a song → **"Download"** from context menu.
2. **Full album**: Open album detail → tap **"Download Album"** button.
3. **Full playlist**: Open playlist detail → tap **"Download Playlist"** button.
4. Progress indicators appear per-track during download.

### Downloads View
1. Open **Downloads** (from Library or Settings).
2. See in-progress downloads with progress bars.
3. See completed downloads with file sizes.
4. Storage usage displayed at the top.
5. Swipe to delete individual downloads.
6. **"Delete All"** button to clear everything.

### Offline Playback
1. Download several songs/albums/playlists.
2. Enable **Airplane Mode**.
3. Navigate to downloaded content — it should render fully (title, tracks, artwork) without network.
4. Tap a downloaded song — it should play from local cache.
5. Play through an entire downloaded playlist — all tracks should work.
6. Non-downloaded content should show an offline indicator.

### Offline Playlists
1. Download a full playlist.
2. Force-quit the app.
3. Relaunch in Airplane Mode.
4. Open the playlist — it should appear in the library and be fully playable.
5. All metadata (title, artist, duration, cover art) should display without network.

### Cache Management
1. Go to **Settings > Downloads > Cache Limit**.
2. Set a limit (e.g., 1 GB).
3. Download content beyond the limit.
4. Verify oldest non-pinned tracks are evicted (LRU).
5. Tracks in offline playlists should **never** be evicted (pinned).

---

## 10. Context Menus

Long-press any song to see these options:

| Option | What It Does |
|---|---|
| Star / Unstar | Toggle favorite status |
| Add to Playlist | Add song to an existing playlist |
| Download | Download for offline playback |
| Add to Next | Insert after currently playing song |
| Add to Queue End | Append to end of queue |
| Start Artist Radio | Begin radio from this song's artist |
| Show Artist | Navigate to artist detail |
| Show Album | Navigate to album detail |

Album context menus offer: Star, Download Album, Play, Shuffle, Show Artist.

---

## 11. Playback Speed

1. Open Now Playing → tap the **speed indicator** (shows "1x" by default).
2. Select a speed: **0.5x**, **0.75x**, **Normal**, **1.25x**, **1.5x**, **1.75x**, **2.0x**.
3. Verify pitch is preserved (audio should not sound chipmunk/slowed).
4. Verify the Control Center / Lock Screen shows the correct playback rate.
5. Speed should work in all three playback modes (gapless, crossfade, EQ).

---

## 12. ReplayGain

1. Go to **Settings > Playback > ReplayGain Mode**.
2. Options: **Off**, **Track**, **Album**.
3. Play tracks with varying loudness levels.
4. With **Track** mode: each track should play at a normalized volume.
5. With **Album** mode: tracks within an album maintain relative dynamics, but different albums are normalized.
6. Verify volume doesn't clip (no distortion on loud tracks).

---

## 13. Lyrics

1. Open Now Playing → tap the **lyrics icon** (`quote.bubble`).
2. If the server has synced lyrics, they scroll automatically with playback.
3. Tap a lyric line to seek to that timestamp.
4. If only unsynced lyrics are available, they display as static text.
5. If no lyrics exist, an appropriate message is shown.
6. **Retry button** appears on error.

---

## 14. Audio Visualizer (iOS Only)

1. Open Now Playing → tap the **visualizer icon** (`waveform.path`).
2. A fullscreen Metal shader visualization appears.
3. **6 presets available**: Plasma, Aurora, Nebula, Waveform, Tunnel, Kaleidoscope.
4. Swipe or tap to change presets.
5. Visualization responds to audio energy in real-time.
6. Controls auto-hide after a timeout.
7. Dismiss by tapping the close button or swiping down.

---

## 15. Internet Radio

### Browse Stations
1. Open the **Radio** tab.
2. See configured radio stations.
3. Tap a station to start streaming.

### Add Station
1. Tap **"Add URL"** in the toolbar.
2. Enter the stream URL (supports HTTP and HTTPS).
3. The station appears in the list.

### Search Stations
1. Tap **"Find Stations"** in the toolbar.
2. Search for internet radio stations online.
3. Select a station to add it.

### Playback
1. Radio streams show **"Internet Radio"** as the artist.
2. Now Playing shows the station name.
3. No seek bar (live stream).
4. No gapless/crossfade/EQ for radio streams.

---

## 16. Queue Management

1. Open Now Playing → tap the **queue icon** (`list.bullet`).
2. See **"Now Playing"** section with the current track.
3. See **"Up Next"** section with upcoming tracks and count.
4. **Drag** tracks to reorder.
5. **Swipe left** on a track to remove it.
6. In radio mode: a **radio badge** appears with a **"Stop Radio"** button.
7. Queue persists across app restarts (saved via Subsonic `savePlayQueue`).

---

## 17. Shuffle & Repeat

### Shuffle
1. Tap the **shuffle icon** in the Now Playing bottom toolbar.
2. White = active, dim = inactive.
3. When active, tracks play in random order.
4. With Repeat Off: each track plays once, then stops.
5. With Repeat All: random order repeats indefinitely.

### Repeat
1. Tap the **repeat icon** to cycle modes:
   - **Off**: Play through queue once, stop at end.
   - **Repeat All** (`repeat` icon, white): Loop the entire queue.
   - **Repeat One** (`repeat.1` icon, white): Loop the current track.
2. Repeat One disables gapless lookahead (track loops at the end).

---

## 18. Settings (⌐■_■)

### Playback Settings
| Setting | Options | Notes |
|---|---|---|
| WiFi Quality | Original, 320, 256, 192, 128 kbps | Bitrate for WiFi streaming |
| Cellular Quality | Same options | iOS only, bitrate on cellular |
| Scrobbling | On/Off | Submit plays to server |
| Gapless Playback | On/Off | Seamless track transitions |
| Crossfade Duration | Off, 2s, 5s, 8s, 12s | Mutually exclusive with gapless |
| ReplayGain Mode | Off, Track, Album | Volume normalization |
| Equalizer | On/Off | All tracks (streams buffered automatically) |
| EQ Settings | → EQView | 10-band + presets |

### Download Settings
| Setting | Options | Notes |
|---|---|---|
| Cache Limit | 1GB, 5GB, 10GB, 25GB, 50GB, Unlimited | LRU eviction, playlist pins protected |
| Auto-Download Favorites | On/Off | Auto-download when you star a song |
| Download Over Cellular | On/Off | iOS only |
| Delete All Downloads | Button | Clears all cached audio |

### Appearance Settings
| Setting | Options |
|---|---|
| Theme | System, Dark, Light |
| Accent Color | Blue, Purple, Pink, Red, Orange, Yellow, Green, Teal, Indigo, Mint |
| Album Art in Lists | On/Off |

### CarPlay Settings (iOS Only)
| Setting | Options |
|---|---|
| Recent Albums Count | 10, 25, 50 |
| Show Genres | On/Off |
| Show Radio | On/Off |

### Accessibility
| Setting | Effect |
|---|---|
| Larger Text | 20% text size increase |
| Bold Text | Bold weight throughout |
| Reduce Motion | Disables animations |

### Offline Queue Status
- Shows count of **pending actions** (stars/scrobbles queued while offline).
- **"Sync Now"** button to flush pending actions.
- **"Retry Failed"** / **"Clear Failed"** for failed sync actions.

---

## 19. CarPlay

### Tab Bar
CarPlay shows 4 tabs: **Library**, **Playlists**, **Radio** (if enabled), **Search**.

### Library Browsing
1. Open Library → see Artists, Albums, Recently Added, Favorites, Random, Genres.
2. Tap Artists → alphabetical list with section index.
3. Tap an artist → see albums → tap album → see tracks.
4. Tap a track to play.
5. **"Start Radio"** option available per artist.

### Now Playing
1. Start playback from CarPlay.
2. Now Playing template shows: artwork, title, artist, progress bar.
3. Controls: play/pause, skip forward/back, scrub.
4. Metadata updates on track change.

### Search
1. Tap Search tab.
2. Use CarPlay keyboard to type a query.
3. Results appear categorized.
4. Tap a result to play.

### Disconnect Recovery
1. Start playback via CarPlay.
2. Disconnect (unplug cable).
3. Verify playback continues on phone speaker/Bluetooth.
4. Reconnect — CarPlay should restore Now Playing state.

---

## 20. macOS-Specific Features

### Layout
- **NavigationSplitView** with sidebar listing all sections.
- Sidebar items: Library, Artists, Albums, Genres, Favorites, Playlists, Radio, Downloads, Settings.

### Keyboard Shortcuts
| Shortcut | Action |
|---|---|
| Cmd+P | Play / Pause |

### Window Behavior
- Fullscreen toggle in Now Playing toolbar.
- Window title updates with now-playing info.
- `.sheet` used instead of `.fullScreenCover` (macOS doesn't support fullscreen covers).

### Visualizer
- Opens in a separate window (not fullscreen cover).
- Metal shader rendering in its own window.

---

## 21. Accessibility

### VoiceOver
- All controls have descriptive labels.
- Play/Pause announces state ("Playing" / "Paused").
- Shuffle/Repeat announce current state ("On" / "Off").
- Star button announces ("Add to Favorites" / "Remove from Favorites").
- Track rows announce title, artist, duration.

### Dynamic Type
- Enable larger text in Settings > Accessibility.
- All text should scale without clipping or overlap.

### Reduce Motion
- Enable in Settings > Accessibility.
- Animations replaced with dissolves or removed.

---

## Quick Test Checklist (ﾉ◕ヮ◕)ﾉ*:・゚✧

Use this for a fast smoke test covering the critical path:

- [ ] Sign in to server
- [ ] Browse artists → open an artist → open an album
- [ ] Play a song — audio works
- [ ] Mini player appears on other screens
- [ ] Open Now Playing — all controls visible
- [ ] Next/Previous work
- [ ] Shuffle toggle works
- [ ] Repeat cycle works (Off → All → One)
- [ ] Seek via progress bar
- [ ] Open Queue — shows tracks, reorder works
- [ ] Search finds results
- [ ] Open a playlist — Play All works
- [ ] Download a song — completes, plays offline
- [ ] Star a song — heart fills pink
- [ ] Open Lyrics — displays if available
- [ ] Open Visualizer (iOS) — Metal shaders render
- [ ] Open EQ — sliders respond, presets apply
- [ ] Sleep timer — set 1 min, volume fades and pauses
- [ ] Start Artist Radio — queue fills, plays continuously
- [ ] Change theme/accent color — UI updates immediately
- [ ] Settings persist after app restart

---

## Known Limitations

1. **EQ streaming buffer delay** — streaming tracks play via gapless while buffering, then switch to EQ mode once the temp file is ready.
2. **CarPlay requires Apple entitlement** — must be approved before testing on real car.
3. **Gapless gaps on transcoded streams** — server-side transcoding may introduce small gaps.
4. **Visualizer iOS only** — macOS uses a separate window, not fullscreen cover.
5. **Radio depends on server API** — `getSimilarSongs2` may return empty on some servers.

---

✧･ﾟ:*✧･ﾟ:*
