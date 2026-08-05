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
| `AudioEngine.shared` in the 34 migrated view files | **107** | **0** |
| `ApplicationPlayback.shared` in the 34 migrated view files | 0 | **107** |
| Typed properties (`: AudioEngine` → `: any ApplicationPlaybackControlling`) | 0 | **18** |
| `AudioEngine.shared` repository-wide (excluding tests) | 200 | **93** |

The substitution is exactly 1:1 — 107 references out, 107 in — so no call site was lost or doubled.

Phase 3 migrated 33 files (104 references). The Lane 2A closure pass added
`Features/Library/SidebarContentView.swift` (3 references, 1 typed property), which the original
unanchored scope grep had silently excluded — see below.

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
| `Features/Library/SidebarContentView.swift` | 3 | 0 |
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

## Held back — six non-view files, deliberately deferred

The scope grep returns these six alongside the views. None is view-layer code, and all are
classified below rather than left unexplained. They may continue referencing `AudioEngine.shared`.

**`CarPlaySceneDelegate` — deferred to the CarPlay lane (2C).**
**The other five — legacy implementation collaborators that must not depend on the
application-facing façade.**

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

## Grep-scope defect — found and fixed

The original scope grep excluded `ContentView\.swift` **unanchored**, so it also silently swallowed
`Features/Library/SidebarContentView.swift` — a genuine view file that nothing had consciously
deferred. Any filename *ending in* `ContentView.swift` was invisible to the sweep.

`SidebarContentView.swift` has since been migrated (3 references), and the pattern is now anchored
on a path separator so it can only match the two intentionally deferred files:

```bash
grep -rl "AudioEngine.shared" Vibrdrome VibrdromeWatch | grep -v VibrdromeTests \
  | grep -vE "RemoteCommandManager|CarPlayManager|WatchSessionManager|AppIntents|/Vibrdrome\.swift$|/ContentView\.swift$|/MacContentView\.swift$|/DebugView\.swift$|Core/Audio/AudioEngine|Core/Audio/Gapless|Core/Audio/Application"
```

`/ContentView\.swift$` matches `Features/Library/ContentView.swift` and nothing else;
`SidebarContentView.swift` no longer matches because `/Sidebar…` does not end at a path separator
before `ContentView.swift`. The same anchoring is applied to `Vibrdrome.swift`, `MacContentView.swift`
and `DebugView.swift`, each of which had the same substring hazard.

**View migration is now complete.** Every view-layer file reaches playback through
`ApplicationPlayback.shared`; the only remaining direct reference inside a view is the documented
`DebugView.activePlayer` diagnostic exception.

---

# Lane 2B — RemoteCommandManager (done)

`Core/Audio/RemoteCommandManager.swift`: **8 direct references → 0.** The route is now

```
MPRemoteCommandCenter → RemoteCommandManager → ApplicationPlayback.shared
                      → LegacyAudioEngineAdapter → AudioEngine.shared → AVQueuePlayer
```

Command availability, button presentation and status mapping are byte-for-byte unchanged: the
`isEnabled` set is identical, skip-forward/backward stay disabled so the lock screen keeps showing
next/previous, an invalid seek event still maps to `.commandFailed`, and everything else still
returns `.success`.

**What changed structurally.** Each command body moved out of its `addTarget` closure into a named
method; the closures now do nothing but call those methods. This exists so the behaviour is
reachable from a test — `MPRemoteCommandCenter` cannot invoke a registered command and
`MPRemoteCommandEvent` has no public initialiser, so without the split "one press produces exactly
one engine call" is unprovable. Registration, ownership and the single `setup()` are untouched.

**State is read live, never cached.** `playback` is a computed property resolving
`ApplicationPlayback.shared` on every access, so `currentSong` for the Like button is re-read per
press. A cached copy would favourite whatever was playing when the handler was registered. There is
a test asserting two presses produce two reads.

**Test seam.** A DEBUG-only `playbackOverride` lets tests substitute a recorder, because `resume`,
`next` and `previous` would start AVQueuePlayer — impossible while the gapless real-time suites are
running. Production never sets it and the property does not exist in release builds. A DEBUG
`registrationCount` proves the `isSetup` guard stops a second set of handlers being attached, which
is the defect that makes one lock-screen press skip two tracks.

---

# Lane 2C-A — CarPlayManager (done)

`CarPlay/CarPlayManager.swift`: **19 direct references → 0.** Route:

```
CarPlayManager → CarPlayPlaybackActions → ApplicationPlayback.shared
               → LegacyAudioEngineAdapter → AudioEngine.shared → AVQueuePlayer
```

## CarPlay has no transport handlers

Worth recording, because it answers the double-dispatch question outright: **play, pause, toggle,
next and previous never reach `CarPlayManager`.** CarPlay raises them through
`MPRemoteCommandCenter`, which `RemoteCommandManager` owns and Lane 2B already migrated. There is no
second path for a transport command to travel, so this migration cannot double-dispatch.

CarPlay's entire playback surface is: shuffle and repeat buttons, Up Next row selection, playing a
song or list from a template, artist radio, and radio stations — plus live reads of `currentSong`,
`isPlaying`, `currentTime`, `recentlyPlayed` and `upNext`.

