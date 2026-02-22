```
______   ___  ______  _____  _____
| ___ \ / _ \ |  _  \|_   _||  _  |
| |_/ // /_\ \| | | |  | |  | | | |
|    / |  _  || | | |  | |  | | | |
| |\ \ | | | || |/ /  _| |_ \ \_/ /
\_| \_|\_| |_/|___/   \___/  \___/
```

# Artist Radio -- Feature Specification ♪♫(◕‿◕)♫♪

**Feature:** Artist Radio (Continuous Auto-Play)
**Version:** 1.0
**Date:** 2026-02-21

## Overview

Artist Radio provides continuous auto-play seeded from an artist or track. The system builds an initial queue and automatically refills it as playback progresses, creating an endless listening experience similar to the selected artist's style.

## Radio State

The following state is managed on `AudioEngine`:

- `isRadioMode: Bool` -- whether radio mode is active
- `radioSeedArtistName: String?` -- the artist used to seed the radio session
- `radioSkippedIds: Set<String>` -- song IDs the user has blocked from future results

## Seed Strategy

When radio mode is activated, the initial queue is built using a three-tier fallback:

1. **Primary:** `getTopSongs(artist: name, count: 40)` -- fetches the artist's most popular tracks.
2. **Fallback 1:** Album sampling -- select random tracks across the artist's discography.
3. **Fallback 2:** `getRandomSongs(count: 40)` -- server-wide random tracks as a last resort.

If all three sources return empty results, display the error message: **"No radio tracks found"**.

## Queue Refill

- **Trigger:** When `currentIndex >= queue.count - 5`, initiate a refill.
- **Primary source:** `getSimilarSongs2(id: currentSongId, count: 20)`.
- **Fallback:** `getRandomSongs(count: 20)`.
- **De-duplication:** Every candidate is checked against existing queue song IDs and `radioSkippedIds`. Duplicates are discarded before appending.

## Entry Points

| Location | Action |
|---|---|
| `ArtistDetailView` | "Start Radio" button seeds from the displayed artist |
| `NowPlayingView` | "Radio" toggle in the overflow menu seeds from the current track's artist |
| `TrackContextMenu` | "Start Artist Radio" menu item seeds from the track's artist |
| `CarPlayManager` | "Artist Radio" action in CarPlay now-playing template |

## Skip and Block

- `skipAndBlock()` skips the current track and adds its ID to `radioSkippedIds`.
- The blocked song is removed from the current queue if it appears ahead of the play position.
- Blocked IDs persist for the duration of the radio session (cleared when radio mode ends).

## Behavior Rules

- Activating radio mode replaces the current playback queue.
- Exiting radio mode (toggling off, selecting a new album/playlist, or clearing the queue) resets all radio state.
- Radio mode is indicated in the UI via a visual badge on `NowPlayingView`.
- Shuffle and repeat settings are ignored while radio mode is active -- the queue order is determined by the radio algorithm.

## Error Handling

- Network errors during refill: retry once after 5 seconds, then continue playing existing queue.
- If the queue runs dry (all refill attempts failed and last track finishes), exit radio mode and stop playback.
- If all seed sources return empty on initial activation, show "No radio tracks found" and do not enter radio mode.

## Acceptance Criteria

- **AC-1:** Activating radio from an artist seeds the queue with that artist's tracks and begins playback.
- **AC-2:** Playback continues indefinitely as the queue refills automatically.
- **AC-3:** Skipped/blocked songs never reappear in the current radio session.
- **AC-4:** De-duplication prevents the same song from appearing multiple times in the queue.
- **AC-5:** All four entry points successfully start a radio session.
- **AC-6:** Exiting radio mode fully clears radio state and restores normal queue behavior.
