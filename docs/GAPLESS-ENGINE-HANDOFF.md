# Persistent Gapless Engine — Session Handoff

**Written:** 2026-08-02 · **Branch:** `feat/persistent-gapless-engine` @ `68b74cb` (off `develop @ 3d82895`)

Resume point for building the persistent-output gapless audio engine. Self-contained — read this
top to bottom and you have everything to continue in a fresh session.

---

## TL;DR

Gapless playback is the **active release gate**. Build 60 release prep is **stopped**. The
AVQueuePlayer path has two proven transition defects that no AVQueuePlayer-level fix resolves, so
we are **rewriting playback onto a persistent-output `AVAudioEngine` graph**. **Checkpoints 1, 2 and
3 items 1–2 are done and objectively proven** (offline render = frame-continuous across every
boundary, for every delivery format, with EQ bypassed / neutral / audible). Next is **Checkpoint 3
items 3–6** (ReplayGain, visualizers, queue/repeat/seek parity, background + remote), then
**Checkpoint 4** (one device build + acceptance).

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
feat/persistent-gapless-engine @ 68b74cb   ← work here
develop                        @ 3d82895   ← Build 60 fixes, DO NOT TOUCH
diag/gapless-queue-matrix      @ bc4b2d6   ← throwaway DEBUG diagnostics, never merge
```

**Committed on this branch (19fd966 — Checkpoint 1 + 2):**
- `Vibrdrome/Core/Audio/Gapless/GaplessRenderFormat.swift` — render-format policy.
- `Vibrdrome/Core/Audio/Gapless/GaplessScheduler.swift` — pure frame-accounting.
- `Vibrdrome/Core/Audio/Gapless/PersistentGaplessEngine.swift` — persistent graph + offline render.
- `VibrdromeTests/Core/GaplessEngineOfflineTests.swift` — objective frame-continuity tests.
- `spike/gapless-proof/main.swift` — standalone repro (`swift main.swift`).

**Committed on this branch (68b74cb — Checkpoint 3 item 2):**
- `Vibrdrome/Core/Audio/Gapless/GaplessEQStage.swift` — persistent EQ, settings mapping, ramp+settle.
- `Vibrdrome/Core/Audio/Gapless/GaplessGainStage.swift` — ReplayGain gain-stage interface (design).
- `Vibrdrome/Core/Audio/Gapless/GaplessVisualizerTap.swift` — install-once tap seam (not yet wired).
- `GaplessTrimDiagnostics` + trim hardening; `.mp3WithoutGaplessMetadata` rename.
- Tests: `GaplessEQTests`. Spikes: `gapless-eq-cost`, `probe-server-transcode.sh`,
  `fetch-server-album.sh`.

**Committed on this branch (93ec188 — Checkpoint 3 item 1):**
- `Vibrdrome/Core/Audio/Gapless/GaplessTrim.swift` — per-format schedulable range + Xing/LAME parsing.
- `Vibrdrome/Core/Audio/Gapless/GaplessPrefetchWindow.swift` — pure rolling-window policy.
- `Vibrdrome/Core/Audio/Gapless/GaplessTrackPreparer.swift` — resolve → decode → prepare.
- `Vibrdrome/Core/Audio/Gapless/GaplessFileProviders.swift` — local + streaming/caching providers.
- `PersistentGaplessEngine.schedule(tracks:)` — segment-based scheduling.
- Tests: `GaplessTrimTests`, `GaplessPrefetchWindowTests`, `GaplessPipelineOfflineTests`,
  `GaplessRealAlbumTests` (real encoded albums through the production types).
- `spike/gapless-formats/main.swift` + `make-test-albums.sh` — per-format matrix and its media.

(Note: `GaplessPromotionWaiter.swift` / `GaplessAdvanceTests.swift` on develop are the OLD
AVQueuePlayer helpers — not part of the new engine.) Prior spec: `docs/release/12-gapless-playback-spec.md`.

---

## Architecture (target)

Persistent graph — never torn down across track boundaries:

```
AVAudioPlayerNode → gain stage → AVAudioUnitEQ(10-band) → output mixer(+visualizer tap) → engine.mainMixerNode → output
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
- **Decode/prefetch**: consume the download layer's cache → decode from the local file → schedule.
  Never hit network at the boundary. Underrun must be reported (not disguised) with safe fallback.
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
# Standalone objective proofs (no Xcode):
swift spike/gapless-proof/main.swift          # expect RESULT: PASS
swift spike/gapless-formats/main.swift        # per-format matrix (needs ffmpeg)

