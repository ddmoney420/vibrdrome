# 09 — Real-Device User Testing Plan

This document defines the procedures, checklists, and tools for testing Vibrdrome on physical devices prior to release. It covers installation methods, CarPlay validation, structured functional tests, bug reporting, and debug tooling.

---

## A) Installation Methods

### 1. Xcode Direct Install (Development)

**Requirements:** Mac with Xcode 26.2+, USB-C/Lightning cable, device registered in Apple Developer account.

**Steps:**
1. Connect device via cable. Trust the computer on the device.
2. Open `Vibrdrome.xcodeproj` in Xcode.
3. Select the connected device from the destination picker.
4. Set the signing team under Signing & Capabilities (automatic signing recommended for development).
5. Press Cmd+R to build and run.
6. On first install, the device may prompt to trust the developer profile: Settings > General > VPN & Device Management.

**Notes:**
- Fastest iteration cycle for developers.
- Debugger and console output available in real time.
- CarPlay entitlement must be restored after every `xcodegen` run (it clears entitlements).

### 2. TestFlight Distribution

**Requirements:** Apple Developer Program membership, App Store Connect access.

**Steps:**
1. Archive the app in Xcode (Product > Archive).
2. Upload to App Store Connect via the Organizer or `xcrun altool`.
3. In App Store Connect, navigate to the TestFlight tab.
4. Add internal testers (up to 25, same App Store Connect team) or external testers (up to 10,000).
5. External testing requires a brief App Review approval (usually < 24 hours).
6. Testers receive an email invitation and install via the TestFlight app.

**Notes:**
- Best option for distributing to non-technical testers.
- Crash reports and feedback collected automatically.
- Each build expires after 90 days.
- CarPlay entitlement must be approved by Apple before TestFlight builds can exercise CarPlay features.

### 3. Ad Hoc Distribution

**Requirements:** Apple Developer Program membership, UDID of each target device (up to 100 per year).

**Steps:**
1. Collect each tester's UDID. (Settings > General > About > tap Serial Number, or use Apple Configurator / Xcode Devices window.)
2. Register each UDID in the Apple Developer portal under Devices.
3. Create (or regenerate) an Ad Hoc provisioning profile that includes the registered devices.
4. Archive the app and export with the Ad Hoc profile (Organizer > Distribute App > Ad Hoc).
5. Distribute the resulting `.ipa` via direct transfer, a file share, or an OTA manifest plist hosted on HTTPS.
6. Testers install by opening the `.ipa` in Finder (drag to device in Xcode/Apple Configurator) or tapping the OTA link.

**Notes:**
- No App Review required. Useful for quick builds to a small group.
- The 100-device limit resets annually at the start of the membership year.
- Does not include automatic crash reporting; testers must capture logs manually or use the debug tools described in Section E.

---

## B) CarPlay Testing

### Real Car Testing

**USB (Wired) CarPlay:**
1. Connect iPhone to the car's USB port with a certified cable.
2. Accept the CarPlay prompt on the car's head unit.
3. Vibrdrome should appear in the CarPlay app grid (audio category).

**Wireless CarPlay:**
1. Ensure Bluetooth is enabled on both the phone and the head unit.
2. On the iPhone, go to Settings > General > CarPlay, select the vehicle, and enable wireless.
3. On subsequent drives, CarPlay connects automatically when the phone is near the vehicle.

**Key considerations:**
- Test with the phone locked (screen off) to verify background audio works.
- Test plugging in mid-playback and unplugging mid-playback.
- Verify Siri voice commands trigger the correct Vibrdrome responses (if applicable).
- Test with both the car's built-in speakers and Bluetooth audio simultaneously connected.

### Xcode CarPlay Simulator

For development without access to a physical car:

1. Connect a real iPhone to the Mac via USB.
2. In Xcode, go to Window > Devices and Simulators.
3. Select the connected device, then click "CarPlay" in the sidebar (or use the CarPlay Simulator app from Additional Tools for Xcode).
4. The CarPlay dashboard appears on the Mac screen, mirroring what the car's head unit would display.

**Limitations:**
- Does not test actual audio routing through car speakers.
- Does not test Bluetooth/USB connection edge cases.
- Useful primarily for UI layout and template navigation validation.

### CarPlay Testing Scenarios

| # | Scenario | Verify |
|---|----------|--------|
| 1 | Open Vibrdrome from CarPlay app grid | Tab bar loads (Browse, Search, Favorites, Now Playing) |
| 2 | Browse artists > select album > play song | Playback starts, Now Playing template updates |
| 3 | Use CarPlay search | Results appear, selecting a result starts playback |
| 4 | Skip forward/back from Now Playing controls | Correct track advances, artwork updates |
| 5 | Disconnect cable mid-playback | Playback continues on phone speaker/Bluetooth |
| 6 | Reconnect cable after disconnect | CarPlay UI restores, Now Playing reflects current state |
| 7 | Cold launch via CarPlay (app not running) | App initializes, credentials load, browsing works |
| 8 | Interact with phone while CarPlay active | CarPlay UI remains functional independently |

---

## C) Structured Test Checklist

### C.1 Authentication (5 tests)

- [ ] **AUTH-01: Successful login** — Enter valid server URL, username, and password. Verify the app connects, shows the library, and persists credentials across app restart.
- [ ] **AUTH-02: Wrong password** — Enter correct URL and username but wrong password. Verify a clear error message appears and the user remains on the login screen.
- [ ] **AUTH-03: Server URL formats** — Test with `https://music.example.com`, `http://192.168.1.100:4533`, `https://example.com/navidrome` (path suffix), and a URL with a trailing slash. All valid formats should connect successfully.
- [ ] **AUTH-04: Logout** — Sign out from Settings. Verify credentials are cleared (Keychain + UserDefaults), the login screen appears, and no cached data is accessible.
- [ ] **AUTH-05: Multi-server switch** — Add two Navidrome servers. Switch between them. Verify the library updates to reflect the active server's content and the previous server's data is not mixed in.

### C.2 Browsing (5 tests)

- [ ] **BROWSE-01: Artists list** — Open the Artists tab. Verify artists load, are sorted alphabetically, and display album counts. Scroll to the bottom to confirm all artists render.
- [ ] **BROWSE-02: Albums list** — Open the Albums tab. Verify album artwork loads (via NukeUI), titles and artist names display correctly, and tapping an album opens the track list.
- [ ] **BROWSE-03: Genres** — Open the Genres tab. Verify genre names load. Tap a genre to confirm it shows the correct albums/songs.
- [ ] **BROWSE-04: Playlists** — Open the Playlists tab. Verify user playlists load with correct song counts. Tap a playlist to confirm tracks match the server.
- [ ] **BROWSE-05: Search** — Type a partial artist name, album title, and song title. Verify results appear promptly (< 2 seconds), are categorized correctly, and tapping a result navigates to the correct detail view.

### C.3 Playback (8 tests)