## The `upNext` / `upNextEntries` trap

`showUpNext` reads **`upNext`**, not `upNextEntries`. They are not interchangeable:

| | `upNext` | `upNextEntries` |
|---|---|---|
| Content | `queue[(currentIndex + 1)...]` | shuffle-aware playback order |
| Shuffle | ignored | honoured |
| Cap | none | **5 entries** (`min(count, 5)`) |
| Index | caller computes | carried in the tuple |

Substituting `upNextEntries` would have silently cut CarPlay's Up Next list from up to 30 rows to 5
and reordered it whenever shuffle was on. `upNext` was therefore **added to the façade** as a
distinct member rather than folded into `upNextEntries`.

## Queue-index semantics — audited, unchanged

CarPlay's Up Next rows map positionally: row `offset` → absolute queue index
`currentIndex + 1 + offset`. Two properties are preserved deliberately:

- **`currentIndex` is read at tap time**, not when the template was built. A queue that advanced
  while the list was on screen resolves against the queue as it is now. Pre-existing behaviour.
- **Positional, never identity-based.** Two queue positions holding the same song id stay distinct;
  matching by `song.id` would collapse them onto the first occurrence.
- **No clamping is added.** An out-of-range row passes its computed index straight through to the
  engine, which owns range handling, exactly as before.

Everywhere else CarPlay plays a song it passes an explicit
`songs.firstIndex(where: { $0.id == song.id }) ?? 0` — unchanged, including its identity-based
lookup within a freshly fetched album/playlist array where ids are unique by construction.

## Test seam

`CarPlayPlaybackActions` is an `enum` of static members. `CPInterfaceController` has no public
initialiser, so `CarPlayManager` cannot be constructed in a test; every playback-triggering handler
calls one of these methods and does nothing else, so tests drive the exact code a tap runs. Static
members mean handlers reference it the way they previously referenced `AudioEngine.shared` — no
closure gains a `self` capture, so no `CPListItem` held by a template starts retaining the manager.

The DEBUG-only `playbackOverride` defaults to `nil`, falls back to `ApplicationPlayback.shared`, is
reset in teardown, does not exist in release builds, and touches neither template registration nor
scene ownership. Same pattern as `RemoteCommandManager` — deliberately one mechanism, not two.

## CarPlaySceneDelegate stays on the legacy singleton

`CarPlaySceneDelegate` keeps its **4** direct references until the scene/lifecycle lane, because its
`restorePlayQueue` call on scene connect is cold-launch restoration and belongs with that work.

So the application temporarily has:

```
CarPlayManager       → façade
CarPlaySceneDelegate → legacy singleton
```

This is safe: both routes reach the same `AudioEngine.shared`, so there is no second queue authority
and the two cannot disagree. No dependency was added from `CarPlaySceneDelegate` to `CarPlayManager`.

---

# Lane 2C-B — WatchSessionManager (done)

`Core/Networking/WatchSessionManager.swift`: **9 direct references → 0**, including all **6** local
`let engine = AudioEngine.shared` aliases. Route:

```
Watch command → WatchSessionManager → WatchPlaybackActions → ApplicationPlayback.shared
              → LegacyAudioEngineAdapter → AudioEngine.shared → AVQueuePlayer
```

`WatchSessionManager` remains the `WCSessionDelegate` and message receiver; WatchConnectivity
ownership is unchanged.

## Watch command inventory

Audited from **both** sides — the commands the watch app actually sends, and what the phone does
with them. Message key is always `command: String`; the only other payload key is `volume: Float`.

| Command | Payload | Operation | Reply |
|---|---|---|---|
| `togglePlayPause` | — | `togglePlayPause()` | `[:]` |
| `next` | — | `next()` | `[:]` |
| `previous` | — | `previous()` | `[:]` |
| `setVolume` | `volume: Float` | `volume =` | `[:]` |
| `toggleStar` | — | `OfflineActionQueue` star/unstar (no transport) | `[:]` |
| `toggleShuffle` | — | `toggleShuffle()` | `[:]` |
| `cycleRepeat` | — | `cycleRepeatMode()` | `[:]` |
| `startRadio` | — | `startRadioFromSong(currentSong)` | `[:]` |
| `playFavorites` / `shuffleFavorites` | — | fetch starred → `play(…at: 0)` | `[:]` |
| `shuffleAll` | — | fetch 50 random → `play(…at: 0)` | `[:]` |
| `playAlbum:<id>` | in the command string | fetch album → `play(…at: 0)` | `[:]` |
| `playPlaylist:<id>` | in the command string | fetch playlist → `play(…at: 0)` | `[:]` |
| `skipToIndex:<n>` | in the command string | `play(queue[currentIndex+1+n], …)` | `[:]` |
| `sleepTimer15/30/45/60`, `sleepTimerEndOfTrack`, `sleepTimerCancel` | — | `SleepTimer` (no playback) | `[:]` |

Three things this audit settled, all contrary to what the command list looks like at a glance:

- **There is no `play` and no `pause` command.** Transport is `togglePlayPause` only.
- **There is no `seek` command.** The entire protocol's only numeric payload is `setVolume`'s
  `volume`, so that is the payload surface with valid / missing / out-of-range coverage.
- **Replies are always `[:]`.** No state is ever returned in a reply. State travels *outbound* in
  the `sendNowPlayingUpdate` application context, so that is where freshness matters.

Every command is fire-and-forget: both `didReceiveMessage` overloads dispatch to `handleCommand` and
the reply variant immediately answers `[:]`. Library commands complete asynchronously after a network
fetch; the reply does not wait for them. No command triggers more than one playback operation.

## Wire contract (unchanged)

Now Playing context keys: `title`, `artist`, `album`, `isPlaying`, `elapsed`, `duration`,
`isStarred`, `isShuffleOn`, `repeatMode`, `sleepTimerActive`, `queue` (capped at 20), plus
`coverArtData` on the art-bearing overload only. Playback-state ticks: `isPlaying`, `elapsed`,
`sleepTimerActive`. Names, types and the 20-entry cap are asserted by test.

## Double-dispatch audit — clear

A Watch message and a remote-command press are **independent routes to the same engine**, and neither
crosses into the other. `WatchSessionManager` and `WatchPlaybackActions` contain no reference to
`RemoteCommandManager` or `MPRemoteCommandCenter` (the only mention is a doc comment), and
`RemoteCommandManager` is driven by system remote events, not by WatchConnectivity. A test installs a
recorder on **both** seams at once and asserts a Watch command records on the Watch seam only.

## `skipToIndex` bounds — hardened

`skipToIndex:<n>` previously guarded only the **upper** bound:

```swift
let abs = currentIndex + 1 + n
guard abs < queue.count else { return }
playback.play(song: playback.queue[abs], ...)
```

A negative `n` reached `queue[negative]` and trapped. Our own watch app only ever sends row
indices >= 0, so it was unreachable from our UI — but a watch message is a dictionary on a wire, and
`skipToIndex:-1` is as deliverable as `skipToIndex:3`.

`skipToIndexAbsolute(currentIndex:relative:)` now returns `Int?` and rejects a negative `n`, a
computed index below zero, and either addition overflowing (checked with `addingReportingOverflow`,
so `Int.min` and a `currentIndex` at `Int.max` are both handled). A rejected index performs
**nothing** — it is never clamped onto a different track, because silently playing the wrong song is
worse than ignoring an impossible request. The upper-bound no-op is unchanged, and every accepted
mapping is identical to before.

Command parsing moved into `WatchPlaybackActions.handleSkipToIndexCommand(_:)` so malformed index
text is testable. It preserves the dispatch contract exactly: text that is not a valid integer is
still *handled* — it performs nothing rather than falling through to the sleep-timer handler.

---

# Lane 2C-C — Siri and App Intents (done)

`App/AppIntents.swift`: **6 direct references → 0.** No aliases and no helper methods hid any of
them; all six were direct `AudioEngine.shared.<member>` calls, one per intent that performs playback.

```
Siri / Shortcut → App Intent → AppIntentPlaybackActions → ApplicationPlayback.shared
                → LegacyAudioEngineAdapter → AudioEngine.shared → AVQueuePlayer
```

## Execution context — verified, not assumed

`AppIntents.swift` has **exactly one build-file entry**, in the `Vibrdrome` app target's Sources
phase. The project's only app-extension target is `VibrdromeWidget`, whose sources are
`VibrdromeWidget` + `Shared` — it does not compile `Vibrdrome/App/`. **There is no App Intents
extension target.**

So the intents are compiled into the main app binary and run **in the app's own process**. The
pre-existing `AudioEngine.shared` calls did reach the app's real playback authority, and
`ApplicationPlayback.shared` now reaches the same one. There is no process boundary here and no IPC
to invent — the concern that motivated the audit does not apply to this codebase.

That holds for `TogglePlaybackIntent` and `SkipTrackIntent` too: `openAppWhenRun = false` means they
run without *foregrounding* the app, not outside it.

## Intent inventory

| Intent | Title | Parameter | Playback operation | `openAppWhenRun` | Errors | Returns |
|---|---|---|---|---|---|---|
| `PlayFavoritesIntent` | Play Favorites | — | `play(song:from:)` at 0 | `true` | `notConfigured`, `noContent` | `.result()` |
| `PlayRandomMixIntent` | Play Random Mix | — | `play(song:from:)` at 0 | `true` | `notConfigured`, `noContent` | `.result()` |
| `PlayArtistRadioIntent` | Play Artist Radio | `artistName: String` | `startRadio(artistName:)` | `true` | `notConfigured` | `.result()` |
| `TogglePlaybackIntent` | Toggle Playback | — | `togglePlayPause()` | **`false`** | none | `.result()` |
| `SkipTrackIntent` | Skip Track | — | `next()` | **`false`** | none | `.result()` |
| `PlayPlaylistIntent` | Play Playlist | `playlistName: String` | `play(song:from:)` at 0 | `true` | `notConfigured`, `playlistNotFound`, `noContent` | `.result()` |

