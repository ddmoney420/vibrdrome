# Persistent Gapless Engine — Session Handoff

**Written:** 2026-08-02 · **Branch:** `feat/persistent-gapless-engine` @ `19fd966` (off `develop @ 3d82895`)

Resume point for building the persistent-output gapless audio engine. Self-contained — read this
top to bottom and you have everything to continue in a fresh session.

---

## TL;DR

Gapless playback is the **active release gate**. Build 60 release prep is **stopped**. The
AVQueuePlayer path has two proven transition defects that no AVQueuePlayer-level fix resolves, so
we are **rewriting playback onto a persistent-output `AVAudioEngine` graph**. **Checkpoint 2 is
done and objectively proven** (offline render = frame-continuous across every boundary). Next is
**Checkpoint 3** (real integration: streaming, EQ, visualizers, ReplayGain, queue/repeat parity),
then **Checkpoint 4** (one device build + acceptance).

---

## Why we're here (the investigation that led to the rewrite)

The AVQueuePlayer playback path has **two distinct** transition artifacts:

1. **Tap freeze (~150–200 ms)** — PROVEN cause: the per-item `MTAudioProcessingTap` (`item.audioMix`).
   Isolated harness showed processing ON → freeze at every transition; OFF → seamless.
2. **Subsequent-transition click** — first transition after a fresh play is seamless; every later
   one clicks. Persists with the tap OFF, on FLAC and ALAC, streamed and downloaded. UNSOLVED at
   the AVQueuePlayer level.

**Ruled out for the click** (do not re-investigate): queue construction, dynamic vs preloaded
insertion, single vs deep lookahead, end observers, queue churn, local vs downloaded material,
buffer readiness, precise-lookahead asset init, processing-tap removal, per-advance seam ops
(volume / observer churn / visualizer-source). The isolated harness never reproduced the click →
it isn't in the discrete queue mechanics.

**External confirmation** (NaviBeat + Apple WWDC21 "Transition media gaplessly with HLS"): robust
iOS gapless keeps ONE hardware output stream open across the handoff and schedules into it; gapless
is a custom-engine feature, not reliably bolt-on to the AVPlayer passthrough path. Diagnostics for
all this live on throwaway branch `diag/gapless-queue-matrix @ bc4b2d6` (DEBUG-only; **never merge**).

Memory files: `gapless-click-investigation.md`, `gapless-architecture-reference.md`.

---

## Guardrails (hard rules)

- **Do NOT** merge, version-bump, tag, archive, upload, release, or contact reporters without
  explicit approval.