- [ ] **PLAY-01: Play and pause** — Tap a song to start playback. Verify audio plays through the device speaker or connected audio output. Tap pause; verify audio stops and resumes at the same position on play.
- [ ] **PLAY-02: Next and previous** — During playback, tap next. Verify the next song in the queue plays. Tap previous within the first 3 seconds; verify it goes to the previous song. Tap previous after 3 seconds; verify it restarts the current song.
- [ ] **PLAY-03: Shuffle** — Enable shuffle mode. Play through several tracks. Verify the playback order is randomized and all tracks in the queue eventually play without repetition (until the queue is exhausted).
- [ ] **PLAY-04: Repeat modes** — Cycle through repeat modes: Off, Repeat All, Repeat One. Verify Off stops at end of queue, Repeat All loops back to the first track, and Repeat One replays the current track indefinitely.
- [ ] **PLAY-05: Queue add and remove** — From a song's context menu, add to queue (end) and add as next. Verify queue order. Remove a song from the queue; verify it disappears and playback continues uninterrupted.
- [ ] **PLAY-06: Queue reorder** — Open the queue view. Drag a song to a new position. Verify the queue reflects the new order and the currently playing song is unaffected.
- [ ] **PLAY-07: Mini player** — While playing, navigate away from Now Playing. Verify the mini player appears at the bottom, shows the correct song title and artwork, and responds to play/pause taps.
- [ ] **PLAY-08: Seek** — Drag the seek bar to a new position. Verify playback jumps to the correct timestamp. Test seeking near the beginning (0:01) and near the end (last 5 seconds).

### C.4 Downloads (4 tests)

- [ ] **DL-01: Download single song** — Tap the download button on a song. Verify the progress indicator appears, the song saves to local storage, and the download icon updates to indicate completion.
- [ ] **DL-02: Download album** — Tap the download button on an album. Verify all tracks begin downloading, progress is shown per-track, and the album is marked as downloaded when complete.
- [ ] **DL-03: Offline playback** — Enable airplane mode. Navigate to downloaded content. Verify downloaded songs play without error. Verify non-downloaded content shows an appropriate offline indicator.
- [ ] **DL-04: Delete downloads** — Delete a downloaded song and a downloaded album. Verify the files are removed from local storage, the download icons reset, and storage usage decreases.

### C.5 CarPlay (5 tests)

- [ ] **CP-01: Browse library** — Open Vibrdrome on CarPlay. Navigate through Artists > Albums > Songs. Verify lists load, artwork appears, and navigation depth works correctly.
- [ ] **CP-02: Now Playing** — Start playback from CarPlay. Verify the Now Playing template shows correct song title, artist, album artwork, and playback controls respond (play/pause, skip, scrub).
- [ ] **CP-03: Search** — Use CarPlay search to find a song by title. Verify results appear and selecting one starts playback.
- [ ] **CP-04: Favorites** — Open the Favorites tab on CarPlay. Verify starred songs appear. Star/unstar from the phone app and confirm CarPlay reflects the change on next visit.
- [ ] **CP-05: Disconnect recovery** — Disconnect CarPlay mid-playback. Verify audio continues on the phone. Reconnect CarPlay. Verify the Now Playing template shows the correct current track and state.

### C.6 Settings (3 tests)

- [ ] **SET-01: Theme and accent color** — Change the app's color theme and accent color in Settings. Verify the UI updates immediately and the preference persists after app restart.
- [ ] **SET-02: Bitrate / streaming quality** — Change the streaming bitrate (e.g., 128 kbps to 320 kbps). Play a song. Verify the stream uses the new bitrate (check via debug tools or network inspector).
- [ ] **SET-03: Sign out** — Tap Sign Out. Verify credentials are cleared, the login screen appears, and re-launching the app does not auto-login.

### C.7 Performance Tests (5 tests)

- [ ] **PERF-01: Large library (10,000+ songs)** — Connect to a Navidrome server with 10,000+ songs. Browse artists, albums, and search. Verify the app remains responsive (no hangs > 1 second). Measure initial library load time.
- [ ] **PERF-02: Background playback stability (30+ minutes)** — Start playback and lock the device. Leave it playing for at least 30 minutes. Verify playback does not stop, skip unexpectedly, or consume excessive battery. Check that the lock screen controls remain functional.
- [ ] **PERF-03: Memory usage during extended browsing** — Browse the library continuously for 10 minutes (open artist pages, album details, scroll through large lists, load artwork). Monitor memory in Xcode Instruments. Verify memory stays below 200 MB and no unbounded growth occurs.
- [ ] **PERF-04: Concurrent downloads (50+ songs)** — Queue 50+ songs for download simultaneously. Verify the download manager processes them without crashing, progress UI updates correctly, and completed files are playable.
- [ ] **PERF-05: CarPlay responsiveness** — While playing music and browsing on CarPlay, verify list scrolling is smooth, template transitions take < 0.5 seconds, and there is no audio interruption during UI navigation.

