# projectM / MilkDrop Visualizer — Integration Plan

**Status:** STEP 0 — orientation & assumption-check only. No code, scripts, vendor
binaries, `project.yml`, or dependency changes yet. Branch: `feature/projectm-spike`
(off `develop` @ `7bd3dd3`). Research/spike only — not part of the next build.

**Verification legend:** ✅ verified directly in repo · ⚠️ from sub-agent map, not
yet re-read line-by-line · 🔴 conflicts with the integration prompt · ❓ open
question to confirm before proceeding.

---

## 1. Confirmed repo facts

- ✅ **XcodeGen owns the project** (`project.yml`); never edit `.xcodeproj` directly. Swift 6, `STRICT_CONCURRENCY: complete`.
- ✅ **Deployment targets: iOS 18.0 / macOS 15.0** (`project.yml` → `options.deploymentTarget`). Build env is Xcode 26.x per `CLAUDE.md` (the `xcodeVersion: "16.0"` field in `project.yml` is only an XcodeGen compat hint).
- ✅ **Existing visualizer** lives in `Vibrdrome/Features/Visualizer/` — exactly two files: `VisualizerView.swift` (~449 lines) and `Shaders.metal` (~898 lines).
- ✅ **Audio pipeline** lives in `Vibrdrome/Core/Audio/` — `AudioEngine` (`@MainActor final class`, singleton) facade + topic extensions (`+Playback`, `+Crossfade`, `+Queue`, `+Observers`, `+Radio`, …), plus `EQTapProcessor`, `AudioSpectrum`, `EQEngine`, `CrossfadeController`, `NowPlayingManager`.
- ✅ **Single `MTAudioProcessingTap` per `AVPlayerItem`**, created by `EQTapProcessor.createAudioMix(track:)` and attached via `item.audioMix` in `AudioEngine.applyEQTapIfNeeded(to:)`. The tap is installed **unconditionally** ("tap stays active always", `AudioEngine.swift:468`) — present whether or not EQ is enabled.
- ✅ **Out of scope per repo + prompt:** watchOS app, widget, CarPlay.

## 2. Conflicts / corrections vs. the prompt