**No intent reads or returns playback state.** Every one returns a bare `.result()` — no dialog, no
snippet, no metadata payload. There is therefore no state-bearing response surface to keep fresh, and
this lane did not create one. What is tested instead is that the *seam* resolves during `perform()`
rather than at intent construction, since the system builds intent values during Shortcuts browsing
and may run them much later.

The four content intents guard on `AppState.shared.isConfigured` and throw `IntentError` before any
network call; the two transport intents deliberately have no such guard, because pausing what is
already playing must work whether or not a server is reachable. Both behaviours are pinned by test.

`VibrdromeShortcuts` still provides exactly two phrase-backed shortcuts; `PlayPlaylistIntent`
remains deliberately phrase-less (a phrase placeholder must be an `AppEntity`/`AppEnum`, not a
`String` parameter).

## Double-dispatch result — clear

`TogglePlaybackIntent` and `SkipTrackIntent` expose the same semantic actions as the lock-screen
play/pause and next buttons, but they are separate entry points: an intent calls the façade directly
and never raises an `MPRemoteCommand`. A test installs recorders on the intent seam **and** the
remote-command seam simultaneously, performs both intents, and asserts the remote recorder stays
empty with the registration count unchanged.

---

# Lane 2D-A — CarPlaySceneDelegate (done)

`CarPlay/CarPlaySceneDelegate.swift`: **4 direct references → 0.**

```
CarPlaySceneDelegate → CarPlayScenePlaybackActions → ApplicationPlayback.shared
                     → LegacyAudioEngineAdapter → AudioEngine.shared → AVQueuePlayer
```

## Scene responsibility map

Traced from the source, not inferred from names. The whole file is 41 lines and owns exactly this:

| Responsibility | Owner |
|---|---|
| Scene connect / disconnect callbacks | `CarPlaySceneDelegate` |
| `CPInterfaceController` reference | `CarPlaySceneDelegate` (stored on connect, cleared on disconnect) |
| `CarPlayManager` construction, retention, teardown | `CarPlaySceneDelegate` |
| Templates, Up Next, list actions | `CarPlayManager` (unchanged) |
| Remote-command registration | `RemoteCommandManager.shared.setup()` — idempotent |
| Connect-time Now Playing / restore | **`CarPlayScenePlaybackActions`** (this lane) |
| `CPWindow` | **none** — a template scene delegate has no window |
| Audio-session calls | **none** |
| Async tasks, observers | **none** — `CarPlayManager` owns its own |
| Queue *saving* | **none** — save is scene-phase work in the main app (Lane 2D-B) |

Registered via `Info.plist` → `CPTemplateApplicationSceneSessionRoleApplication` →
`$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate`, not in code.

`didConnect` order is unchanged: teardown any prior manager → store the interface controller →
construct `CarPlayManager` → `setupRootTemplate()` → `RemoteCommandManager.shared.setup()` →
connect-time playback sync **last**.

## The four references

All four were in `templateApplicationScene(_:didConnect:)`, in one `if let currentSong` branch.

| # | Reference | Kind | Can activate audio | Idempotent | Re-runs on reconnect |
|---|---|---|---|---|---|
| 1 | `currentSong` | read | no | yes | yes |
| 2 | `isPlaying` | read | no | yes | yes |
| 3 | `currentTime` | read | no | yes | yes |
| 4 | `restorePlayQueue(client:)` | operation | **no** | effectively — engine-guarded | yes, but self-limiting |

`restorePlayQueue` cannot begin audible playback. It guards on
`currentSong == nil, currentRadioStation == nil, queue.isEmpty`, restores from the local snapshot or
the server, publishes Now Playing with `isPlaying: false`, and calls `preloadCurrentSong()` — which
carries an explicit comment that it must **not** activate the audio session, because doing so would
interrupt other apps' audio before the user presses Play (#134). The rate stays at 0.

## Restoration ownership — unchanged

Restoration stays in the scene delegate's `didConnect`, in the same callback, still last, still on
every connection, still asynchronous inside the engine, still with the engine's own error handling.
It was **not** moved into `CarPlayManager` and **not** consolidated with the main app's path.

Reconnection is safe without a once-only rule, because two independent guards already limit it: the
call site skips restore whenever `currentSong` is non-nil, and `restorePlayQueue` itself returns
early unless song, radio station and queue are all empty. A head unit reconnecting mid-session
therefore takes the Now Playing refresh branch and leaves the queue untouched.

## Restoration overlap with the main app — documented, unchanged

Three call sites request restoration:

| Call site | Trigger |
|---|---|
| `CarPlay/CarPlaySceneDelegate.swift` | CarPlay scene connect |
| `Features/Library/ContentView.swift` | main iOS scene |
| `Features/Library/MacContentView.swift` | macOS scene |

They overlap by design and the overlap is harmless: whichever runs first restores, and the engine's
guard makes the others no-ops. Left exactly as-is — `ContentView` and `MacContentView` belong to
Lane 2D-B.

## Test seam

