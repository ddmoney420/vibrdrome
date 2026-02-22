```
 _____   ___  ______  _      _____  _____  _____
|  __ \ / _ \ | ___ \| |    |  ___|/  ___|/  ___|
| |  \// /_\ \| |_/ /| |    | |__  \ `--. \ `--.
| | __ |  _  ||  __/ | |    |  __|  `--. \ `--. \
| |_\ \| | | || |    | |____| |___ /\__/ //\__/ /
 \____/\_| |_/\_|    \_____/\____/ \____/ \____/
```

# Gapless Playback -- Feature Specification (⌐■_■)

**Feature:** Gapless Playback
**Version:** 1.0
**Date:** 2026-02-21

## Overview

Gapless playback eliminates audible pauses between consecutive tracks. The implementation uses `AVQueuePlayer` with a lookahead strategy that pre-loads the next track as the second item in the player queue, achieving a target of less than 50ms gap for locally cached tracks.

## Definition

**Gapless:** No intentional pause is inserted between queue items. For local (cached/downloaded) tracks, the target transition gap is under 50ms. For streamed tracks, the gap depends on network buffering but should be minimized by pre-buffering.

## Core Mechanism

### AVQueuePlayer Lookahead

- The player always contains at most two items: the currently playing item and the next item (lookahead).
- When a track begins playing, `prepareLookahead()` is called to determine and insert the next track.
- The lookahead item is added via `AVQueuePlayer.insert(_:after:)`.

### Auto-Advance Detection

- Listen for `AVPlayerItemDidPlayToEndTime` notification.
- Distinguish between **auto-advance** (track ended naturally) and **manual end** (user skipped or stopped).
- `handleAutoAdvance()` updates playback state (current index, now-playing info, UI) **without** incrementing the generation counter. This preserves the AVQueuePlayer's continuous playback -- a new generation would tear down and rebuild the player.

### prepareLookahead()

Determines the next song based on current playback mode:

| Mode | Lookahead Behavior |
|---|---|
| Normal (no repeat) | Next song in queue; none if at end |
| Repeat All | Next song in queue; wraps to first track after last |
| Repeat One | No lookahead (AVQueuePlayer is not used for repeat-one; the single item loops via `actionAtItemEnd = .none`) |
| Shuffle | Random next song from remaining unplayed tracks |

## Edge Cases

### Repeat One

- Lookahead is disabled. The current `AVPlayerItem` is set to loop by seeking back to the start on completion.
- `AVQueuePlayer` contains only one item.

### Repeat All + Last Track

- When the currently playing track is the last in the queue, lookahead wraps around and pre-loads the first track.

### Shuffle Mode

- The next shuffled track is determined at lookahead time, not at queue-build time.
- This ensures the lookahead reflects the actual next track even if shuffle order changes.

### Queue Edits

- Any modification to the playback queue (add, remove, reorder) invalidates the current lookahead.
- After a queue edit, the lookahead item is removed from `AVQueuePlayer` and `prepareLookahead()` is called again to rebuild it with the correct next track.

### Radio Streams

- Lookahead is disabled for radio/live streams (non-finite duration items).
- Standard single-item playback is used instead.

## State Management

- `AudioEngine` tracks whether the current advance was automatic or manual.
- The generation counter is only incremented on explicit user actions (play, skip, queue change) -- never on auto-advance.
- Stale callback guards remain in place: any async completion that finds a mismatched generation is discarded.

## Acceptance Criteria

- **AC-1:** Two consecutive local tracks play with no audible gap (under 50ms measured transition).
- **AC-2:** Auto-advance updates now-playing metadata correctly without restarting the player.
- **AC-3:** Repeat-all mode wraps from the last track to the first with no gap.
- **AC-4:** Repeat-one mode loops the current track seamlessly.
- **AC-5:** Editing the queue mid-playback rebuilds the lookahead without interrupting the current track.
- **AC-6:** Shuffle mode pre-loads the correct next shuffled track.
- **AC-7:** Radio streams fall back to standard playback with no lookahead errors.
