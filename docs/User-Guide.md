# Veydrune User Guide

Veydrune is a native iOS and macOS music player for Navidrome and other Subsonic-compatible servers. Connect to your self-hosted music server and enjoy your library on the go, including in the car via CarPlay.

## Initial Setup

1. Launch Veydrune.
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
- **Mini player**: Appears at the bottom of the screen during playback. Tap it to open the full-screen player.
- **Full-screen player**: Shows album art, playback progress, and controls. Swipe down to dismiss.
- **Queue**: Tap the queue icon in the player to view and reorder upcoming tracks.
- **Shuffle**: Tap the shuffle icon to randomize your queue.
- **Repeat**: Tap the repeat icon to cycle through off, repeat all, and repeat one.

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
- Tap **Add Radio Station** and enter the stream URL and a name.
- Tap a station to start streaming.

## Settings

Access settings from the **Settings** tab:

- **Server Management** -- Add, edit, or remove servers.
- **Playback Quality** -- Set bitrate limits separately for Wi-Fi and cellular connections. Lower bitrates save data and battery; higher bitrates improve audio quality.
- **Appearance** -- Choose a theme (light, dark, or system), pick an accent color, and adjust text size via Dynamic Type.
- **Cache** -- Clear the image or audio cache to free storage.

## Multi-Server Support

Veydrune supports multiple Navidrome servers:

1. Go to **Settings** and tap **Add Server** to add additional servers.
2. Switch between servers from the server list in Settings.
3. Each server maintains its own library, playlists, and favorites.