`CarPlayScenePlaybackActions` holds only the connect-time playback step. Scene ownership — the
interface controller, the manager's lifetime, teardown, and the order of those steps — stays in the
delegate, and template logic stays in `CarPlayManager`. The extraction exists because
`CPInterfaceController` and `CPTemplateApplicationScene` have no public initialisers, so `didConnect`
cannot be invoked from a test; without it, "connecting CarPlay must not start audible playback" would
be a claim with nothing behind it.

It returns a `ConnectOutcome` so tests can pin which branch ran without inspecting
`MPNowPlayingInfoCenter`. DEBUG-only `playbackOverride`, same pattern as the other four seams:
defaults `nil`, falls back to the composition point, reset in teardown, absent from release builds,
and alters no scene registration, controller ownership or template setup.

A test also asserts `CarPlayScenePlaybackActions.playback === CarPlayPlaybackActions.playback`, so
the scene and the manager can never drift onto different playback authorities.

---

# Lane 2D-B1 — scene-phase playback in the two ContentViews (done)

`Features/Library/ContentView.swift` and `Features/Library/MacContentView.swift`:
**1 direct reference each → 0.**

```
Scene-phase callback → ScenePlaybackLifecycleActions → ApplicationPlayback.shared
                     → LegacyAudioEngineAdapter → AudioEngine.shared → AVQueuePlayer
```

## The reference count understated the work

Each file showed **one** `AudioEngine.shared` occurrence — the alias line
`private var engine: AudioEngine { AudioEngine.shared }`. Through that alias the two files reached
**nine distinct members**, and **four were not on the façade**:

| Member | On façade before | |
|---|---|---|
| `currentSong`, `currentRadioStation`, `next`, `togglePlayPause`, `restorePlayQueue` | yes | |
| `savePlayQueue(client:)` | **no** | added |
| `saveQueueLocally()` | **no** | added |
| `createBookmarkIfNeeded(client:)` | **no** | added |
| `refreshPlaybackState()` | **no** | added |

The four are grouped as a new `PlaybackPersistenceControlling` capability — scene-phase persistence,
driven by the app lifecycle rather than by anything the user did to the queue. This is the same
alias trap that caused the original Lane 2A revert: counting `AudioEngine.shared` occurrences
understates the surface whenever a file aliases the singleton.

## Scene-phase behaviour — audited, unchanged

Both files use the **two-argument** closure `\.onChange(of: scenePhase) { _, newPhase in }`, and both
keep it. That arity is the known trap: rewriting to a zero- or one-argument closure produces the
misleading `(ScenePhase) -> Void expects 1 argument` error. Neither file's inspected value changed —
both still switch on the *new* phase.

| | iOS `ContentView` | macOS `MacContentView` |
|---|---|---|
| Save phase | **`.background`** | **`.inactive`** |
| Save operations | `savePlayQueue` → `saveQueueLocally` → `createBookmarkIfNeeded` | identical |
| Restore phase | `.active` | `.active` |
| Restore operations | `restorePlayQueue` → `refreshPlaybackState` | identical |
| Other phases | no-op | no-op |
| View-local follow-up on `.active` | widget command, auto-sync when online | playlist export sync when enabled |
| Guard | `appState.isConfigured` | `appState.isConfigured` |

**The platforms are deliberately not merged.** They save on *different phases*: a Mac window rarely
reaches `.background`, so waiting for it would mean never saving. A single shared handler would have
to pick one and would silently stop saving on the other platform. Hence two entry points,
`handleIOSScenePhase` and `handleMacScenePhase`, each pinned by its own test.

All operations are synchronous at the call site; the engine launches its own tasks internally, and
its own error handling is unchanged. No debounce, deduplication or throttling was added — a repeated
qualifying phase saves again, exactly as before.

The `.onChange` closures stay in the view files. Only the playback half moved; the widget command,
offline auto-sync and playlist export remain view-local and still run *after* the restore on
`.active`, as they always did.

## Restoration overlap — unchanged, now pinned

Three sites request restore: `CarPlaySceneDelegate`, `ContentView`, `MacContentView`. Every request
still delegates; the engine's own guard (`currentSong == nil, currentRadioStation == nil,
queue.isEmpty`) is what makes later ones no-ops. **No once-per-process rule was added.** A test
asserts all three resolve the same `ApplicationPlayback.shared`, so the queue cannot fork, and
another asserts repeated restore requests are *not* suppressed at the call site.

---

# Lane 2D-B2 — Vibrdrome.swift, the app entry point (done)

**15 direct references → 0.** This was the last application-facing caller.

```
Vibrdrome app entry → AppCommandPlaybackActions → ApplicationPlayback.shared
                    → LegacyAudioEngineAdapter → AudioEngine.shared → AVQueuePlayer
