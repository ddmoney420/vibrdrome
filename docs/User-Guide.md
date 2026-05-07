# Vibrdrome User Guide

Vibrdrome is a native iOS and macOS music player for Navidrome and other Subsonic-compatible servers. Connect to your self-hosted music server and enjoy your library on the go, including in the car via CarPlay.

## Initial Setup

1. Launch Vibrdrome.
2. Open the **Settings** tab.
3. Tap **Add Server**.
4. Enter your server details:
   - **URL**: Your Navidrome server address (e.g., `https://your-server.example.com`). Include the `https://` prefix.
   - **Username**: Your Navidrome username.
   - **Password**: Your Navidrome password.
5. Tap **Test Connection** to verify, then **Save**.

Your credentials are stored securely in the iOS/macOS Keychain.

## Browsing Your Library

The **Library** tab is the main way to explore your music:

- **Artists** -- Browse all artists alphabetically.
- **Albums** -- Browse all albums. Tap an album to see its tracks.
- **Recent** -- Albums you played recently.
- **Frequent** -- Your most-played albums.
- **Random** -- A randomized selection of albums from your library.

Use the **Search** tab to find artists, albums, or songs by name.

Use the **Playlists** tab to view and manage your server-side playlists.

## Playback

- **Play a song**: Tap any song to start playback. The remaining songs in the list are added to your queue.
- **Mini player**: Appears at the bottom of the screen during playback. Tap it to open the full-screen player. On iPad it stays pinned to the bottom even when the floating keyboard is up.
- **Full-screen player**: Shows album art, playback progress, and controls. Swipe down to dismiss.
- **Queue**: Tap the queue icon in the player to view and reorder upcoming tracks.
- **Shuffle**: Tap the shuffle icon to randomize your queue.
- **Repeat**: Tap the repeat icon to cycle through off, repeat all, and repeat one.
- **Radio Mix**: Open the player toolbar and tap the Radio Mix button to queue up songs similar to the one currently playing. Rearrange or hide toolbar items in **Settings > Player > Now Playing Toolbar**.

## Get Info

Long-press any song, album, or artist and choose **Get Info** to inspect its metadata:

- **Overview** tab: cover art, title, year, duration, bitrate/format, ReplayGain, MusicBrainz and Last.fm links.
- **Raw Metadata** tab: the full Subsonic API response plus Navidrome file tags (rawTags) for deeper diagnostics.

On iOS, Get Info opens as a sheet. On macOS it opens its own window, so you can have several open at once while you keep browsing.

## macOS Keyboard Shortcuts

- **⌘K** -- Go to Search tab.
- **⌘F** -- Focus the search bar in the current view.

Both shortcuts are listed in the **Navigate** menu in the menu bar. CMD+F is intercepted before AppKit's Find panel can claim it, so it focuses Vibrdrome's search instead of making a beep.

## Downloads (Offline Playback)

- **Download a song**: Long-press a song and select **Download**.
- **Download an album**: Long-press an album and select **Download Album**.
- **Manage downloads**: Open the **Downloads** tab to view downloaded content, check progress, or remove downloads.

Downloaded music plays without a network connection.

## Favorites

Star songs, albums, or artists to mark them as favorites:

- Tap the heart/star icon on any song, album, or artist.
- View all your favorites from the **Favorites** section in the Library tab.

Favorites sync with your Navidrome server, so they appear across all your Subsonic clients.

## Bookmarks

Save your position in long tracks (podcasts, audiobooks, live recordings):

- During playback, use the bookmark action to save your current position.
- Resume from a bookmark via the **Bookmarks** section.

Bookmarks sync with your server.

## Radio

Add and listen to internet radio streams:

- Go to **Radio** in the Library tab.
- Tap **Add Radio Station** and fill in the labeled sections:
  - **Name** -- the display name shown in the Radio grid.
  - **Stream URL** -- the actual audio stream (e.g. `https://example.com/stream.mp3`, or a `.pls` / `.m3u` playlist).
  - **Homepage** (optional) -- the station's website, used for the favicon and info.
- Tap a station to start streaming.
- To delete a station, long-press its card and choose **Delete Station**. This works in portrait and landscape, iPhone, iPad, and Mac.

## Settings

Access settings from the **Settings** tab:

- **Server Management** -- Add, edit, or remove servers.
- **Playback Quality** -- Set bitrate limits separately for Wi-Fi and cellular connections. Lower bitrates save data and battery; higher bitrates improve audio quality.
- **Appearance** -- Choose a theme (light, dark, or system), pick an accent color, and adjust text size via Dynamic Type. On iOS 26, enable **Liquid Glass** to give the Now Playing toolbar and mini player a frosted, glass-like background.
- **Cache** -- Clear the image or audio cache to free storage.

## CarPlay

When your iPhone is connected to CarPlay, Vibrdrome shows a dedicated CarPlay interface.

- **Artists and Albums** use two-letter drill-down for large collections: pick a first letter, then a second letter to jump straight to that slice instead of scrolling a long list.
- **Now Playing** shows shuffle, repeat, progress, and Up Next. It no longer auto-pushes on track start, so the list you were browsing stays visible.
- Playback keeps its position through short call or text interruptions: when audio resumes it seeks back to where it was before the interruption rather than restarting from 0.

## Visualizer

Open the visualizer from the Now Playing screen (waveform icon). Swipe sideways to cycle presets, swipe down to dismiss, tap once to toggle controls.

- **Spectrum / Waveform / Aurora** react to the real frequency content of the audio: bass on the left of the screen, treble on the right. Spectrum shows classic peak-hold caps floating above each bar.
- Other presets animate from an overall energy curve and still pulse with the music.
- See **Settings > Accessibility** for photosensitivity controls.

## Multi-Server Support

Vibrdrome supports multiple Navidrome servers:

1. Go to **Settings** and tap **Add Server** to add additional servers.
2. Switch between servers from the server list in Settings.
3. Each server maintains its own library, playlists, and favorites.
