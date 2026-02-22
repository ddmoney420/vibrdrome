```
 _____ ______ ______  _      _____  _   _  _____
|  _  ||  ___||  ___|| |    |_   _|| \ | ||  ___|
| | | || |_   | |_   | |      | |  |  \| || |__
| | | ||  _|  |  _|  | |      | |  | . ` ||  __|
\ \_/ /| |    | |    | |____ _| |_ | |\  || |___
 \___/ \_|    \_|    \_____/ \___/ \_| \_/\____/
```

# Offline Playlists -- Acceptance Criteria

**Feature:** Offline Playlists
**Version:** 1.0
**Date:** 2026-02-21

## Overview

Users can download entire playlists for offline playback. Downloaded playlists remain fully functional in airplane mode, including metadata display, artwork, and audio playback.

## Data Model

### OfflinePlaylist (SwiftData @Model)

- `serverId: String` -- identifies the Navidrome server
- `playlistId: String` -- server-side playlist identifier
- `playlistName: String` -- display name
- `coverArtId: String?` -- artwork reference for NukeUI disk cache
- `songIds: [String]` -- ordered list preserving playlist track order
- `cachedAt: Date` -- timestamp of last successful download
- `totalSongs: Int` -- expected track count for progress calculation
- `compositeKey: String` -- computed as `"{serverId}_{playlistId}"` for multi-server safety

### CachedSong (SwiftData @Model)

- Preserves full song metadata (title, artist, album, duration, track number, disc number, cover art ID)
- Enables offline reconstruction of playlist detail views without any network calls

## Download Flow

### DownloadManager.downloadPlaylist()

1. Fetch playlist metadata and song list from Subsonic API.
2. Persist an `OfflinePlaylist` record with ordered `songIds`.
3. Enqueue all tracks as a batch download via `DownloadManager`.
4. `DownloadManager` handles deduplication -- tracks already cached (from album downloads or other playlists) are skipped.
5. Per-playlist progress is tracked via `DownloadProgress` (completed / totalSongs).

### Deduplication

- Before enqueuing a song download, check whether the file already exists on disk.
- Shared songs across multiple offline playlists are stored once; both playlists reference the same cached file.

## Acceptance Criteria

### AC-1: Offline Rendering

- **Given** a playlist has been fully downloaded,
- **When** the device is in airplane mode and the user opens the playlist detail view,
- **Then** the playlist title, track list (with metadata), and cover art render without network calls.

### AC-2: Offline Playback

- **Given** a playlist has been fully downloaded,
- **When** the device is in airplane mode and the user taps any track,
- **Then** audio plays from the local cache with no interruption or error.

### AC-3: All Tracks Play

- **Given** a downloaded playlist with N tracks,
- **When** playback proceeds through the entire queue in airplane mode,
- **Then** all N tracks play successfully in playlist order.

### AC-4: Survives App Relaunch

- **Given** a playlist was downloaded in a previous app session,
- **When** the app is force-quit and relaunched in airplane mode,
- **Then** the offline playlist appears in the library and is fully playable.

### AC-5: Progress Tracking

- **Given** a playlist download is in progress,
- **When** the user views the playlist in the library,
- **Then** a progress indicator shows completed/total tracks updating in real time.

### AC-6: Multi-Server Safety

- **Given** two servers each have a playlist with the same `playlistId`,
- **When** both are downloaded,
- **Then** they are stored as separate `OfflinePlaylist` records keyed by `compositeKey`.

## Error Handling

- If a download fails mid-playlist, completed tracks remain cached and playable.
- Retry resumes from the first missing track, not from the beginning.
- If the playlist is deleted server-side, the offline copy persists until the user manually removes it.