```

## Full member inventory

11 distinct members across 15 occurrences on 13 lines. **All 11 were already on the façade — no
capability additions were needed**, unlike Lane 2D-B1.

| Member | Kind | Where | Launch phase |
|---|---|---|---|
| `play(song:)` | operation | `handleDeepLink` → `case "song"` → `Task` | **URL / deep link** |
| `togglePlayPause()` ×2 | operation | Playback menu: ⌘P and Space | explicit user command |
| `next()` | operation | Playback menu: ⌘→ | explicit user command |
| `previous()` | operation | Playback menu: ⌘← | explicit user command |
| `seek(to:)`, `duration`, `currentTime` | operation + reads | Seek Forward 10s (⇧⌘→), via a local alias | explicit user command |
| `seek(to:)`, `currentTime` | operation + read | Seek Backward 10s (⇧⌘←), via a local alias | explicit user command |
| `toggleShuffle()` | operation | Playback menu: ⇧⌘S | explicit user command |
| `cycleRepeatMode()` | operation | Playback menu: ⇧⌘R | explicit user command |
| `volume` get+set ×2 | read + write | Volume Up ⌘↑ / Down ⌘↓ | explicit user command |
| `currentSong` ×2 | read | `toggleFavorite()` (⌘L), `setRating(_:)` (⌘1–5, ⌘0) | explicit user command |

Two local aliases (`let engine = AudioEngine.shared`, at the seek commands) were enumerated through
before editing, per the rule that burned Lane 2A and again in Lane 2D-B1.

## Launch-phase classification — the headline finding

| Group | References in this file |
|---|---|
| 1. App construction | **0** |
| 2. Initial scene setup | **0** |
| 3. Remote-command setup | **0** (it calls `RemoteCommandManager.setup()`, which owns its own playback) |
| 4. Restoration | **0** — restoration lives in `ContentView`/`MacContentView` and `CarPlaySceneDelegate` |
| 5. Explicit user command | **14** |
| 6. Widget command | **0** — `handleWidgetCommand()` is in `ContentView`, not here |
| 7. URL / deep link | **1** |
| 8. Background task | **0** |
| 9. Termination / persistence | **0** |
| 10. Standalone diagnostic read | **0** — every read is inside an explicit command |

**There is no cold-launch playback path in this file.** `VibrdromeApp.init()` runs credential and
visualizer migrations, prunes legacy widget keys, and calls `BackgroundSyncScheduler.registerTasks()`.
Both scenes' `.onAppear` install the image pipeline, call `RemoteCommandManager.shared.setup()`,
resume downloads, schedule background sync and start library sync. Machine-verified: neither block
contains a single playback call.

So the zero-activation gate here is not "the launch path was made safe" — it is "the launch path
never had a playback call to make unsafe", and the tests pin that it stays that way.

## Dependency ordering — unchanged

Nothing was resolved earlier for convenience. `SubsonicClientProvider.shared.client` is set in
`AppState.swift`, not here; `BGTaskScheduler` registration stays synchronous in `init()` (moving it
to `.onAppear` would make iOS silently drop a task-triggered launch); `scheduleRefresh()` /
`scheduleFullSync()` stay in `.onAppear`, after credentials are loaded. `RemoteCommandManager.setup()`
keeps its position at the top of `.onAppear`, before library sync.

## Naming note

The helper is `AppCommandPlaybackActions`, not `AppPlaybackLifecycleActions`. Every reference in this
file is an explicit command, and there is no lifecycle playback here at all — naming it "lifecycle"
would encode a launch-phase relationship that does not exist. Scene-phase lifecycle playback lives in
`ScenePlaybackLifecycleActions` (Lane 2D-B1), which is correctly named.

## Testability limit, stated plainly

`VibrdromeApp` is **not** constructed in tests. Its `init()` calls
`BackgroundSyncScheduler.registerTasks()`, and `BGTaskScheduler.register(forTaskWithIdentifier:)`
raises on a duplicate identifier — the host app already registered at launch, so building a second
`VibrdromeApp` would take the test process down rather than prove anything. The launch-path tests
drive what *is* safely re-runnable: the scene root and the idempotent remote-command setup. The
stronger claim — that `init()` and both `.onAppear` blocks contain no playback call — is a source
property, established by the enumeration above.

---

# Application-facing migration complete

Every application caller now routes through `ApplicationPlayback.shared`:

| Surface | Lane | Refs migrated |
|---|---|---|
| Views (34 files) | 2A | 107 |
| Remote commands | 2B | 8 |
| CarPlay manager | 2C-A | 19 |
| Watch session | 2C-B | 9 |
| Siri / App Intents | 2C-C | 6 |
| CarPlay scene | 2D-A | 4 |
| Main scene phase | 2D-B1 | 2 (9 members via aliases) |
| App entry | 2D-B2 | 15 |

A test asserts all six seams plus the composition point resolve the **same** object, so the
application cannot fork into two playback authorities.

---

# Lane 3A — the application playback router (done)

Composition before:

```
ApplicationPlayback.shared → LegacyAudioEngineAdapter → AudioEngine.shared → AVQueuePlayer
```

Composition now:

```
Views / CarPlay / Watch / Siri / Remote commands / Lifecycle / App entry
                              ↓
                   ApplicationPlayback.shared
                              ↓
                  ApplicationPlaybackRouter        ← the decision lives here
                              ↓
                   LegacyAudioEngineAdapter        ← the only destination
                              ↓
                      AudioEngine.shared → AVQueuePlayer