# In-target automated tests:
xcodebuild -project Vibrdrome.xcodeproj -scheme Vibrdrome \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:VibrdromeTests/GaplessEngineOfflineTests test
```

---

## What's DONE — Checkpoint 3 item 1 (streaming / cached-file gapless)

Pipeline: **resolve → local file (downloaded/cached, else fetched whole) → decode → prepare →
schedule as a segment**, with a rolling window of *current + next fully ready + one preparing*
(`GaplessPrefetchWindow`). No network, decode, or file I/O happens at a boundary.

**Per-format result** — independently-encoded parts of one continuous tone, scheduled consecutively
into the persistent graph and measured by frame count *and* by phase at each join:

| Delivery path                   | Decoded length      | Join after this work |
|---------------------------------|---------------------|----------------------|
| FLAC (direct)                   | exact               | frame-continuous     |
| ALAC (direct, m4a)              | exact               | frame-continuous     |
| AAC (direct, m4a)               | exact (`iTunSMPB`)  | frame-continuous     |
| Opus (transcode, 48 kHz)        | exact               | frame-continuous     |
| MP3 (direct or transcoded file) | **+1368 frames**    | frame-continuous *after trim* |
| MP3 from a **live** transcode   | +1368 frames        | **not fixable** — see below |
| Downloaded / offline            | same as its format  | same as its format   |

**The MP3 finding.** `AVAudioFile` applies the m4a `iTunSMPB` gapless atom but **not** the MP3
Xing/LAME header — it returns encoder delay + padding as ordinary audio (measured: delay 576 +
padding 792 = 1368 frames per track, ~31 ms per join, 124 ms across a 4-track album).
`GaplessTrimPolicy` parses that header and the engine schedules `[delay, length - padding)` as an
explicit segment, which restores exact continuity.

**The cell that cannot be trimmed.** An MP3 carrying no trustworthy gapless metadata cannot be
trimmed by the client, because the exact encoder delay and final padding are unknown. Reported as
`.mp3WithoutGaplessMetadata`, which describes **that response** — not MP3, and not streaming in
general. A server that supplied the same information another way, or spooled the encode to a
complete file before delivering it, would trim normally.

**Never apply a fallback constant.** A fixed 576/792 is right for one encoder at one setting; applied
to anything else it deletes real audio or leaves padding in place. Either way it converts an honest
"unsupported" into a silently wrong answer.

### Measured against the owner's real Navidrome (2026-08-02)

Probe: `spike/gapless-formats/probe-server-transcode.sh` (reads the Keychain itself; prints no
credentials, tokens, or media URLs). Album fetch: `fetch-server-album.sh`.

| | MP3 transcode | Opus transcode |
|---|---|---|
| HTTP | 200, `audio/mpeg` | 200, `audio/ogg` |
| Delivery | 1st request chunked, 2nd had `content-length` (server caches the transcode) | complete response |
| Repeatability | two identical requests byte-identical | — |
| Xing / Info / LAME | **all absent** | n/a |
| Delay + padding | **not recoverable** | n/a |
| Codec / rate | mp3, 44.1 kHz, stereo | opus, **48 kHz**, stereo |
| Decoded frames (10 s part) | 442368 (**+1368**) | 480000 (**exact**) |
| Boundary continuity | **discontinuous at every join** | **frame-continuous at every join** |
| Range requests | — | `206` — byte ranges supported |

Caching the completed response does **not** make it trim-capable: caching cannot add metadata the
encoder never wrote.

**Recommendation (owner's decision, not blocking):** this server's MP3 transcode cannot be gapless.
Its **Opus** transcode is gapless and measured frame-exact, so switching the transcode target to Opus
— or serving originals — resolves it. FLAC, ALAC, AAC, stored MP3, and downloaded files are already
frame-exact and unaffected. AirPlay behaviour with Opus is still to be checked (Checkpoint 4).

**Note on `PredownloadManager`:** the new provider *consumes* what the download layer already
cached, but does not drive `PredownloadManager` itself. That actor sleeps 10 s before its first
download and 20 s between downloads, and does nothing when the user's *Preload songs* setting is 0 —
correct for polite background caching, wrong for a fetch that must finish before the current track
ends. A file it already fetched is used as-is, with no second download.

**Evidence:** `GaplessRealAlbumTests` runs 5 real encoded albums through the **production** types;
`GaplessPipelineOfflineTests` proves the pipeline end-to-end hermetically; `GaplessTrimTests` pins
the header parsing. `verify-build.sh` **RESULT: PASS** — 801 tests, 0 warnings, SwiftLint clean.

**Harness gotcha (cost an hour, don't rediscover):** building many `AVAudioEngine`s in one process
without a full teardown starts producing corrupted renders — it showed up as a phantom
discontinuity on files that render clean in isolation. `spike/gapless-formats` now stops, disables
manual rendering, and detaches nodes inside an autorelease pool per render. If a measurement
disagrees with an isolated re-run, suspect the harness before the engine.

---

## What's DONE — Checkpoint 3 item 2 (persistent EQ)

Graph, built once and never rebuilt:

```
AVAudioPlayerNode → gain stage → AVAudioUnitEQ → output mixer → mainMixerNode → output
```

A track boundary is no longer an EQ event — nothing is attached, detached, reset, or reconnected, so
filter state carries across the join like any mid-track moment. No per-item `MTAudioProcessingTap`.

**Existing settings mapped unchanged** (`GaplessEQStage`): 10 ISO bands (32 Hz–16 kHz), RBJ peaking
shape at a fixed 1-octave bandwidth, ±12 dB clamp, presets and persistence untouched. The
`EQTapProcessor` pre-gain clip guard becomes the unit's `globalGain` — identical result, because
scaling commutes with a linear filter chain.

**Two findings that changed the implementation** (both found by measurement, neither by ear):

1. **A one-step EQ change clicks.** Worst sample-to-sample delta ~5× the signal's own in-cycle step.
   Fixed with a **50 ms parameter ramp** driven in *audio* time (the render loop), not wall time —
   which is also why it reproduces identically offline.
2. **Flattening the bands is not enough to engage bypass.** The biquads still hold decaying energy
   from the previous curve, and bypassing discards it in a single sample: a step of **0.071**, ~8×
   in-cycle. Settle time was measured directly (50 ms already clean) and a **200 ms transparent
   settle** now runs before bypass engages. Re-enabling during the settle cancels it, so bypass is
   never switched under a live signal.

Bypass is kept because it is confirmed to cost nothing: **0.0043% of one core bypassed vs 0.13%
active** (`spike/gapless-eq-cost`), memory unchanged in every state. Device CPU/thermal/battery
remain a Checkpoint 4 measurement.

**Proven:** frame continuity with EQ bypassed, active-neutral, and active with an audible preset;
scheduled frame ranges **identical** with EQ on and off; graph node identity unchanged across
enable/disable/band-change cycles; mid-render enable, band change, disable and re-enable (including
immediately before boundaries) leave no discontinuity. 829 tests green, 0 warnings.

**Filter-state reset semantics** — a persistent filter carries state across a *continuous* join,
which is what an album should do. It is **not** reset by a track boundary or by an EQ change. It
*will* be discontinuous wherever the audio itself is: a manual skip, a seek, or a queue replacement
splices unrelated audio, so the filter's carried state belongs to the previous material. That is
correct and inaudible in practice (the state decays in tens of milliseconds), but it is the reason
seek/skip must not be treated as gapless joins.

---

## What's NEXT — Checkpoint 3 items 3–6

Real integration, each gated by **automated frame-continuity + state tests before any device build**:

1. ~~**Streaming/cached-file**~~ — **DONE** (see above).
2. ~~**EQ** in the persistent graph~~ — **DONE** (see above).
3. **ReplayGain** — interface already defined in `GaplessGainStage` (persistent node, applied at the
   *rendered* boundary, short ramp, never baked into cached files, 1.5× cap, album vs track gain,
   peak protection, missing-metadata → unity). Only the policy + wiring remain.
4. **Visualizers** — tap point already exists (`GaplessVisualizerTap` on `outputMixer`, install-once,
   consumers add/remove without touching the graph). Wire Classic + Native to the one feed.
5. **Queue / repeat / shuffle / seek parity.**
6. **Background, lock-screen, remote control.**

Original numbering below is preserved for the remaining items:

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

- `PredownloadManager` (`AudioEngine.predownloadManager`) — background offline caching. **Consume its
  output; don't drive it** for boundary-critical fetches (10 s/20 s pacing, preload-count gated).
- `GaplessStreamingFileProvider` — the gapless-owned resolve/fetch path (checks downloads first).
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
- **Test media (local Mac):** `~/vibrdrome-test-media/Gapless 4-Track Test/` (FLAC) and
  `Gapless 4-Track ALAC/` — one continuous 220 Hz tone split into 4 sample-exact 441000-frame parts,
  all joins (incl. loop wrap) verified seamless. Also on the owner's Navidrome server.
  Per-format albums (`MP3`, `AAC`, `Opus`, `Transcoded MP3`) are generated from the FLAC master by
  `spike/gapless-formats/make-test-albums.sh`. `GaplessRealAlbumTests` finds them via
  `SIMULATOR_HOST_HOME` (or `VIBRDROME_TEST_MEDIA`) and **skips** when absent — so a green run on a
  machine without the media is not evidence; check that 5 album cases actually executed.
- **Tools:** Swift 6.3 + AVFoundation on macOS 26 (offline render works). `xcodegen` (restore
  entitlements after). Xcode 26, iOS 17+ target, sim = iPhone 17 Pro.
- **Build/QA:** `scripts/verify-build.sh` (or `--quick`) = source of truth for green.
  `swiftlint` = 0 violations required. 0 source warnings required.

---

## First moves in the new session

1. `git checkout feat/persistent-gapless-engine` (confirm `@ 68b74cb`).
2. Re-read this file + the two gapless memory files.
3. Sanity-check the proof still passes: `swift spike/gapless-proof/main.swift` → `RESULT: PASS`.
4. Start Checkpoint 3 item 3 (**ReplayGain**) — the gain-stage interface is already defined in
   `GaplessGainStage`; add the policy (album vs track gain, preamp, peak protection, 1.5x cap) and
   apply it at the *rendered* boundary with a ramp. Prove it with an offline render measuring level
   changes at boundaries and the absence of a step, before any device build.

### Open decision for the owner (not blocking)

The owner's Navidrome MP3 transcode carries no gapless metadata and measures discontinuous at every
join; its Opus transcode measures frame-exact and continuous (full table above). Switching the
transcode target to Opus, or serving originals, resolves it. Everything else (FLAC, ALAC, AAC,
stored MP3, downloaded) is already frame-exact. Not blocking any remaining checkpoint work.
