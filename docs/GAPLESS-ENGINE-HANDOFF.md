# Persistent Gapless Engine — Session Handoff

**Written:** 2026-08-03 · **Branch:** `feat/persistent-gapless-engine` @ `cb9c59b` (off `develop @ 3d82895`)

Resume point for building the persistent-output gapless audio engine. Self-contained — read this
top to bottom and you have everything to continue in a fresh session.

---

## TL;DR

Gapless playback is the **active release gate**. Build 60 release prep is **stopped**. The
AVQueuePlayer path has two proven transition defects that no AVQueuePlayer-level fix resolves, so
we are **rewriting playback onto a persistent-output `AVAudioEngine` graph**. **Checkpoints 1, 2 and
3 items 1–4 are done and objectively proven** (frame-continuous across every boundary, for every
delivery format, with EQ bypassed / neutral / audible, with ReplayGain changing at boundaries, and
with both visualizer consumers attached). Next is **Checkpoint 3 items 5–6** (queue/repeat/shuffle/
seek parity, background + lock-screen + remote control), then **Checkpoint 4** (one consolidated
device build + acceptance).

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
feat/persistent-gapless-engine @ cb9c59b   ← work here
develop                        @ 3d82895   ← Build 60 fixes, DO NOT TOUCH
diag/gapless-queue-matrix      @ bc4b2d6   ← throwaway DEBUG diagnostics, never merge
```

**Committed on this branch (19fd966 — Checkpoint 1 + 2):**
- `Vibrdrome/Core/Audio/Gapless/GaplessRenderFormat.swift` — render-format policy.
- `Vibrdrome/Core/Audio/Gapless/GaplessScheduler.swift` — pure frame-accounting.
- `Vibrdrome/Core/Audio/Gapless/PersistentGaplessEngine.swift` — persistent graph + offline render.
- `VibrdromeTests/Core/GaplessEngineOfflineTests.swift` — objective frame-continuity tests.
- `spike/gapless-proof/main.swift` — standalone repro (`swift main.swift`).

**Committed on this branch (fbb1c0f — Checkpoint 3 item 5, partial):**
- `GaplessPlaybackQueue.swift` — authoritative queue mirror, slot identity, generation, item states.
- `GaplessTransportPolicy.swift` — repeat/manual-skip/previous policy + seedable smart shuffle.
- `GaplessPlaybackSession.swift` — session: planning, transport, seek, render-frame-driven events,
  completion/scrobble accounting.
- `GaplessVisualizerAdapters.swift` — Classic + Native adapters on the shared feed.
- `GaplessEngineSelector.swift` — fallback reasons + capability policy.
- Tests: `GaplessPlaybackSessionTests`, `GaplessVisualizerAdapterTests`, `GaplessEngineSelectorTests`.

**Committed on this branch (21dfbf3 — Checkpoint 3 items 3–4):**
- `Vibrdrome/Core/Audio/Gapless/GaplessReplayGain.swift` — policy map, calculator, diagnostics.
- `GaplessGainStage` — boundary-aligned gain events, cancellation, measured mixer smoothing.
- `GaplessVisualizerTap.swift` → `GaplessVisualizerFeed` — one tap, per-consumer bounded rings.
- Tests: `GaplessReplayGainTests`, `GaplessReplayGainOfflineTests`, `GaplessVisualizerFeedTests`.
- Spike: `gapless-replaygain-ramp`.

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

## What's DONE — Checkpoint 3 items 3–4 (ReplayGain + visualizer feed)

**ReplayGain** reproduces the existing policy exactly (off/track/album; album falls back to track
gain; preamp added before conversion; fallback dB for untagged material; flat 1.5x ceiling), applied
through the persistent gain stage at the frame each track becomes audible — the boundary frame comes
from the scheduler's own segment map, so a gain change cannot drift from its track. Nothing is baked
into cached files or decoded PCM; the EQ's `globalGain` is untouched.

**Two gaps in the existing policy, reported not silently fixed:**
1. `trackPeak` / `albumPeak` are fetched, cached and persisted but **never used** — there is no
   peak-based clipping prevention today, only the flat 1.5x cap. The new calculator supports it,
   **off by default**, because enabling it changes playback levels.
2. There is **no "automatic" mode** — only off/track/album, global across radio/playlists/albums/
   single tracks. None was invented. If one is wanted later, the proposal to document first is:
   album gain for sequential album playback, track gain for shuffle/radio/search/mixed playlists.

**The ramp finding.** `AVAudioMixerNode.outputVolume` already interpolates internally — measured at
10% in ~2.5 ms, 50% at ~16 ms, 90% at ~28 ms — and **never steps**, verified across jumps up to
1.5x → 0.25x where an unsmoothed change would have produced a delta of ~0.5. An explicit ramp of our
own would convolve with that and could only make the transition *longer*, never sharper. So the
node's own interpolation is the ramp, and the engine's job is to start it on the right frame. Equal
consecutive gains skip the set entirely, so an album-gain join is completely untouched.

**Gain order and clipping policy:** `player → ReplayGain (gain stage) → EQ (+ its own clip guard) →
output mixer`. The two attenuations are deliberately separate and both apply: the EQ clip guard
offsets *EQ's own* boost and is a function of EQ gains alone; ReplayGain matches loudness between
tracks and is a function of track metadata alone. Neither reads the other, so there is no hidden
double attenuation — only two independent guards that happen to compose.

**Visualizer feed:** one tap on the persistent `outputMixer`, after gain and EQ so it shows what is
heard. Installed once, survives every boundary, and is never removed because a visualizer closed —
opening/closing changes *consumers*. Each consumer holds its own bounded `FloatRingBuffer`, which
keeps that type's single-producer/single-consumer contract intact while Classic and Native both read
the same audio. The callback copies and nothing else: no allocation, no FFT, no UI, and it never
waits on the consumer lock (it drops a buffer and counts it instead).

**Measured cost:** EQ bypassed 0.004% of one core, EQ active 0.14%, ReplayGain 0.004%, visualizer
callback 67 µs per consumer per 1024-frame buffer = **0.29% of the 23.2 ms deadline** (0.58% for
both consumers), zero drops when drained at 60 Hz, memory flat in every state. Device CPU/thermal/
battery remain a Checkpoint 4 measurement.

**Measurement caveat worth keeping:** under offline manual rendering the engine *batches* tap
callbacks (~1 per render slice instead of one per 1024 frames) and dispatches them off the render
loop — timings taken there describe the rendering mode, not real-time playback. The visualizer cost
above is measured by driving the copy path directly.

---

## What's DONE — Checkpoint 3 item 5 (partial): the playback session layer

**One authoritative queue.** Queue *content* stays owned by the app; `GaplessPlaybackQueue` is the
single place it is mirrored into the engine and adds only derived state
(pending → preparing → ready → scheduled → audible → completed, plus cancelled/failed). No second
hidden queue. Slots carry their own identity because a queue can legitimately contain the same song
twice.

**Generation.** Structural changes bump a monotonic generation; *advancing* through the queue does
not, because that would needlessly invalidate preparation that is still correct. Async work carries
its generation and is discarded when superseded.

**Events come from rendered frames**, never from a download, decode, or accepted buffer. Scrobble
eligibility reproduces production exactly: half the effective duration, capped at 240 s, one
eligible scrobble per play.

**Two modelling bugs the tests caught** (worth not rediscovering): keying "already audible" on item
identity swallowed every Repeat One replay — the same slot becomes audible again at a *new frame*,
which is a new play; and carrying the per-play scrobble flag across a repeat suppressed the second
play's scrobble. Both now key on the boundary.

**Existing semantics mapped and preserved:** Previous restarts past **3 s**; manual navigation
overrides Repeat One; and — the important one — **shuffle is not a permuted playlist**. Production
picks the next index on the fly, preferring a different artist and excluding
current/planned/recently-played. So there is **no original order to restore** and **no reshuffle on
a Repeat All wrap**. Both are existing user-visible behaviour, documented rather than "fixed".
Randomness is injectable, so tests are deterministic while production stays random.

**Visualizer adapters are wired** to the real `AudioSpectrum` and `VisualizerPCMSource`. Each drains
its own bounded ring *off* the render thread, so the FFT (which allocates) never runs in the audio
callback. Open/close/switch leave the tap installed exactly once and the graph untouched.

---

## What's DONE — the real-time playback path (`cb9c59b`)

**The graph now runs in real time against hardware output.** A capability probe established this
first: the test host *can* start the graph in real time and the player node's sample clock advances.
That is why the results below are from actually-rendered audio rather than offline renders — worth
re-checking on any new machine before trusting real-time test results.

- **Backend abstraction** (`GaplessRenderBackend`): init, connect, format, schedule, start, pause,
  resume, stop, tail replacement, render position, failure reporting. Both backends consume the
  **same** `GaplessPreparedTrack` values and segment model — one scheduler, not two.
- **Lifecycle**: `idle → prepared → starting → playing → paused → stopping → idle`, plus `failed`
  from any active state. `starting`/`stopping` exist so a duplicate Play or an overlapping stop/start
  is *rejected* rather than raced (verified: three Plays activate the session once).
- **Cold-launch preserved**: building the graph, preparing files and scheduling audio are all
  verified NOT to activate the session. Only `start()`/`resume()` do, and activation is injected so
  the step stays visible instead of hiding in a side effect.
- **Audible-frame clock**: player node time → engine render time → timeline frame → queue item →
  source-relative frame → elapsed seconds, in one place, so no two consumers can disagree.
- **Boundaries are clock-driven, not callback-driven.** A completion callback says a segment finished
  *feeding*, which on this architecture is a whole track before it is heard.
- **Play-instance identity** is separate from slot and song identity, because Repeat One replays the
  same slot and each replay is its own play. Verified: three replays → three distinct instances.

**A real bug the tests caught, worth not rediscovering:** the hardware clock can run **backwards**
across a tail rebuild (measured 1411 after an earlier 2351). Elapsed time, boundary detection and
seek all derive from it, so `renderFrame` now enforces monotonicity at the source rather than each
caller defending against it.

**Evidence:** 20 automatic transitions on one continuously running engine (one boundary per play
instance, no duplicates, no node replacement); four-part album start to finish; pause preserves
position and tail across cycles; stop invalidates future events and leaves the graph reusable; tail
reset keeps the timeline monotonic; session-activation failure and a missing file leave a known
state without corrupting the timeline.

---

## What's NEXT — real-time integration still to do

The real-time *path* exists; the real-time *integration* does not. Still outstanding:

- **Now Playing / metadata** — the session emits `becameAudible` at the correct frame; nothing is
  wired to `NowPlayingManager` yet.
- **Scrobbling** — eligibility is computed correctly; nothing calls `OfflineActionQueue` yet.
- **Restoration, audio session, background** — untouched. The Build 60 cold-launch fix (launch must
  not interrupt Spotify/YouTube) must be preserved when this is wired.
- **Lock screen / remote commands** — untouched.
- **Seek latency and manual-skip interruption** — cannot be measured without a real-time path.
- **Soak / performance under real playback** — same.
- **End-to-end acceptance through actual audio** — the acceptance sequences are proven at session
  level; they have not been run through rendered audio with frame assertions.

Also still outstanding on the real-time path itself: driving the session's transport (Next /
Previous / seek / queue mutation) through the real backend, real-time tail replenishment via
`GaplessPrefetchWindow`, real encoded-format transitions in real time (only the synthetic tone album
has been run), live visualizer-adapter measurements, and real-time CPU/memory/deadline figures.

**Do not request a Checkpoint 4 device build until these are done.**

---

## What's NEXT — Checkpoint 3 items 5 (rest) and 6

Real integration, each gated by **automated frame-continuity + state tests before any device build**:

1. ~~**Streaming/cached-file**~~ — **DONE** (see above).
2. ~~**EQ** in the persistent graph~~ — **DONE** (see above).
3. ~~**ReplayGain**~~ — **DONE** (see above).
4. ~~**Visualizer feed**~~ — **DONE** (feed + tap). Still to do: point the real `AudioSpectrum`
   (Classic) and `VisualizerPCMSource` (Native) at `GaplessVisualizerFeed` consumers when playback
   moves onto this engine — the feed is ready, the adapters are not wired.
5. **Queue / repeat / shuffle / seek parity** — including cancelling scheduled gain events on every
   queue mutation (`cancelScheduledReplayGain(fromFrame:)` exists and is tested; the call sites do
   not exist yet because queue integration is this item).
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

1. `git checkout feat/persistent-gapless-engine` (confirm `@ cb9c59b`).
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

---

## The retained-memory investigation and the buffer-scheduler rewrite (branch `feat/persistent-gapless-buffer-scheduler`)

**Branch:** `feat/persistent-gapless-buffer-scheduler`, off `feat/persistent-gapless-engine @ ac7c24e`.
`feat/persistent-gapless-engine` is **parked** until this passes its acceptance gate.

### Accepted root cause

> In the tested persistent `AVAudioPlayerNode` configuration, `scheduleSegment` retains each supplied
> `AVAudioFile` and file descriptor until the player node is stopped. This makes long uninterrupted
> sessions unbounded in both memory and descriptors.

Proven in `VibrdromeTests/Core/GaplessCallbackOwnershipTests.swift` by direct lifetime evidence —
weak boxes on the files, deinit sentinels on the closures, `/dev/fd` counts — not by footprint
inference:

| Probe | Live files | fdΔ |
|---|---|---|
| opened, never scheduled | 0/40 | 0 |
| scheduled, all callbacks fired, 2 s settle, no stop | 40/40 | +40 |
| scheduled, then `player.stop()` | 0/40 | 0 |
| scheduled inside an explicit `autoreleasepool`, no stop | 40/40 | — |
| `scheduleBuffer` (PCM), no stop | 0/40 | — |

The completion-handler matrix (500 tracked schedules per variant) showed ~30 KB and one descriptor
per schedule for **every** variant — no closure, `.dataConsumed`, `.dataRendered`, `.dataPlayedBack`
— with **zero outstanding closures** in all of them. The production closure was `{ _ in }`: empty
capture list, no retain path. Closure capture is not causal; autorelease timing is not causal.

**Rejected as the final fix:** session-long per-URL `AVAudioFile` identity. It only moves the bound
from *transitions* to *distinct tracks*, and descriptors — not memory — become the binding
constraint on a long queue.

### Substrate

    source file → bounded decode → reusable AVAudioPCMBuffer pool → scheduleBuffer

The player node never receives an `AVAudioFile` in this path.

- `GaplessPCMChunkSource` — opens the file, seeks to the trimmed start, reads bounded chunks, and
  **closes the file as soon as its audio is read**, while its chunks are still scheduled. Rejects a
  source whose decoded format does not match the graph (that is the converter stage's job, not
  something to paper over). Carries a process-wide live-file counter so file lifetime is observed
  directly rather than inferred from descriptors.
- `GaplessBufferPool` — a *fixed* set of `AVAudioPCMBuffer` objects allocated once. Starves rather
  than allocates; refuses a duplicate release so one buffer can never back two chunks.
- `GaplessBufferScheduler` — keeps N chunks scheduled ahead, crosses track boundaries inside its own
  produce loop so the last chunk of A and the first of B are back to back, and recycles on
  completion. The callback captures **only** a `GaplessRecycleToken` (four scalars) and the inbox.

**Callbacks are for recycling only.** Audible boundaries stay clock-driven off the per-track
`segments` records — a completion callback reports the node finished with a buffer, which is not the
instant the next track became audible.

### Recycle point: measured, not assumed

All three points keep captured audio intact at pool capacity 6 *and* with **no headroom at all**
(capacity == scheduled depth), with zero starvations. Correctness does not discriminate, so the
choice is slack: `.dataConsumed` returns a buffer earliest and gives the pump the most time. It is
the default.

### Chunk size: measured

| chunk | sched | cb/s | CPU | pool | starv | tail | seek | order | gap |
|---|---|---|---|---|---|---|---|---|---|
| 2048 | 3.9 µs | 20.4 | 4.1% | 96 KB | 0 | 4.69 ms | 10.57 ms | OK | 0.0000 s |
| **4096** | **3.9 µs** | **11.1** | **3.7%** | **192 KB** | **0** | **3.86 ms** | **10.65 ms** | **OK** | **0.0000 s** |
| 8192 | 4.2 µs | 5.6 | 3.5% | 384 KB | 0 | 4.79 ms | 10.64 ms | OK | 0.0000 s |
| 16384 | 2.8 µs | 3.7 | 2.7% | 768 KB | 0 | 5.10 ms | 10.63 ms | OK | 0.0000 s |
| 32768 | 4.5 µs | 1.9 | 3.2% | 1536 KB | 0 | 5.14 ms | 10.77 ms | OK | 0.0000 s |

**4096 frames** (93 ms; 4 chunks ≈ 372 ms of lead) — the smallest size with no starvation that does
not double the callback rate for nothing. A discarded warm-up run precedes the matrix: the audio
stack's one-time allocation otherwise lands entirely on whichever candidate runs first.

### Checkpoint A result — 1,000 transitions, fresh file every time

    baseline tx 100   fp 137.5 MB  fd 31  files 3  pool 2/4  chunks 4  segs 15
    window   tx 1100  fp 137.6 MB  fd 28  files 0  pool 3/3  chunks 3  segs 12
    RESULT   1000 transitions  growth 0.03 MB (0.03 KB/tx)  fdΔ -3  peakFd 31
             peakFiles 3  starvations 0  chunks 2200 scheduled / 2200 recycled
             after stop: fp 137.5 MB  fd 28  files 0

Against the file scheduler's ~30 KB and one descriptor per transition. 64 distinct sources (larger
than any cache it would be safe to hold open), enqueued at most three ahead as the preparation
window does, and **no player-node stop anywhere in the run**.

### Harness correction (worth knowing before trusting a capture)

`GaplessRealTimeCapture` installs its tap on `mainMixerNode` **before** `engine.start()`, so it asks
for 44.1 kHz and then receives **48 kHz** buffers once the mixer adopts the output node's rate
(measured ratio 1.0885 = 48000/44100). Analysis that assumed one timebase stretched every span it
measured. The capture now records `observedSampleRate` from the delivered buffers, and span analysis
scales by it.

Separately: `heardSequence` slides a fixed window across the whole capture, so a window straddling a
track boundary contains two tones and can report **a third frequency that was never played**. Use
`tonesInTrackInteriors` — it maps captured audio onto the span the scheduler claims for each track.
Both effects looked exactly like scheduler defects and were not.

### Known limitation carried into Checkpoint E

`GaplessBufferScheduler` places each track's timeline record from the **declared** `renderFrames`
(`segments.last?.endFrame`) but advances the chunk cursor by frames **actually produced**. Those
agreed exactly in every run here (timeline 158760/158760 over 24 transitions), because the trim
policy resolves lengths from the decoded file. A truncated or mis-declared file would make them
diverge, and boundary detection reads the segment records — so the divergence would show up as a
boundary at the wrong frame rather than as an error. Reconcile the record against produced frames
when a track's final chunk is scheduled, as part of transport integration.

### Checkpoint B — explicit PCM conversion (DONE)

**Stable graph format.** Fixed by Vibrdrome, not adopted from the device: `PersistentGaplessEngine`
connects every node with `GaplessRenderFormat.standard` — 44,100 Hz, 2 ch, Float32,
non-interleaved, 8 bytes/frame, 1 frame/packet — and holds it for the life of the engine. Measured
live: the mixer reports 44,100/2 before and after a mixed-format album, with no graph reconstruction.
Route-driven reconstruction stays a later system-integration concern. Note the output *node* runs at
48 kHz on this host; the graph does not follow it, which is why the capture tap needed calibrating.

**Substrate.** `source file → bounded decode → GaplessPCMConverter → fixed buffer pool →
scheduleBuffer`. `GaplessPCMChunkSource` is now a pure source-format reader; the converter belongs to
the scheduler, because converter lifetime is a policy question a single track must not decide.

**Frames are counted, never computed.** A track's segment record opens when its first chunk is
scheduled and is *reconciled to actually produced output* when its last chunk is scheduled.
`renderFrames` and the rate ratio are planning estimates only. This closes the Checkpoint A gap.

Measured 48 kHz → 44.1 kHz, four 24,000-frame parts: **22,050 produced each, diff 0**, tiling
0 / 22,050 / 44,100 / 66,150. Real Navidrome Opus (48 kHz mono, `wholeFile` trim), four parts:
**480,000 source frames → 441,000 output frames each, diff 0**, total 1,764,000, fd delta 0.

**Truncated input.** A file cut on disk shortens *its own* record and the next track starts at the
real end — `t0:0+11025, t1:11025+22050` for both the direct and converted paths. Note a WAV header
that merely *claims* more audio is resolved by `AVAudioFile` from the real data, so it never reaches
the scheduler; the bytes have to actually be missing.

**Converter lifecycle — measured, and the result is a constraint, not a preference.** On one
sample-continuous 48 kHz sine split into four parts:

| lifecycle | built | reused | boundary step | interior step | ratio | gap |
|---|---|---|---|---|---|---|
| perTrack | 4 | 0 | 0.04200 | 0.03998 | 1.05 | 0.0000 s |
| reuseWhileFormatMatches | 4 | 0 | 0.04200 | 0.03998 | 1.05 | 0.0000 s |

Reuse measured **0 in every run**. Not a bug: reuse is gated on the retained converter not being held
by a live source, and the preparation window keeps up to three tracks enqueued at once, so the
previous track's converter is still in use when the next is prepared. Handing one `AVAudioConverter`
to two concurrently-converting tracks would interleave their input into one resampler state. **Object
reuse is therefore structurally unavailable under the preparation window, and per-track converters
are what the architecture actually permits.** A boundary/interior step ratio of 1.05 on a continuous
sine says the per-track prime-and-flush cycle produces no click.

**Channel policy.** Mono→stereo up-mixes with the frame count unchanged (22,050 in, 22,050 out, both
channels identical). Stereo passes through. **More than two channels is refused** with
`unsupportedChannelCount` — an explicit capability result, pending an owner decision on downmix.
Channels are never silently dropped. (Note `AVAudioFormat(commonFormat:sampleRate:channels:...)`
returns nil above stereo without an explicit layout.)

**Conversion failure**, all four injection points — pool returns to 6/6, no segment claims a span
that was not produced, segments still tile, no file left open:

    creation          enqueueFailures 2  productionFailures 0  segments []
    beforeFirstOutput enqueueFailures 0  productionFailures 2  segments []
    afterChunks(2)    enqueueFailures 0  productionFailures 2  segments [f0:8192, f1:8192]
    flush             enqueueFailures 0  productionFailures 2  segments [f0:44100, f1:44100]

Cancellation mid-conversion returns every buffer (6/6), clears live files to 0, bumps the tail
generation, and re-anchors the cursor.

**Mixed format** — 44.1/2 → 48/1 → 44.1/1 → 48/2, each landing at 22,050 render frames, tiling
exactly, graph unchanged.

**Chunk size reconfirmed under conversion** (2048/4096/8192): all correct, zero starvation, zero gap;
4,096 keeps half the callback rate of 2,048 at comparable CPU. **Default unchanged at 4,096.**

**Long acceptance runs are gated.** `chunkSizeComparison`, `chunkSizeUnderConversion` and the
1,000-transition runs are minutes-long real-time audio. Ungated they ran in parallel with every other
audio suite and the test process restarted with "unexpected exit, crash, or test timeout", taking
unrelated suites down with it. They now follow the soak/hour convention:

    TEST_RUNNER_GAPLESS_BUFFER_GATE=1 xcodebuild ... -only-testing:VibrdromeTests/GaplessBufferMemoryTests test

The gapless buffer suites are also `@Suite(.serialized)` — overlapping `AVAudioEngine` instances,
one of them in manual rendering mode, destabilise the process.

**1,000-transition acceptance, every transition converting** (48 kHz mono, 64 distinct sources):

    converted=false  growth 0.19 MB  fdΔ -5  peakFiles 3  liveConverters 0  chunks 2200/2200
    converted=true   growth 0.00 MB  fdΔ -2  peakFiles 2  liveConverters 0  convBuilt 1100
                     starvations 0   after stop: fd 26, files 0

Converters are built per track (1,100 over the run) and every one is released as its track drains —
live count returns to 0, so nothing is retained because a track merely finished.

### Still to do

- **Checkpoint C** — full format + transport integration, processing/Now Playing/scrobble parity,
  removal of the production `AVAudioFile` cache in `GaplessRealTimeBackend`.
- **Checkpoint D** — genuine `TEST_RUNNER_GAPLESS_SOAK=full` and `TEST_RUNNER_GAPLESS_HOUR=1` runs.

Checkpoint 4 (device build) stays blocked until D passes.