```

**Zero behaviour change.** Every one of the router's 58 members forwards to the legacy adapter.

## Why a router rather than swapping what `shared` returns

Lane 2 moved 170 call sites across eight surfaces onto `ApplicationPlayback.shared`, and those
surfaces *hold* it. If its identity could change under them, the app would end up with two queue
authorities and no way to tell which one the user is looking at. So:

- the **authority is stable** for the process lifetime — one router, always the same object;
- the **decision lives inside it** — a future lane changes what `routed` returns, never what callers
  hold.

`routed` is a `switch` on an explicit `PlaybackBackend`, not an identity check on a stored
controller: the policy has to read as policy, and a later lane must not be able to change routing by
accidentally reassigning a reference. `.persistent` exists as a case so the decision has a name
before it has a second destination; `selectedBackend` is `private(set)` and never assigned, so
`.legacy` is the only reachable runtime value. Selecting `.persistent` today trips an
`assertionFailure` in DEBUG and falls back to legacy in release — a premature selection should be
loud in development and harmless in the field, never silently routed to something unbuilt.

## The revised invariant

Lane 2's identity test proved *all seams resolve the same façade*. That is now:

```
All application seams → the same stable ApplicationPlaybackRouter
                      → the same routing decision (.legacy)
                      → the same LegacyAudioEngineAdapter
                      → the same AudioEngine.shared