- **Do NOT** touch `develop` or the Build 60 fixes (they're preserved at `develop @ 3d82895`).
- Keep the existing AVQueuePlayer `AudioEngine` as the **production path and fallback** until the
  new engine reaches parity. Do not switch engines silently mid-track.
- **Objective offline/automated tests replace by-ear loops.** Only ask for **one** focused device
  confirmation after automated + offline evidence passes. The owner is fatigued by device testing —
  do not hand back repeated "go tap this" loops.
- After `xcodegen generate`, **restore entitlements**: `git checkout -- Vibrdrome/Vibrdrome.entitlements
  VibrdromeWidget/VibrdromeWidget.entitlements` (CarPlay + App Group). `.xcodeproj` is gitignored;
  new files need regen (dir-glob sources).

---

## State of the branch

```
feat/persistent-gapless-engine @ 19fd966   ← work here
develop                        @ 3d82895   ← Build 60 fixes, DO NOT TOUCH
diag/gapless-queue-matrix      @ bc4b2d6   ← throwaway DEBUG diagnostics, never merge
```

**Committed on this branch (19fd966):**
- `Vibrdrome/Core/Audio/Gapless/GaplessRenderFormat.swift` — render-format policy.
- `Vibrdrome/Core/Audio/Gapless/GaplessScheduler.swift` — pure frame-accounting.
- `Vibrdrome/Core/Audio/Gapless/PersistentGaplessEngine.swift` — persistent graph + offline render.
- `VibrdromeTests/Core/GaplessEngineOfflineTests.swift` — objective frame-continuity tests.
- `spike/gapless-proof/main.swift` — standalone repro (`swift main.swift`).

(Note: `GaplessPromotionWaiter.swift` / `GaplessAdvanceTests.swift` on develop are the OLD
AVQueuePlayer helpers — not part of the new engine.) Prior spec: `docs/release/12-gapless-playback-spec.md`.

---

## Architecture (target)

Persistent graph — never torn down across track boundaries:

```
AVAudioPlayerNode → AVAudioUnitEQ(10-band) → AVAudioMixerNode(+visualizer tap) → engine.mainMixerNode → output
```

- **Scheduler** (`GaplessScheduler`): frame-accounted rolling queue. Each item = {id, renderFrames,
  startFrame, endFrame}. Consecutive `scheduleFile(at: nil)` / `scheduleSegment` — no overlap, ≥2
  prepared ahead. Metadata/scrobble/Now Playing flip at the **rendered** boundary
  (`AVAudioPlayerNodeCompletionCallbackType.dataRendered`), NOT data-consumed. `truncate(fromID:)`
  handles queue edits.
- **Render-format policy** (`GaplessRenderFormat`): one stable format for the engine's life —
  Float32, non-interleaved, 44.1 kHz stereo (`.standard`). Mono up-mixes to stereo (frame count
  unchanged). Sample-rate mismatch → convert ahead with `AVAudioConverter` (changes frame count →
  record converted frames per segment). Never silently downmix >2ch; use an explicit channel map.
- **Decode/prefetch**: reuse `PredownloadManager` → decode from local cached file → schedule. Never
  hit network at the boundary. Underrun must be reported (not disguised) with safe fallback.
- **EQ**: `AVAudioUnitEQ` in the persistent graph; flat = transparent bypass; toggling must not
  rebuild the graph or recreate the player node. The old per-item `MTAudioProcessingTap` is NOT used.
- **Visualizers**: persistent mixer tap feeds Classic (FFT/`AudioSpectrum`) + Native
  (`VisualizerPCMSource`). Opening/closing a visualizer must not recreate the audio source.
- **ReplayGain**: per-track gain applied at the exact boundary (decode-time, per-track mixer gain,
  or a scheduled gain node) with a very short ramp to avoid a click. Document album vs track gain.

---

## What's DONE — Checkpoint 1 + 2

**Checkpoint 1** (architecture, format policy, scheduler design, files) — above + implemented.

**Checkpoint 2** (vertical slice + objective proof) — the persistent graph plays 4 continuous-tone
parts scheduled consecutively, rendered offline (deterministic `AVAudioEngine` manual rendering):

```
rendered 1764000 / 1764000 frames        → zero inserted / dropped / duplicated
in-cycle smooth delta: 0.00887
worst delta anywhere:  0.00887  (mid-cycle, NOT at a boundary)
boundary P1→P2 / P2→P3 / P3→P4: all 0.00887 == in-cycle
RESULT: PASS   (EQ node live in the path)
```

Automated tests: 3 new (2 pure-scheduler + 1 offline render) pass; **full suite 770/770 green,
0 warnings**. Perf note: offline throughput ~90× real-time (headroom indicator only; real CPU/mem/
battery need device measurement at CP4).

**Verify anytime:**
```bash
# Standalone objective proof (no Xcode):
swift spike/gapless-proof/main.swift          # expect RESULT: PASS

# In-target automated tests:
xcodebuild -project Vibrdrome.xcodeproj -scheme Vibrdrome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:VibrdromeTests/GaplessEngineOfflineTests test
```

---

## What's NEXT — Checkpoint 3 (do this next)

Real integration, each gated by **automated frame-continuity + state tests before any device build**:

1. **Streaming/cached-file**: resolve Navidrome URL → predownload to temp cache (reuse
   `PredownloadManager`) → decode from local file → schedule. Rolling pipeline: current + next
   fully ready + one more preparing. Report per format: direct ALAC, direct FLAC, AAC, MP3,
   server-transcoded, downloaded/offline. Real-album automated evidence (use the test albums below).
2. **EQ** in the persistent graph — toggle without engine restart or item recreation; gapless holds
   with EQ ON. Reuse `EQEngine` (`syncCoefficients()`) coefficients.
3. **Visualizers** — persistent mixer tap feeding Classic + Native; consumer gating without graph
   rebuild. Reuse `VisualizerPCMSource` (`beginRenderConsumer`/`endRenderConsumer`).
4. **ReplayGain** — boundary-scheduled gain; reuse `AudioEngine.computeReplayGainFactor(for:)`
   (capped 1.5× per project rule). Short ramp, no click.
5. **Queue + repeat parity** — Off / All / One (One reschedules current without stopping the engine;
   All wraps; manual Next/Prev override One). Reuse `RepeatMode` + pure `nextSequentialIndex`.
   Queue ops: auto-advance, Next/Prev, play from album/playlist/search, replace, Play Next, Add,
   Remove, reorder, shuffle, restored playback. Cancel scheduled-but-unplayed items without engine
   restart (document strategy).
6. **Seeking** — within active track, cancel stale scheduled audio, reschedule remainder + upcoming,
   correct metadata, no duplicate scrobble. Needn't be gapless but must be correct/responsive.

**Checkpoint 4** (only after CP3 automated + offline pass): ONE device build + acceptance matrix
(10+ tone boundaries, 2 real albums 1→2/2→3/3→4, EQ off/on, Classic + Native viz, Repeat Off/All/One,
Next/Prev, background/lock-screen, Bluetooth, AirPlay). Then a production-merge recommendation.

**Crossfade**: do NOT implement until ordinary gapless passes. Later: two player nodes (A outgoing /
B incoming) into the persistent mixer with scheduled gain ramps. Gapless and crossfade are separate
modes; crossfade OFF = exact consecutive scheduling, no overlap.

---

## Definition of done (gate for merge recommendation)

Offline rendering proves frame-continuous boundaries · local device playback has no audible
click/pause · later transitions as clean as the first · EQ doesn't degrade transitions · visualizers
don't degrade transitions · Repeat modes correct · queue edits correct · background + lock-screen
correct · AirPlay no functional regression (don't weaken the Build 59 AirPlay fix) · no per-item
`MTAudioProcessingTap` for normal processing · Build 60 fixes intact · cold launch still doesn't
interrupt Spotify/YouTube until the user starts playback · scrobble policy preserved (one completed
play = one eligible scrobble; scheduling/decoding ≠ scrobble).

---

## Integration points in existing code (reuse, don't reinvent)

- `PredownloadManager` (`AudioEngine.predownloadManager`) — prefetch to local cache.
- `EQEngine` (`Core/Audio/EQEngine.swift`, `syncCoefficients()`) — 10-band coefficients.
- `VisualizerPCMSource` (`Core/Audio/VisualizerPCMSource.swift`) — Native viz PCM consumer.
- `AudioSpectrum` — Classic viz FFT source.
- `AudioEngine.computeReplayGainFactor(for:)` — RG factor (cap 1.5×).
- `RepeatMode` + `AudioEngine.nextSequentialIndex(current:count:repeatMode:)` (pure, tested).
- `NowPlayingManager.shared` — lock-screen/CarPlay metadata + transport.
- `SubsonicClientProvider.shared.client` — stream URL resolution; watch/remote commands.
- Existing `AudioEngine` (`Core/Audio/AudioEngine*.swift`) — the fallback engine + all queue state.

---

## Environment

- **Device:** Damion's iPhone 17 Pro Max. Install UDID `AA719D3B-DB77-55E3-9007-83E0A3685C9D`
  (`xcrun devicectl device install app --device <udid> <app>`; launch with
  `process launch --terminate-existing --device <udid> com.vibrdrome.app`). idevicesyslog hardware
  UDID `00008150-001635990EC0401C` (flaky; drops when phone locks — prefer on-screen logging).
- **Test media (local Mac):** `~/vibrdrome-test-media/Gapless 4-Track Test/` (FLAC),
  `~/vibrdrome-test-media/Gapless 4-Track ALAC/` (ALAC) — one continuous 220 Hz tone split into 4
  sample-exact 441000-frame parts, all joins (incl. loop wrap) verified seamless. Also on the
  owner's Navidrome server. Regenerate with ffmpeg if needed (see git history of this handoff).
- **Tools:** Swift 6.3 + AVFoundation on macOS 26 (offline render works). `xcodegen` (restore
  entitlements after). Xcode 26, iOS 17+ target, sim = iPhone 17 Pro.
- **Build/QA:** `scripts/verify-build.sh` (or `--quick`) = source of truth for green.
  `swiftlint` = 0 violations required. 0 source warnings required.

---

## First moves in the new session

1. `git checkout feat/persistent-gapless-engine` (confirm `@ 19fd966`).
2. Re-read this file + the two gapless memory files.
3. Sanity-check the proof still passes: `swift spike/gapless-proof/main.swift` → `RESULT: PASS`.
4. Start Checkpoint 3 item 1 (streaming/cached-file gapless) — build the prefetch→decode→schedule
   path, prove it with the real 4-track album via automated/offline evidence before any device build.
