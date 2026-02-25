# Vibrdrome CarPlay Guide

Vibrdrome supports Apple CarPlay, giving you access to your Navidrome music library on your car's display.

## Setup

1. Connect your iPhone to your car via **USB cable** or **wireless CarPlay** (if your car supports it).
2. Vibrdrome should appear on the CarPlay home screen automatically.
3. Tap the Vibrdrome icon to launch.

No additional configuration is needed. Vibrdrome uses the same server you configured in the app.

## What You Can Do in CarPlay

### Browse
- **Artists** -- Scroll through your artist list.
- **Albums** -- Browse albums.
- **Playlists** -- Access your server-side playlists.
- **Genres** -- Browse by genre.
- **Recently Played** -- Jump back to recent music.
- **Random** -- Discover random albums from your library.
- **Favorites** -- Quick access to your starred music.

### Search
- Use the CarPlay search interface (keyboard or Siri) to find artists, albums, or songs.

### Playback Controls
- **Play/Pause** -- Tap the on-screen button or use the steering wheel play/pause button.
- **Next/Previous** -- Skip tracks via on-screen controls or steering wheel buttons.
- **Like/Dislike** -- Rate tracks from the Now Playing screen (maps to Subsonic star/unstar).

## Limitations

- **No download management** -- You cannot start or manage downloads from the CarPlay interface. Use the iPhone app for that.
- **List size cap** -- Apple limits CarPlay lists to 200 items. Large libraries are truncated. Use search to find specific content.
- **No settings access** -- Server and playback settings must be changed in the main app.

## Troubleshooting

**Vibrdrome does not appear on CarPlay:**
- Make sure you have an active CarPlay connection (USB or wireless).
- Restart your iPhone and reconnect to CarPlay.
- Check that Vibrdrome is not restricted under **Settings > General > CarPlay** on your iPhone.
- The app requires a valid CarPlay Audio entitlement in its provisioning profile.

**Playback stutters in the car:**
- Check your cellular signal. CarPlay streams music from your server in real time (unless tracks are downloaded).
- Lower the cellular bitrate limit in the Vibrdrome app settings.
- Download albums you frequently listen to in the car for offline playback.

**Controls unresponsive:**
- Try disconnecting and reconnecting CarPlay.
- Force-quit Vibrdrome on the iPhone and relaunch via the CarPlay screen.