```

Both halves are tested. The existing identity test was updated rather than deleted.

**Note for Lane 3D:** once the router can return different destinations, "same authority" stays true
but "same destination" stops being the invariant — it becomes "same *decision* for the same source".
That test needs rewriting deliberately at that point, not deleting when it starts failing.

## Diagnostics

The router reports what is actually true:

```
Application playback router: Active
Selected backend: Legacy
Legacy adapter: Active
Persistent controller: Not constructed
```

`persistentControllerConstructed` is *read* from `GaplessDiagnosticsRegistry`, not asserted — if
anything ever does construct a persistent controller, diagnostics must say so rather than keep
reporting the comfortable answer.

## No source predicate

Lane 3A adds **no** routing predicate. Nothing consults format (FLAC/ALAC/AAC/Opus/MP3), local vs.
streamed, cache state, radio, live streams, channel count or gapless metadata. That is Lane 3B.

## Planned lanes

| Lane | Scope |
|---|---|
| **3B** | Pure backend-routing predicate — a testable function, consulted by nothing yet |
| **3C** | Construct the persistent engine in production, still unselected; measure cold-launch cost and leaks against the recorded soak numbers |
| **3D** | First real persistent routing behind a DEBUG/settings flag, then the serialized buffer gate |
| **4** | Direct-device smoke and regression testing |

---

# Lane 3B — the playback-backend routing policy (done)

A pure decision function, **consulted by nothing**. The router still always selects `.legacy`.

## Pre-playback fact availability — audited, not assumed

| Fact | When it becomes known |
|---|---|
| Content kind (track vs radio) | **Before request** — the queue knows what it holds |
| Song metadata: server-declared suffix, duration | **Before request** |
| Download / cache record for the track | **Before request** |
| *Requested* transcode format + max bitrate | **When the request is constructed** — `stream(id:maxBitRate:format:)`. A request, not an outcome |
| **Delivered** container | **From response headers** — `GaplessStreamingFileProvider.fileExtension(for:remote:)` reads `response.mimeType` |
| True sample rate, channel count, exact frame length | **Only after opening the media** — `AVAudioFile(forReading:)` |
| MP3 Xing/LAME trim validity | **Only after decoder inspection** — `GaplessTrim` parses the header |
| Whether the server *will* honour a requested transcode | **Never reliably known before asking** |

## The transcode-knowledge result

The client **does** confirm the delivered representation — but only after fetching. The gapless file
provider reads the response MIME type and names the cache file from it, with the reason stated in
the source: *"A transcoding server returns a different type than the stored file, so the response's
content type wins over anything in the request URL."*

That gives Lane 3D a real confirmation point, and it is not before the request:

```
existing local file?  → representation confirmed from the file itself
otherwise fetch       → representation confirmed from the response MIME type
then open AVAudioFile → sample rate, channel count and exact length confirmed
```

The persistent engine reads `AVAudioFile(forReading:)`, so **every source must exist as a complete
local file before playback** — remote tracks are materialised by a whole-file download, deliberately
not a streaming read, because a partial file decodes short and would corrupt boundary accounting.
That materialisation *is* the confirmation step.

## Conservative rule

```
Delivered representation not confirmed → Legacy
```

Requested-but-unconfirmed and unknown delivery are always legacy, whatever else is true — including
when a trusted trim is already known. Routing on the configured transcode preference would be
guessing what the server did.

## Backend eligibility ≠ gapless capability

Two separate outputs, because collapsing them fails in both directions — withholding the engine from
playable content, or promising a seam it cannot deliver.

| Source | Backend | Playable | Gapless | Reason |
|---|---|---|---|---|
| FLAC / ALAC / AAC / WAV / Opus, confirmed | persistent | yes | yes | supported *(source form)* |
| MP3 with trusted Xing/LAME trim | persistent | yes | **yes** | supported *(source form)* |
| MP3, header absent or not inspected | persistent | yes | **no** | `gaplessMetadataUnavailable` |
| MP3, header malformed or untrusted | persistent | yes | **no** | `gaplessMetadataUntrusted` |

MP3 without a trim is **not** forced to legacy. It plays on the persistent engine; it just cannot
promise a seamless join. That mirrors the measured format matrix: WAV/FLAC exact, ALAC/AAC exact via
`iTunSMPB`, Opus exact at 48 kHz, MP3 **+1368 frames** (delay 576 + padding 792) unless trimmed.

## Hard legacy decisions

Radio · live stream · indefinite stream · unknown content kind · unknown delivery ·
requested-but-unconfirmed transcode · unsupported codec · unknown codec · above-stereo channel
layout · decoder known unavailable · required media properties unknown (duration, channel count).

Each has its own reason — nothing funnels into a single `.unsupported`.

## Channels

Mono up-mixes to stereo **without changing the frame count**, so accounting stays exact; stereo
passes through; above stereo is refused, matching `GaplessChannelPolicy.validate`, which throws
`unsupportedChannelCount` for anything other than 1 or 2 "pending a product decision on downmix".
An undiscovered channel count is treated conservatively — it is discoverable only by opening the
file, so Lane 3D must defer final selection until preparation has done so.

Sample rate is deliberately **not** gated: a mismatch against the fixed 44.1 kHz graph is the
converter's job, and Opus decoding at 48 kHz is an expected supported case.

## The Lane 3D sequence

```
build routing facts
→ evaluate policy
→ prepare the selected backend
→ confirm the actual representation (response MIME, then AVAudioFile)
→ finalise selection BEFORE audible playback
→ never switch while audible
```

If the final representation cannot be confirmed before playback starts, select **Legacy**. There is
no mid-track fallback and no cutover: a source that turns out unsuitable must have been legacy from
the first sample.

## Doc-comment discrepancy worth knowing

`GaplessRenderFormat`'s header comment says sources above stereo "are down-mixed only via an explicit
converter channel map". `GaplessChannelPolicy.validate` actually **throws** for anything above 2
channels. The code is authoritative and the policy follows it; the comment is stale. Not corrected
here — it is persistent-engine code and outside this lane.

## Remaining direct references by subsystem

## Remaining direct references by subsystem

## Remaining direct references by subsystem

## Remaining direct references by subsystem

## Remaining direct references by subsystem

## Remaining direct references by subsystem

## Remaining direct references by subsystem

32 references remain (occurrence counts, not line counts). **No application-facing caller is among
them** — what is left is the legacy implementation, the façade's own files, the documented debug
exception, and the persistent engine:

| Subsystem | Files | Refs | Lane |
|---|---|---|---|
| Legacy implementation collaborators | `Core/Audio/EQEngine.swift` (6), `AudioEngine+Predownload.swift` (6), `AudioSession.swift` (4), `SleepTimer.swift` (2), `NowPlayingManager.swift` (2), `CrossfadeController.swift` (1) | 21 | 3 |
| Façade / router internals | `Application/LegacyAudioEngineAdapter.swift` (3 — the delegation itself), plus doc-comment mentions in `ApplicationPlaybackControlling.swift`, `CarPlayPlaybackActions.swift`, `AppCommandPlaybackActions.swift` | 6 | — (by design) |
| Debug screen | `Features/Settings/DebugView.swift` | 3 | **permanent diagnostic exception** |
| Persistent-engine implementation | `Gapless/GaplessRemoteCommandCoordinator.swift` (1), `Gapless/GaplessEQStage.swift` (1) | 2 | — |
| Main app scene entry | — | **0** | **2D-B2 done** |
| Main app scene phase | — | **0** | **2D-B1 done** |
| CarPlay scene / lifecycle | — | **0** | **2D-A done** |
| Siri / App Intents | — | **0** | **2C-C done** |
| Watch session | — | **0** | **2C-B done** |
| CarPlay manager | — | **0** | **2C-A done** |
| Remote commands | — | **0** | **2B done** |
| Views | — | **0** | **2A done** |

Persistent-engine references in **tests** are separate and expected: `GaplessPlaybackController` is
constructed in 11 test files and **0** production files.

`GaplessPlaybackController` is constructed in **11 test files and 0 production files** — the
persistent engine remains unwired.

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

1. **Views** — **complete**: 34 files. The largest group and the lowest risk.
2. **RemoteCommandManager** — **complete**: one file, 8 references, one-press-one-call proven by test.
3. **CarPlay, Watch, Siri** — out-of-process callers. **2C-A CarPlayManager** and **2C-B WatchSessionManager** and **2C-C AppIntents** all complete — batch 3 is done.
4. **Scene entry and lifecycle** — restoration and cold launch; migrate last, because the Build 60
   zero-activation behaviour depends on it.

Every remaining call site still calls the singleton directly, and the façade reads the same object,
so the two cannot disagree.