### C.8 Accessibility Tests (5 tests)

- [ ] **A11Y-01: VoiceOver full navigation** — Enable VoiceOver. Navigate through every major screen (Login, Browse, Albums, Now Playing, Queue, Settings, Downloads). Verify all elements have descriptive labels, actions are announced, and no elements are unreachable.
- [ ] **A11Y-02: Dynamic Type at largest size** — Set the system text size to the largest accessibility size (Settings > Accessibility > Display & Text Size > Larger Text). Verify all text is readable, no text is clipped or overlapping, and the layout adapts gracefully.
- [ ] **A11Y-03: Bold Text** — Enable Bold Text (Settings > Accessibility > Display & Text Size > Bold Text). Verify all text renders in bold, the layout does not break, and no text overflows its container.
- [ ] **A11Y-04: Reduce Motion** — Enable Reduce Motion (Settings > Accessibility > Motion > Reduce Motion). Verify animations are replaced with dissolves or eliminated, and the app remains fully functional.
- [ ] **A11Y-05: Switch Control basic navigation** — Enable Switch Control with a single switch (auto-scan). Verify the scan order follows a logical reading path, all interactive elements are reachable, and playback controls can be activated.

---

## D) Bug Capture Template

Use the following template when filing bugs. Copy this block and fill in each field.

```markdown
## Bug Report

**Title:** [Short, descriptive title — e.g., "Playback stops after 15 minutes in background"]

**Steps to Reproduce:**
1. [First step]
2. [Second step]
3. [Continue as needed]

**Expected Result:**
[What should happen]

**Actual Result:**
[What actually happened — be specific about error messages, visual glitches, or incorrect behavior]

**Device:**
- Model: [e.g., iPhone 15 Pro]
- OS Version: [e.g., iOS 18.3.1]
- App Version: [e.g., 1.0.0 (build 42)]
- CarPlay: [Yes/No — if Yes, specify head unit model or Xcode simulator]

**Severity:**
- [ ] **Critical** — App crashes, data loss, or complete feature failure
- [ ] **High** — Major feature broken but workaround exists
- [ ] **Medium** — Minor feature broken or significant UI issue
- [ ] **Low** — Cosmetic issue, typo, or minor inconvenience

**Screenshots / Video:**
[Attach screenshots or screen recordings. For CarPlay bugs, capture the head unit display if possible.]

**Logs:**
[Paste relevant console output or attach the exported log file from the debug screen (see Section E).]

**Additional Context:**
[Network conditions (Wi-Fi/cellular/offline), audio output (speaker/Bluetooth/CarPlay), any other relevant state.]
```

### Severity Guidelines

| Severity | Definition | Examples | Response |
|----------|-----------|----------|----------|
| Critical | App crash, data loss, security issue | Crash on launch, credentials exposed, downloaded files deleted | Fix immediately, block release |
| High | Major feature unusable | Playback won't start, CarPlay blank screen, downloads always fail | Fix before release |
| Medium | Feature partially broken, UI incorrect | Wrong artwork on one screen, search missing some results | Fix if time permits |
| Low | Cosmetic, minor polish | Alignment off by a few pixels, animation stutter | Backlog for next release |

---

## E) Debug Tools

Vibrdrome includes a debug screen accessible only in development builds (`#if DEBUG`). It is designed to help testers and developers diagnose issues without requiring Xcode attachment.

### Accessing the Debug Screen

Navigate to Settings > scroll to the bottom > tap "Debug Info" (visible only in DEBUG builds).

### Debug Screen Sections