| # | Prompt claim | Reality | Impact |
|---|---|---|---|
| 🔴 | "current repo deployment targets iOS 17+ / macOS 14+" (locked decision #7) | ✅ **iOS 18.0 / macOS 15.0** | None for projectM/MetalANGLE support; doc/CMake min-version flags must target 18/15, not 17/14. |
| 🔴 | "the existing **18 Metal shader presets**" | ✅ 18 presets, but rendered via **SwiftUI `TimelineView` + `.colorEffect`** with `[[stitchable]]` MSL functions — **not** an MTKView / CAMetalLayer / Metal render-pass architecture. | The new projectM mode needs its **own** GL surface (`MGLKView`); it cannot share or extend the existing SwiftUI shader path. They coexist as two independent surfaces — confirms "Classic" vs "MilkDrop" can sit side by side without rewriting Classic. |
| 🔴 | Android "real projectM engine with **50+ presets**" | ✅ Repo actually bundles **21 `.milk` presets** (`app/src/main/assets/presets/`). README is aspirational. | Parity target is ~21 curated presets (reuse the same files), expandable later. |
| 🔴 | Feed **float stereo** via `projectm_pcm_add_float(..., PROJECTM_STEREO)` (locked #4) | ✅ Android feeds **`PROJECTM_MONO`, unsigned 8-bit** (`nativeAddAudioData(ByteArray)` → JNI `PROJECTM_MONO`). | iOS plan (float stereo) is *higher quality* than Android and is fine with projectM — but it is a **deviation from Android**, not strict parity. Recommend keeping float-stereo on iOS; note the divergence. |
| 🔴 | Use the **projectM playlist C API** (`playlist.h`, `projectM-4-playlist`) (locked #3) | ✅ Android **does not** ship/​use the playlist lib (no `playlist.h` in `cpp/projectM-4/`); it manages presets itself (`nativeSelectRandomPreset`, `projectm_set_preset_duration`). | Either approach works. Using the playlist lib on iOS is a reasonable choice but is **not** how Android does it — decide consciously in Phase 2. |

None of these are blockers; they are corrections so we don't build against false assumptions.

## 3. Existing visualizer architecture (✅ verified)

- `VisualizerPreset: String, CaseIterable` enum, **18 presets** (Plasma, Aurora, Nebula, Waveform, Tunnel, Kaleidoscope, Particles, Fractal, Fluid, Rings, Spectrum, Vortex, Lava Lamp, Starfield, Ripple, Fireflies, Prism, Ocean). Each maps to a `[[stitchable]]` function in `Shaders.metal`.
- Render: `TimelineView(.animation(paused:…)) { Rectangle().colorEffect(preset.shader(size:input:)) }` (`VisualizerView.swift:142`). A 60 Hz `Timer` pushes `bass/mid/treble/energy/bands/peaks` into `@State` from `AudioSpectrum.shared`; falls back to a simulated beat when energy is ~0.
- Presentation: `.fullScreenCover(isPresented: appState.showVisualizer)` (`NowPlayingView.swift:156`); toolbar button `.visualizer` case (`NowPlayingView+iOS.swift`), gated by `showVisualizerInToolbar` and `disableVisualizer`.
- Accessibility: **Reduce Motion** (`UserDefaultsKeys.reduceMotion` freezes the loop), **Disable Visualizer** (`disableVisualizer` hides the button), and a first-run **photosensitivity warning** (`visualizerWarningShown`). The new MilkDrop mode must honour all three.
- UX: popover preset picker; drag-horizontal cycles presets, drag-down dismisses; tap toggles controls (auto-hide 6 s).

**Plan:** add a **mode picker (Classic / MilkDrop)**; the new mode is a separate `MGLKView`-hosting representable presented through the same `showVisualizer` entry point, reusing the warning/Reduce-Motion/disable gating.

## 4. Audio / EQ-tap architecture (✅ verified)

- One tap per item (`EQTapProcessor.createAudioMix`, `kMTAudioProcessingTapCreationFlag_PostEffects`). The **process callback** (`EQTapProcessor.swift:186`):
  1. `MTAudioProcessingTapGetSourceAudio`;
  2. applies a 10-band biquad EQ per channel with **pre-gain anti-clip** (`preGain`, `:205–225`) + a hard clamp safety net (don't remove — `CLAUDE.md`);
  3. extracts **first channel only** → `AudioSpectrum.shared.processPCM(samples, count:, sampleRate:)` (`:258`).
- Buffer format: **non-interleaved / planar Float32**, one `mData` per channel in the `AudioBufferList`; **item-native sample rate** + channel count from `processingFormat` in `tapPrepare`. (Sub-agent said "interleaved" — ❌ corrected: it's planar.)
- `AudioSpectrum` is a **consumer, not a tap owner**: 2048-pt vDSP FFT → 32 log bands; `@unchecked Sendable`, single-writer accumulator on the audio thread, `OSAllocatedUnfairLock` for main-thread reads. It does **not** expose raw PCM — projectM needs raw PCM, so it cannot reuse `AudioSpectrum`'s output, but it can tap the **same point**.
- ❓ **No general-purpose lock-free ring buffer exists** in the repo (only `AudioSpectrum`'s private FFT accumulator). We must add an SPSC ring buffer for the visualizer.

## 5. Can one tap feed both EQ and visualizer PCM? — ✅ YES

The prompt's assumption holds, with nuance:
- `AudioSpectrum` is **already** a second consumer of the single EQ tap. The projectM ring-buffer feed becomes a **third consumer** added next to `EQTapProcessor.swift:258` — **no new tap**, no tap-ownership fight.
- Caveat: the EQ tap is **PostEffects** and the PCM there is **EQ'd + pre-gain-attenuated + clamped**. For a visualizer this is acceptable (it reacts to what you hear); document it. If we ever want pre-EQ PCM we'd need a second `PreEffects` tap — **not** recommended for v1.
- The feed must produce **interleaved stereo** for `projectm_pcm_add_float(..., PROJECTM_STEREO)` by interleaving the two planar channel buffers in the callback (currently only channel 0 is read for FFT).

## 6. Gapless / crossfade topology risks

- ✅ **Gapless** (`AVQueuePlayer`): tap attached per item, including the lookahead item, so the audible item always has a live tap. Low risk.
- ⚠️/❓ **Crossfade** (dual `AVPlayer` via `CrossfadeController`): during the overlap **both** items have taps → **both would feed the ring buffer → corrupted/double-fed waveform** for projectM. (`AudioSpectrum` tolerates this because it sums into an FFT; raw-PCM projectM does not.) The prompt's rule — *feed only the incoming track during crossfade* — is therefore mandatory and needs a **per-tap "is-audible" gate** (e.g. a tap-context flag the engine flips on swap; or only the active-player's tap writes to the ring). ❓ Also confirm whether the crossfade incoming-item tap is attached unconditionally or only `if eqEnabled` (sub-agent noted an `eqEnabled` guard on that path — must verify, since it would gate visualizer PCM on EQ during crossfade).

## 7. MetalANGLE / projectM build risks (the genuinely hard part)

- **iOS has no native OpenGL ES** → we need **MetalANGLE** (GLES→Metal). Android does **not** need this (the NDK gives native GLES), so the iOS toolchain is materially harder than the Android one — most spike risk is here, not in Swift.
- Cross-compiling **libprojectM v4** (CMake, `ENABLE_GLES`, **shared** library for LGPL) for iOS device + iOS sim + macOS, and pointing projectM's GL loader at ANGLE's GLES3 headers/dylib.
- ⚠️ **Simulator** ANGLE-on-Metal is historically flaky (prompt acknowledges) → **device is source of truth**; gate the backend out of the simulator with a runtime message if needed.
- Approved fallback if MetalANGLE is unbuildable/has GLES3 gaps: **upstream Google ANGLE Metal backend** — **stop and report before switching** (do not switch unilaterally).
- Swift 6 strict-concurrency real-time constraints: RT-safe tap writes into a preallocated SPSC ring; render thread confines `projectm_handle` + GL context; `@unchecked Sendable` only on the thread-confined wrapper, documented.

## 8. LGPL / dynamic-linking requirements

- **libprojectM is LGPL-2.1** → link as a **dynamically-linked, embedded, signed framework** (`projectM.xcframework`), never static; verify with `otool -L`. Vibrdrome being MIT/open-source satisfies the relinking/source-availability obligation, but we still must ship **license text + attribution**.
- **MetalANGLE / ANGLE** are BSD-style → attribution.
- ❓ Confirm whether an in-app **licenses/about screen** already exists (Settings) to add projectM + ANGLE entries; if not, add one in Phase 3. Pin exact versions/commits in this doc.

## 9. Preset-pack / parity notes (Android, ✅ from source)

- Android: real **projectM v4** via JNI (`cpp/projectM-4/*.h`, `projectm_jni.cpp`) + `visualizer/ProjectMBridge.kt`, screen `ui/player/VisualizerScreen.kt`.
- **21 bundled `.milk` presets** in `app/src/main/assets/presets/` — community "cream of the crop" (Geiss, Rovastar, Aderrasi, Zylot, EoS, Mstress, Stahlregen, …) **plus 3 custom** `vibrdrome_kaleidoscope/plasma/tunnel.milk`. **Reuse these same files for cross-platform visual parity.**
- C API used: `projectm_create`, `projectm_set_window_size`, `projectm_opengl_render_frame`, `projectm_set_preset_duration`, plus its own random-preset selection (no playlist lib).
- PCM: **mono, unsigned-8-bit** on Android (we will use float-stereo on iOS — note the divergence, §2).
- UX: swipe-to-cycle + random preset; configurable preset duration. ❓ exact default duration / shuffle / hard-cut values not captured from `VisualizerScreen.kt` yet — confirm during Phase 0/2.

## 10. Recommended Phase 0 spike plan

Exactly as the prompt's Phase 0, **outside the app target**, in `spike/ProjectMSpike/` + `scripts/`, so nothing touches the app, lint, or CI:
1. `scripts/build-metalangle.sh` → `MetalANGLE.xcframework` (iOS device+sim+macOS) into `Vendor/MetalANGLE/`; pin exact commit.
2. `scripts/build-projectm.sh` → CMake cross-compile **libprojectM v4** (pinned tag, GLES, **shared**) → `projectM.xcframework` into `Vendor/projectM/`; expose headers via modulemap; document the ANGLE-GLES3 wiring in script comments.
3. Standalone spike app: `MGLKView` (`kMGLRenderingAPIOpenGLES3`) → `projectm_create` → load one bundled idle preset → feed a synthetic 440 Hz sine + AM noise as PCM → render.
4. Reuse Android's 21 `.milk` files as the preset corpus.

## 11. Exact files proposed to add/change NEXT (Phase 0 — pending your approval)

**Add only (no app-target / `project.yml` / committed binaries until approved):**
- `scripts/build-metalangle.sh`, `scripts/build-projectm.sh`
- `spike/ProjectMSpike/` (standalone minimal Xcode project + tiny Swift/MGLKit harness)
- `Vendor/MetalANGLE/`, `Vendor/projectM/` (**gitignored** build outputs; commit the *scripts*, not the binaries — binary-vs-fetch decision deferred to you per the working agreement)
- this doc (`docs/projectm-integration-plan.md`), updated with observed results

**Explicitly NOT touched in the spike:** `project.yml`, the app target, `Features/Visualizer/` (the existing 18-preset Metal/Classic path), `Core/Audio/`, any dependency manifest, entitlements, CI.

## 12. Exit criteria for the spike (Phase 0 gate)

- A **moving, audio-reactive** `.milk` preset rendering at **~60 fps on a physical iPhone and on a Mac**, with **Metal API validation enabled and clean**.
- Recorded in this doc: observed fps (device + Mac), any required **GLES3 extensions/workarounds**, simulator status (works / gated-out), and pinned MetalANGLE commit + libprojectM tag.
- A clear **go / no-go** on MetalANGLE: if it can't build or has blocking GLES3 gaps, **stop and report** with exact errors before considering the Google-ANGLE fallback.

---

## Open questions to resolve before/within Phase 0–1

1. ❓ Crossfade tap: is the incoming-item tap attached unconditionally or only `if eqEnabled`? (Affects visualizer PCM during crossfade.) — verify in `AudioEngine+Crossfade.swift`.
2. ❓ Confirm an in-app licenses/about screen exists (or plan to add one) for LGPL/ANGLE attribution.
3. ❓ Decide: projectM **playlist library** vs. self-managed presets (Android does the latter).
4. ❓ Commit policy for `Vendor/*.xcframework` (binary in-repo vs. reproducible fetch) — your call per the working agreement.
5. ❓ Capture Android's exact default preset duration / shuffle / hard-cut values from `VisualizerScreen.kt` for parity.
