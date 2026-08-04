# Playback migration inventory (Lane 1 → Lane 2)

Source of truth for migrating the application off direct `AudioEngine.shared` access.
Regenerate the raw member sweep with:

```bash
grep -rhoE "AudioEngine\.shared\.[a-zA-Z]+" Vibrdrome | grep -v VibrdromeTests \
  | sed 's/AudioEngine.shared.//' | sort | uniq -c | sort -rn
```

## The headline number

`AudioEngine` exposes **101 members**. A sweep of all **194 production call sites** shows only
**32 distinct members are ever called**. The façade covers those, plus the members reached only
through local aliases (see below). The rest are internal implementation detail — observers, timers,
task dictionaries, private queue bookkeeping — and are deliberately *not* API.

**Aliases are the trap.** Ten in-scope files did `let engine = AudioEngine.shared` and then used
`engine.member`. Grepping only for `AudioEngine.shared.member` finds 19 members; enumerating through
the aliases as well brings the real total to **40 distinct members**. Missing that gap caused a full
revert of the first Lane 2A attempt. Any future sweep must enumerate both forms.

## Classified surface

| Class | Members reached by production callers | Destination after Lane 3 |
|---|---|---|
| 1. Core transport | `play` (57 calls), `pause`, `resume`, `stop`, `togglePlayPause`, `next`, `previous`, `seek`, `skipToIndex` | **Persistent engine** for supported non-live sources |
| 2. Queue management | `addToQueue`, `addToQueueNext`, `updateQueueSongStarred`, `updateQueueSongRating`, `clearQueue`, `removeFromQueue`, `moveInUpNext` | **Persistent engine** (queue model already exists) |
| 3. Playback state | `isPlaying`, `currentSong`, `currentTime`, `smoothCurrentTime`, `isBuffering`, `duration`, `effectiveDuration`, `queue`, `currentIndex`, `upNextEntries`, `nextSongIndex`, `playingFromContext` | Split: transport state from engine, `playingFromContext` stays application |
| 4. Repeat and shuffle | `toggleShuffle`, `cycleRepeatMode`, `shuffleEnabled`, `repeatMode` | **Persistent engine** (implemented and tested) |
| 5. Radio / live | `startRadio`, `startRadioFromSong`, `startSongSimilarityMix`, `playRadio`, `stopRadioMode`, `isRadioMode`, `currentRadioStation`, `radioSeedArtistName` | **Legacy AVQueuePlayer** — a live stream has no finite timeline to schedule |
| 6. Predownload | `predownloadStatus`, `predownloadSpeed`, `predownloadsPending`, `prepareLookahead` | **Shared service** — distinct from the persistent preparation window |
| 7. Crossfade | (no direct production call sites) | Legacy; persistent path keeps crossfade disabled |
| 8. ReplayGain / EQ | `eqEnabled`, `applyEQToggle`, `volume`, `userVolume`, `playbackRate`, `applyEffectiveVolume` | **Persistent engine** has both stages; settings stay application |
| 9. Visualizer | `visualizerActive` (feed reached via engine tap, not by name) | **Persistent engine** feed |
| 10. Now Playing | internal to `AudioEngine` | `GaplessNowPlayingBridge` after Lane 3 |
| 11. Scrobbling / history | `recentlyPlayed`, `addRandomSongPlayed` | Reporter moves; history stays application |
| 12. Diagnostics | Debug screen only (`activePlayer`) | **Permanent direct-access exception** |
| 13. Lifecycle | `restorePlayQueue` | Application + restoration coordinator |
| 14. Internal detail | ~61 members: `removeCurrentTimeObserver`, `removeItemEndObserver`, `removeLookaheadEndObserver`, smart-shuffle caches, radio task handles, skip-id sets | **Not exposed.** Stays private to the legacy implementation |

---

# Lane 2A phase 3 — view call-site migration (done)

The 33 view-layer files below now reach playback through `ApplicationPlayback.shared`. The
production path is unchanged in behaviour:

```
Views → ApplicationPlayback.shared → LegacyAudioEngineAdapter → AudioEngine.shared → AVQueuePlayer
```

## Phase 2 was skipped

Recorded outcome: **SKIPPED — the compiler type-check failure did not reproduce.**

`MiniPlayerView.swift` and `QueueView.swift` were reported to fail with
`error: the compiler is unable to type-check this expression in reasonable time` once `AudioEngine`
became `any ApplicationPlaybackControlling`. Both files were flipped to the existential and rebuilt
full-module on both platforms with
`-Xfrontend -warn-long-function-bodies=400 -Xfrontend -warn-long-expression-type-checking=400`:

| Body | iOS | macOS |
|---|---|---|
| `QueueView.body` | < 400 ms | < 400 ms |
| `MiniPlayerView.body` | < 400 ms | < 400 ms |
| `MacMiniPlayerView.body` | — | 459 ms |
| `PopOutPlayerView.body` | — | < 400 ms |

Both targets reported `** BUILD SUCCEEDED **`. For scale, bodies that compile without complaint in
the same module: `ArtistsView.body` 2511 ms, `FilterMultiSelectList.body` 1874 ms,
`NowPlayingView.body` 952 ms, `LibraryFilterSidebarView.body` 801 ms. The worst of the two reported
hotspots is more than five times *under* a body the compiler already accepts, so no restructuring of
`MiniPlayerView`, `MacMiniPlayerView`, `PopOutPlayerView` or `QueueView` was justified. A speculative
SwiftUI refactor of layout-critical player and queue UI was not performed.

## Reference counts

| | Before | After |
|---|---|---|
| `AudioEngine.shared` in the 33 migrated files | **104** | **0** |
| `ApplicationPlayback.shared` in the 33 migrated files | 0 | **104** |
| Typed properties (`: AudioEngine` → `: any ApplicationPlaybackControlling`) | 0 | **17** |
| `AudioEngine.shared` repository-wide (excluding tests) | 200 | **96** |

The substitution is exactly 1:1 — 104 references out, 104 in — so no call site was lost or doubled.

## Files migrated

| File | `AudioEngine.shared` before | after |
|---|---|---|
| `Features/Downloads/DownloadsView.swift` | 3 | 0 |
| `Features/Library/AlbumDetailView.swift` | 7 | 0 |
| `Features/Library/AlbumsView.swift` | 4 | 0 |
| `Features/Library/ArtistDetailView.swift` | 5 | 0 |
| `Features/Library/BookmarksView.swift` | 1 | 0 |
| `Features/Library/FavoritesView.swift` | 3 | 0 |
| `Features/Library/FolderDetailView.swift` | 3 | 0 |
| `Features/Library/LibraryView.swift` | 4 | 0 |
| `Features/Library/MacHomeView.swift` | 1 | 0 |
| `Features/Library/MacHomeViewModel.swift` | 5 | 0 |
| `Features/Library/MacTrackTableRow.swift` | 5 | 0 |
| `Features/Library/SongDetailView.swift` | 1 | 0 |
| `Features/Library/SongsView.swift` | 4 | 0 |
| `Features/Player/LyricsView.swift` | 1 | 0 |
| `Features/Player/MiniPlayerView.swift` | 9 | 0 |
| `Features/Player/NowPlayingView.swift` | 1 | 0 |
| `Features/Player/NowPlayingView+iOS.swift` | 1 | 0 |
| `Features/Player/QueueView.swift` | 1 | 0 |
| `Features/Player/SidePanels.swift` | 4 | 0 |
| `Features/Playlists/PlaylistDetailView.swift` | 9 | 0 |
| `Features/Playlists/PlaylistsView.swift` | 4 | 0 |
| `Features/Playlists/SmartPlaylistView.swift` | 1 | 0 |
| `Features/Radio/RadioView.swift` | 1 | 0 |
| `Features/Radio/StationSearchView.swift` | 1 | 0 |
| `Features/Search/SearchView.swift` | 1 | 0 |
| `Features/Settings/PlayerSettingsView.swift` | 1 | 0 |
| `Features/Settings/ServerManagerView.swift` | 2 | 0 |
| `Features/Settings/SettingsView.swift` | 1 | 0 |
| `Features/Visualizer/VisualizerView.swift` | 1 | 0 |
| `Shared/Components/AlbumGridCard.swift` | 6 | 0 |
| `Shared/Components/BatchActionBar.swift` | 1 | 0 |
| `Shared/Components/TrackContextMenu.swift` | 4 | 0 |
| `Shared/Components/TrackRow.swift` | 8 | 0 |

`Features/Downloads/DownloadsView.swift` still names the type twice, for the **static** constants
`AudioEngine.predownloadedCategory` and `AudioEngine.predownloadedCacheTimeMins`. Those are
type-level values, not instance members, so they are not façade candidates and are not counted as
direct singleton access.

## Held back from the 39-file grep scope

The scope grep returns 39 files. Six of them are not view-layer code and were deliberately **not**
migrated:

| File | Refs | Why held |
|---|---|---|
| `CarPlay/CarPlaySceneDelegate.swift` | 4 | A scene delegate — scene/lifecycle coordinator, and its `restorePlayQueue` call is cold-launch restoration. Belongs with lane 2D, not the view lane. |
| `Core/Audio/AudioSession.swift` | 4 | Implements the interruption pause/resume policy, which this lane is explicitly forbidden to change. |
| `Core/Audio/EQEngine.swift` | 6 | Engine collaborator, not application code. |
| `Core/Audio/NowPlayingManager.swift` | 2 | Engine collaborator. |
| `Core/Audio/SleepTimer.swift` | 2 | Engine collaborator. |
| `Core/Audio/CrossfadeController.swift` | 1 | Engine collaborator; four of its six `AudioEngine` references are static factory calls that cannot move at all. |

The façade is *application*-facing by construction — the documented path starts at **Views**.
Routing `AudioEngine`'s own collaborators back through it would invert the dependency, and once the
Lane 3 selector lands it would send implementation-internal calls through engine selection. These
five `Core/Audio/*` files are legacy-implementation peers and should move (or not) with Lane 3.

## Grep-scope defect worth knowing

The scope grep excludes `ContentView\.swift` **unanchored**, so it also silently swallows
`Features/Library/SidebarContentView.swift` (3 references) — a genuine view file that nothing has
consciously deferred. Anchor the pattern, or name the file explicitly, before the next lane.

## Remaining direct references by subsystem

96 references remain outside the migrated view layer (occurrence counts, not line counts):

| Subsystem | Files | Refs | Lane |
|---|---|---|---|
| CarPlay | `CarPlay/CarPlayManager.swift` (19), `CarPlay/CarPlaySceneDelegate.swift` (4) | 23 | 2C |
| Legacy implementation | `Core/Audio/EQEngine.swift` (6), `AudioEngine+Predownload.swift` (6), `AudioSession.swift` (4), `SleepTimer.swift` (2), `NowPlayingManager.swift` (2), `CrossfadeController.swift` (1) | 21 | 3 |
| Scene and lifecycle | `Vibrdrome.swift` (15), `Features/Library/ContentView.swift` (1), `Features/Library/MacContentView.swift` (1) | 17 | 2D |
| Watch session | `Core/Networking/WatchSessionManager.swift` | 9 | 2C |
| Remote commands | `Core/Audio/RemoteCommandManager.swift` | 8 | 2B |
| Siri / App Intents | `App/AppIntents.swift` | 6 | 2C |
| The façade itself | `Application/LegacyAudioEngineAdapter.swift` (3), `Application/ApplicationPlaybackControlling.swift` (1) | 4 | — (by design) |
| Sidebar view (grep artifact) | `Features/Library/SidebarContentView.swift` | 3 | next views pass |
| Debug screen | `Features/Settings/DebugView.swift` | 3 | **permanent exception** |
| Persistent engine | `Gapless/GaplessRemoteCommandCoordinator.swift` (1), `Gapless/GaplessEQStage.swift` (1) | 2 | — |

`DebugView` keeps `AudioEngine.shared.activePlayer` permanently. `activePlayer` returns the
`AVQueuePlayer` itself; exposing it on the façade would leak the legacy implementation object
through the seam and defeat the point of having one.

## Type-check instrumentation

The 400 ms threshold is **diagnostic, not a gate**. Slowest bodies among the migrated files, before
and after migration (macOS full-module, the platform with the largest bodies):

| Body | Before | After | Δ |
|---|---|---|---|
| `NowPlayingView.body` | 952 ms | 980 ms | +28 ms |
| `SongsView.decoratedView` | 598 ms | 637 ms | +39 ms |
| `SongsView` (expression, `:111`) | 597 ms | 636 ms | +39 ms |
| `MacMiniPlayerView.body` | 459 ms | 473 ms | +14 ms |

No migrated file exceeded 400 ms on iOS. No body timed out on any platform, and every delta is
within 3–7% — nowhere near the 2511 ms the compiler already accepts elsewhere in this module. No
refactor was triggered.

## Lane 2 batches

1. **Views** — *done* (this phase): 33 files, the largest group and the lowest risk.
2. **RemoteCommandManager** — one command per press is the property to preserve; migrate alone.
3. **CarPlay, Watch, Siri** — out-of-process callers; migrate together, each verified separately.
4. **Scene entry and lifecycle** — restoration and cold launch; migrate last, because the Build 60
   zero-activation behaviour depends on it.

Every remaining call site still calls the singleton directly, and the façade reads the same object,
so the two cannot disagree.