**1. Server Connection**
- Current server URL and authenticated username.
- Connection status indicator (connected / disconnected / error).
- Last successful API call timestamp.
- Subsonic API version reported by the server.

**2. Cache Management**
- NukeUI image cache size (disk + memory) in MB.
- SwiftData persistent store size.
- Downloaded audio files total size.
- "Purge Image Cache" button — clears NukeUI disk and memory caches.
- "Clear All Downloads" button — removes all downloaded audio files and resets SwiftData download records.

**3. Audio Session**
- Current AVAudioSession category and mode.
- Active audio route (built-in speaker, Bluetooth device name, CarPlay, headphones).
- Audio session interruption state (active / interrupted).
- Current playback item URL (streaming URL or local file path).
- Buffer status (seconds buffered ahead).

**4. Network Error Log**
- Scrollable list of the last 10 network errors, each showing:
  - Timestamp
  - HTTP method and URL path (query parameters redacted for security)
  - HTTP status code or error description
  - Response time in milliseconds
- Tap an entry to copy the full details to the clipboard.

**5. Export Logs**
- "Export Debug Log" button triggers a share sheet with a plain-text file containing:
  - Device model and OS version
  - App version and build number
  - Current server URL and username (password excluded)
  - Cache sizes
  - Audio session state
  - Full network error log (last 50 entries)
  - Current playback queue (song IDs and titles)
- The exported file is named `vibrdrome-debug-YYYY-MM-DD-HHmmss.txt`.
- Testers can share this file via AirDrop, email, or any share extension.

### Using Debug Tools During Testing

1. **Before starting a test session:** Open the debug screen and verify the server connection is active and the correct account is logged in.
2. **When a bug occurs:** Open the debug screen immediately and tap "Export Debug Log" before reproducing other steps, as the network error log may rotate out relevant entries.
3. **For performance issues:** Note the cache sizes and audio buffer status from the debug screen and include them in the bug report.
4. **For CarPlay issues:** The debug screen is only accessible on the phone (not on the CarPlay head unit). Check it on the phone while CarPlay is connected to see audio route information confirming CarPlay output.

---

## Appendix: Test Execution Tracker

Use this table to track test execution across devices and testers.

| Test ID | Device | Tester | Date | Pass/Fail | Bug ID (if fail) | Notes |
|---------|--------|--------|------|-----------|-------------------|-------|
| AUTH-01 | | | | | | |
| AUTH-02 | | | | | | |
| AUTH-03 | | | | | | |
| AUTH-04 | | | | | | |
| AUTH-05 | | | | | | |
| BROWSE-01 | | | | | | |
| BROWSE-02 | | | | | | |
| BROWSE-03 | | | | | | |
| BROWSE-04 | | | | | | |
| BROWSE-05 | | | | | | |
| PLAY-01 | | | | | | |
| PLAY-02 | | | | | | |
| PLAY-03 | | | | | | |
| PLAY-04 | | | | | | |
| PLAY-05 | | | | | | |
| PLAY-06 | | | | | | |
| PLAY-07 | | | | | | |
| PLAY-08 | | | | | | |
| DL-01 | | | | | | |
| DL-02 | | | | | | |
| DL-03 | | | | | | |
| DL-04 | | | | | | |
| CP-01 | | | | | | |
| CP-02 | | | | | | |
| CP-03 | | | | | | |
| CP-04 | | | | | | |
| CP-05 | | | | | | |
| SET-01 | | | | | | |
| SET-02 | | | | | | |
| SET-03 | | | | | | |
| PERF-01 | | | | | | |
| PERF-02 | | | | | | |
| PERF-03 | | | | | | |
| PERF-04 | | | | | | |
| PERF-05 | | | | | | |
| A11Y-01 | | | | | | |
| A11Y-02 | | | | | | |
| A11Y-03 | | | | | | |
| A11Y-04 | | | | | | |
| A11Y-05 | | | | | | |
