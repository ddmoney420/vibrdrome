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

---

## Phase 0 results — MetalANGLE toolchain spike — ✅ GO (2026-06-05)

Branch `feature/projectm-spike`. Goal: prove MetalANGLE still builds on the
current Xcode and renders GLES3 on a real iPhone + a Mac. **It does.**

**Build** — `scripts/build-metalangle.sh` (committed; reproducible):
- Pinned `kakashidinho/metalangle` tag **`gles3-0.0.8`** = commit **`850c87ba5b744c7c39f30c66bacdc9648d15067a`**.
- Recipe: clone pinned → `ios/xcode/fetchDependencies.sh` (git-clones glslang / SPIRV-Cross / jsoncpp from chromium.googlesource.com — **no depot_tools/gn/gclient needed**) → `xcodebuild` the dynamic-framework schemes `MetalANGLE` (iphoneos, iphonesimulator) and `MetalANGLE_mac` (macosx) → `xcodebuild -create-xcframework`.
- **Builds clean on Xcode 26** (only harmless warnings: deployment-target 9.0 floor; umbrella-header/module-map note).
- Output (gitignored, NOT committed): `Vendor/MetalANGLE/MetalANGLE.xcframework`, **51 MB total** — slices `ios-arm64` (9.1 MB), `ios-arm64_x86_64-simulator` (19 MB), `macos-arm64_x86_64` (20 MB). Ships MGLKit + `GLES3/gl3.h` headers.

**Runtime proof** — `spike/ProjectMSpike` (SwiftUI + `MGLKViewController` GLES3 clear-screen, ~30 lines; committed):
| Target | GL_VERSION | fps |
|---|---|---|
| Physical iPhone (00008150, iOS 26.5.1) | `OpenGL ES 3.0.0 (ANGLE 2.1.0.850c87ba5b74)` | **60** |
| Mac (Apple Silicon) | `OpenGL ES 3.0.0 (ANGLE 2.1.0.850c87ba5b74)` | **61** |

(The ANGLE version string embeds the pinned commit `850c87ba`, confirming provenance. Proof captured via a file the spike writes — `screencapture`/unified-log were blocked in this environment.)

**Gotcha (fixed, in spike project.yml):** the multiplatform target needed `LD_RUNPATH_SEARCH_PATHS` to include `@executable_path/../Frameworks` for the macOS bundle layout (iOS uses `@executable_path/Frameworks`); without it the Mac app dyld-crashed on the embedded framework.

**Not yet exercised:** GLES3 *render* in the iOS **simulator** (sim slice builds; device is source of truth per plan — verify/gate later). And whether projectM v4's shaders hit MetalANGLE's "GLES3 90%" gap — that's the next risk.

**Verdict:** **GO on MetalANGLE** — no Google ANGLE fallback needed. Next checkpoint: projectM v4.1.6 build (`scripts/build-projectm.sh`, needs `cmake` — not yet installed), wired to ANGLE's GLES3, **playlist library skipped for v1**.

---

## Phase 0 checkpoint 2 — projectM v4.1.6 build — 🔴 BLOCKED (2026-06-05)

Branch `feature/projectm-spike`. Goal: build libprojectM **v4.1.6** (commit `3158ee615eaafd93a8912b5f6dd84a9c47b2e00a`) as a shared xcframework wired to MetalANGLE GLES3. **Blocked at CMake configure by an upstream platform gate — projectM v4.1.6 has no Apple GLES path.** `cmake` installed (4.3.3, Homebrew).

**Whether projectM built:** No — fails at configure, before compiling anything.

**Exact error (verified, reproducible via `scripts/build-projectm.sh configure`):**
```
-- Building for OpenGL Embedded Profile
CMake Error at CMakeLists.txt:169 (message):
  OpenGL ES 3 support is currently only available for Linux platforms.
-- Configuring incomplete, errors occurred!
```
Root cause: `CMakeLists.txt` ~165–178 hard-gates `ENABLE_GLES` to `CMAKE_SYSTEM_NAME == Linux | Android` and `FATAL_ERROR`s otherwise. And `cmake/gles/FindOpenGL.cmake` only resolves `OpenGL::GLES3` on its Linux branch (`OPENGL_GLES3_INCLUDE_DIR` via `find_path GLES3/gl3.h`, `OPENGL_gles3_LIBRARY` via `find_library`); on Apple it finds only the desktop OpenGL framework.

**Exact CMake flags used:** `-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DENABLE_GLES=ON -DENABLE_PLAYLIST=OFF -DENABLE_SYSTEM_PROJECTM_EVAL=OFF -DENABLE_SYSTEM_GLM=OFF -DENABLE_SDL_UI=OFF -DBUILD_TESTING=OFF`. (Validated against the v4.1.6 option set; bundled `glm`/`hlslparser`/`SOIL2` are in-tree, `projectm-eval` submodule fetched OK at `811eea5`. These flags are correct — the block is upstream's platform guard, not the flags.)

**Output xcframework path / size:** none (blocked before build).
**Headers / modulemap status:** not reached.
**MetalANGLE / GLES linking issues:** not reached — fails inside projectM's own configure *before* any MetalANGLE wiring. The intended wiring is clear: set `OPENGL_GLES3_INCLUDE_DIR` → MetalANGLE `Headers`, `OPENGL_gles3_LIBRARY` → MetalANGLE binary, create `OpenGL::GLES3`.
**License files added:** none (no successful build to attribute yet).
**Can the spike import/link projectM yet:** No.

**Prompt conflict:** Locked decision #1 ("its OpenGL ES 3.0 rendering path … the same path the Android builds use, so it is maintained, not legacy") is true for **Android/Linux** but **false for Apple** in v4.1.6 — GLES on iOS/macOS is explicitly unsupported and `FATAL_ERROR`s at configure.

**Go/no-go: 🔴 NO-GO as-is.** Options (need your decision — patching upstream's deliberate platform support is the architecture-adjacent change to surface first):
- **(A) Patch v4.1.6:** allow Darwin in the line-169 guard **and** patch `cmake/gles/FindOpenGL.cmake` (or pre-create the target) so `OpenGL::GLES3` resolves to MetalANGLE. Risk: upstream never validated Apple GLES — likely further Apple-specific issues beyond the guard; effort unknown.
- **(B) Re-pin a newer projectM** (master / a later tag) if it added Apple/iOS GLES support — preferred if available, avoids carrying patches.
- **(C) Reconsider GL strategy** — only with your direction; do not switch architecture without approval.

**Recommendation:** quick-check option **B** (does a newer projectM support Apple GLES?) before committing to the **A** patch. Stopped here per the working agreement.

---

## Phase 0 checkpoint 2b — projectM re-pinned to master @ `4d28493` — ✅ BUILT (2026-06-05)

Investigation confirmed projectM **master** removed the Linux-only GLES guard (now `if(ENABLE_GLES) set(USE_GLES ON)`, no system-GLES `find_package`) and added macOS-framework support; the C API is identical to v4.1.6 (all needed symbols present). `scripts/build-projectm.sh` re-pinned to commit **`4d2849333b63235a6af4d1f02508a97529d96dc7`** (master @ 2026-05-08 — a fixed commit, NOT the moving branch). Chose the **newer pin over patching v4.1.6**.

**Result: projectM builds for all three slices and assembles into an xcframework — no upstream patch.**
- **CMake flags:** `-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DENABLE_GLES=ON -DENABLE_PLAYLIST=OFF -DENABLE_SYSTEM_PROJECTM_EVAL=OFF -DENABLE_SYSTEM_GLM=OFF -DENABLE_SDL_UI=OFF -DBUILD_TESTING=OFF` + per-slice `-DCMAKE_OSX_ARCHITECTURES`; iOS uses `-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos|iphonesimulator`.
- **GLES wiring:** MetalANGLE framework `Headers` added to projectM's compile include path so `#include <GLES3/gl3.h>` resolves; shared lib linked with `-Wl,-undefined,dynamic_lookup` (benign "deprecated on iOS" warning).
- **GL resolution model (key finding):** master projectM resolves GL **at runtime via a GLAD loader + `eglGetProcAddress`** — strings show `@rpath/libGLESv2.dylib`/`libGLESv3.dylib`, a `GLResolver`, `[GladLoader] GLES2`. So there are **0 undefined `gl*` symbols**; instead it exposes **`projectm_create_with_opengl_load_proc`** to receive a GL loader. Runtime wiring (next step) = create projectM via that load-proc fed by MetalANGLE's EGL `getProcAddress`, or expose MetalANGLE as `libGLESv2/3.dylib` on `@rpath`. Not a build issue.

**Output xcframework:** `Vendor/projectM/projectM.xcframework` (gitignored, NOT committed) — **7.2 MB**; slices `ios-arm64` (1.4M lib), `ios-arm64_x86_64-simulator` (2.8M), `macos-arm64_x86_64` (2.8M). Install name `@rpath/libprojectM-4.4.dylib`.
**Headers/modulemap:** `module projectM { header "projectM-4/projectM.h"; export * }` + full `projectM-4/` C API headers in each slice's `Headers/`.
**C API verified exported:** `projectm_create`, `projectm_create_with_opengl_load_proc`, `projectm_opengl_render_frame`, `projectm_pcm_add_float`, `projectm_set_window_size`, `projectm_set_preset_duration`, `projectm_set_preset_locked`, `projectm_load_preset_file/data`.

**Go/no-go: ✅ GO.** projectM builds for iOS + macOS against MetalANGLE via the master pin; the v4.1.6 blocker is resolved without patching upstream. License attribution (LGPL projectM + bundled GLM/SOIL2/hlslparser/projectm-eval) to be added when the lib is wired in. **Next: wire projectM's GL loader to MetalANGLE and render a `.milk` preset in the spike.**

---

## Phase 0 checkpoint 3 — projectM render wiring — 🔴 BLOCKED: MetalANGLE GLES 3.0 < projectM's required GLES 3.2 (2026-06-05)

Wired the spike: MetalANGLE `MGLKView` GLES3 context → `projectm_create_with_opengl_load_proc` → load `idle.milk` → synthetic stereo PCM → `projectm_opengl_render_frame_fbo`. **Build, link, dylib load all succeed; projectM instance creation returns NULL.**

**What worked (so the failure is precisely bounded):**
- `import projectM` + link + embed the xcframework. **Install-name fix needed** (re-id each dylib to its real filename in `build-projectm.sh`; otherwise dyld crashes: `Library not loaded: @rpath/libprojectM-4.4.dylib` — only the fully-versioned file is embedded, no symlink).
- projectM dylib loads; `projectm_get_version_components` → **4.1.0**.
- MetalANGLE **GLES 3.0** context created; the **GL loader works** via `dlsym(RTLD_DEFAULT, …)` (eglGetProcAddress alone won't resolve core symbols on ANGLE). projectM log: `user_resolver="yes"`.

**Exact failure** (captured via `projectm_set_log_callback`):
```
[GladLoader] GLInfo api="GLES" ver="3.0" glsl="OpenGL ES GLSL ES 3.00 (ANGLE 2.1.0.850c87ba5b74)"
             renderer="ANGLE (Metal Renderer: Apple M5 Pro)" backend="EGL" user_resolver="yes"
[GladLoader] GL requirements check failed: Version too low: 3.0
```
**Root cause:** `src/libprojectM/Renderer/Platform/GladLoader.cpp:50` → `.WithMinimumVersion(3, 2).WithMinimumShaderLanguageVersion(3, 20)`. projectM master requires **GLES 3.2 / GLSL ES 3.20**; **MetalANGLE provides only GLES 3.0** (the 2022/unmaintained "GLES3 90%" ceiling — no 3.1/3.2). projectM master also *uses* ≥3.1 features (e.g. `Framebuffer.hpp:211`, per-buffer color masks).

**Failure category:** **MetalANGLE GLES support** (hard 3.0 ceiling) vs projectM's GLES-3.2 requirement. Not loader, import, link, dylib, preset, shader, or PCM (those work or are never reached).

**Small spike-only patch realistic?** **No clean one.** Lowering projectM's `WithMinimumVersion(3,2)` to `(3,0)` passes the gate but projectM master genuinely uses 3.1/3.2 features → failure just moves to shader-compile/render. The real fix is a **GLES 3.2-capable GL provider**.

**Go/no-go: 🔴 MetalANGLE is a dead end for projectM master (GLES version ceiling).** Options:
- **(A) Google ANGLE (full/current) Metal backend** — supports GLES 3.2; this is the prompt's **pre-approved fallback** for "blocking GLES3 gaps." Cost: heavier build (depot_tools/gn/gclient) and loses MetalANGLE's MGLKit wrapper (need EGL-on-`CAMetalLayer` surface setup). **Architecture switch → needs approval before switching.**
- **(B) Older projectM that targets GLES 3.0** — but Apple-GLES support exists only on master, which requires 3.2; likely no single commit satisfies both. Patching projectM down to 3.0 + removing 3.1/3.2 feature use = heavy, risky upstream surgery.
- **(C) Reconsider** the approach.

**Recommendation:** This is the exact scenario the prompt named ("If MetalANGLE … has blocking GLES3 gaps, the approved fallback is upstream Google ANGLE's Metal backend — stop and report before switching"). **Evaluate (A) Google ANGLE**, pending approval. Stopped before switching architecture per the working agreement.

---

## Phase 0 checkpoint 4 — narrow GLES-gate patch → projectM RENDERS on MetalANGLE GLES 3.0 (2026-06-05)

**Google ANGLE ruled out at the source level (read-first, no build):** ANGLE `main` caps its Metal backend at GLES 3.0 — `src/libANGLE/renderer/metal/mtl_common.h:175` `constexpr gl::Version kMaxSupportedGLVersion = gl::Version(3, 0)`, and `DisplayMtl.mm:448` `getMaxConformantESVersion()` = `std::min(…, gl::Version(3, 0))`. Same ceiling as MetalANGLE (which is a fork of this backend); ANGLE's ES 3.2 conformance is **Vulkan-only**. No projectM "sweet-spot" commit exists either — the 3.2 gate, the GLAD/GLProbe version-check, and the `projectm_create_with_opengl_load_proc` API all landed in one commit (`c7754456d`).

**Why the patch is defensible — projectM's GLES gate is inconsistent with its own GLES code, which is ES 3.0 / GLSL ES 3.00:**
- All GLES shaders are `#version 300 es` — `Renderer/CopyTexture.cpp:7`, `Renderer/TransitionShaderManager.cpp:33`, `UserSprites/MilkdropSprite.cpp`; **no `#version 310/320 es` anywhere** in the GLES path.
- The only ES-3.1 entry point, `glColorMaski`, is `#ifdef USE_GLES`-compiled **out** in favor of `glColorMask` — `Renderer/Framebuffer.cpp:319-324`.
- **No** unconditional ES-3.1/3.2 calls (no compute, image load/store, geometry/tessellation shaders).
- The gate is a hard create-failure: `GladLoader.cpp:50-51` → `GLProbe.cpp:765` → `GladLoader::Initialize()` returns false → `ProjectMCWrapper.cpp:89` returns `nullptr`.
- So the `(3,2)/(3,20)` minimum is over-strict vs. the code it guards; lowering it to `(3,0)/(3,0)` realigns the gate with reality rather than forcing an unsupported config.

**Patch (carried, not forked):** `scripts/build-projectm.sh` → `patch_gles_gate` applies a documented `sed` to the pinned source on every checkout: `WithMinimumVersion(3,2)→(3,0)` and `WithMinimumShaderLanguageVersion(3,20)→(3,0)` in `GladLoader.cpp`. Only the GLES gate; the desktop-GL gate (`(3,3)/(3,30)`, lines 60-61) is left untouched. (LGPL: projectM is already built from source as a dynamic lib; this 2-number source change is documented and reproducible.)

**Result — macOS: ✅ projectM creates, loads the preset, and renders at 60 fps** via MetalANGLE GLES 3.0. Proof: `projectm_created=YES, version=4.1.0, preset_loaded=true, rendering=YES, fps=60`. projectM log: `GLInfo api="GLES" ver="3.0" glsl="OpenGL ES GLSL ES 3.00 (ANGLE 2.1.0.850c87ba)" renderer="ANGLE (Metal Renderer: Apple M5 Pro)"` — **no shader-compile or GL error lines** (no `pm[4]`/`pm[5]`). Preset: bundled `idle.milk` (vibrdrome_plasma). The static audit is empirically confirmed: projectM's GLES path runs on a 3.0 context.

**iPhone:** pending (device was locked at test time — iOS suspends GPU work when locked; re-run when unlocked).

**Bottom line:** MetalANGLE (already built + proven at GLES 3.0) is a viable GL provider for projectM after this narrow gate patch — **no Google ANGLE, no MoltenVK, no architecture switch.**

### Metal API Validation pass (2026-06-05) — ✅ clean on both platforms

Ran the spike with **Metal API Validation + GPU Validation + Shader Validation** enabled (`MTL_DEBUG_LAYER=1`, `METAL_DEVICE_WRAPPER_TYPE=1`, `MTL_SHADER_VALIDATION=1`):
- **macOS (M5 Pro):** rendered 485 frames @ 60fps; 10,527 lines of validation output, **all benign trace** (`End Encoding Validation` ×3156, `Set Front Facing Winding Validation` ×526) — **zero error/failure/assert/hazard lines**.
- **iPhone (A19 Pro):** launched via `devicectl --environment-variables` with the same flags (assert mode → any validation error aborts); rendered **718 frames @ 61fps, no abort, no crash report** → clean.
- **Result: no Metal validation errors on either platform** — the projectM→MetalANGLE GLES3 path is GPU-correct.

Visual confirmation (screenshot/video) is a manual step (this environment blocks programmatic screen capture); the per-second center-pixel sample (which varies over time incl. colour shifts on both devices) stands in as objective evidence of a live, non-static render.

**Phase 0 spike: COMPLETE.** Exit gate met — a moving `.milk` preset at 60fps on a physical iPhone and a Mac via MetalANGLE + patched projectM, validated clean under Metal API/GPU validation. Pinned versions: MetalANGLE `gles3-0.0.8` (`850c87ba`), projectM master `4d28493` (+ 2-line GLES-gate patch). **Phase 1 (real audio plumbing in the app) is the next phase and is NOT started — it touches the app's audio pipeline and needs explicit approval.**

---

## Phase 1 plan — PCM source and audio tap integration

**Planning section only. Phase 1 is NOT implemented. Phase 1A requires separate
approval (see §8) before any code is written.**

### 1. Scope
- Phase 1 is **audio plumbing only**.
- It adds the PCM source / ring-buffer path that projectM will eventually drain.
- It does **not** integrate projectM/MetalANGLE into the main app UI yet.
- It does **not** add the MilkDrop visualizer mode yet.
- It does **not** touch the existing "Classic" Metal/`.colorEffect` visualizer behavior.
- It does **not** commit Vendor binaries.

### 2. Risk summary
- This phase touches the **real playback/audio path**.
- The EQ tap (`EQTapProcessor`, one `MTAudioProcessingTap` per `AVPlayerItem`,
  `PostEffects`) is the **universal audio tap** — its process callback runs for
  *all* playback.
- Any mistake in the tap callback could affect **all** playback (glitches, drops,
  or a crash on the real-time thread).
- **Crossfade may have two active taps during overlap** (outgoing + incoming
  items both have live taps — `AudioEngine+Crossfade.swift`).
- **Gapless / queue advance** must hand off the PCM source cleanly.
- The audio callback must remain **real-time safe** (see §4).

### 3. Revised checkpoint plan
Phase 1 is split into four smaller, independently-approvable checkpoints.

#### Phase 1A — VisualizerPCMSource + ring buffer only
Goal:
- Add `VisualizerPCMSource` and a lock-free SPSC ring buffer.
- No EQ tap wiring yet. No `CrossfadeController` changes. No gapless/queue
  changes. No debug overlay. No projectM/MetalANGLE main-app integration.

Requirements:
- Preallocated power-of-two buffer.
- Interleaved stereo Float32 storage.
- Atomic head/tail indices.
- Drop-oldest overflow policy.
- Unit tests for write / read / overflow / underrun.
- Documentation comments explaining the real-time constraints.
- **No app behavior change** (the type exists but nothing feeds or drains it yet).

#### Phase 1B — inactive-by-default tap write
Goal:
- Wire the existing EQ tap to write PCM into `VisualizerPCMSource`.
- Keep writing **gated off** unless explicitly active — normal playback behaves
  exactly as before when inactive.
- No crossfade source ownership yet (unless strictly required).
- No renderer / projectM main-app integration yet.

Requirements (the audio callback must):
- **No allocation.**
- **No locks.**
- **No async/await.**
- **No logging.**
- **No Objective-C messaging** from the callback.
- **No temporary Swift arrays** in the callback.
- Write planar input **directly** into the preallocated interleaved ring buffer.

#### Phase 1C — crossfade/gapless source ownership
Goal:
- Ensure only **one** audible item feeds the visualizer PCM source.
- Avoid double-feeding during crossfade overlap.
- Move source ownership cleanly during gapless/queue advance.
- Confirm manual next/previous does not leak or double-feed.

Requirements:
- Per-tap or per-item ownership flag.
- The **incoming** track feeds during crossfade.
- The **outgoing** track does **not** feed during overlap.
- Produce rate stays ~1x sample rate (not 2x) during crossfade.

#### Phase 1D — dev debug overlay + verification matrix
Goal:
- Add a **dev-only** debug overlay / diagnostics view to prove the PCM pipeline.
- Show: ring fill %, produced samples/sec, consumed samples/sec, underrun count,
  overflow count, sample rate, channel count, and current source item.
- Run the full verification matrix.

Verification matrix:
- Streamed track, normal playback.
- Downloaded/offline track, normal playback.
- Gapless auto-advance.
- Crossfade overlap.
- Manual next/previous.
- 50-track-change soak test.
- `make lint`.
- `make test`.
- `make build-ios`.
- `make build-macos`.
- `scripts/verify-build.sh` (the repo's normal full gate).

### 4. Real-time audio constraints
The `MTAudioProcessingTap` process callback is a **real-time audio thread**. It:
- must **not** allocate;
- must **not** lock;
- must **not** log;
- must **not** call async code;
- must **not** call UI / `@MainActor` code;
- must **not** use temporary Swift arrays;
- must **only** copy into preallocated memory and update atomics.

### 5. Ring-buffer design note
Intended design:
- **SPSC** ring buffer.
- Single producer: the audio tap callback.
- Single consumer: the future render / debug consumer.
- Interleaved stereo Float32.
- Power-of-two capacity.
- Atomic acquire/release indices.
- Drop-oldest on overflow.
- Counters for overflow / underrun.

### 6. Crossfade/gapless risk
- Crossfade can have **two live taps** during overlap.
- Raw PCM **cannot** be double-fed (the waveform would be corrupted).
- `AudioSpectrum` may tolerate the current behavior (it sums into an FFT), but
  **projectM raw PCM will not**.
- Phase 1C must **explicitly own** which item feeds PCM.

### 7. Rollback plan
- **Phase 1A rollback:** remove the `VisualizerPCMSource` / ring-buffer files.
- **Phase 1B rollback:** disable the active flag, or revert the tap write.
- **Phase 1C rollback:** revert the source-ownership logic.
- No schema / data migration.
- No Vendor binaries.
- No projectM UI integration yet.

### 8. Phase 1A approval gate
**Before any Phase 1 implementation starts, Phase 1A requires separate approval.**

For Phase 1A approval, bring the **exact ring-buffer design** first:
- Files to add.
- Storage type.
- Atomic primitive choice.
- Capacity.
- API shape.
- How planar audio buffers will eventually be written without allocation.
- Unit test plan.
- Whether any dependency/package is required.

**Do not implement Phase 1A until approved.**

---

## Phase 1 — PCM pipeline: ✅ SIGNED OFF (on-device, 2026-06-06)

Phases 1A–1D are implemented and verified on a physical iPhone via the DEBUG-only
`PCM DEBUG` overlay (triple-tap Now Playing), on top of the green automated gate
(28 unit tests, `verify-build.sh` PASS, Release compile-out clean — 0 `PCMDebug`
symbols in the release binary).

**On-device overlay result** (David Byrne — "Big Blue Plymouth", 320 kbps MP3):
- `produced` ≈ `consumed` ≈ **43,873 fps** at **44,100 Hz · 2ch** → essentially
  exactly 1× (the ~0.5% gap is the 0.5 s rate-averaging window).
- `fill` **0 / 16,384** — drained and stable, never pinned at capacity.
- `overflow` **0** — no PCM ever lost (the key data-integrity / no-double-feed signal).
- **No red `⚠︎ produced > 1.5× sample rate` warning** — produced never spiked to 2×,
  so crossfade single-source ownership held.

**Scenarios passed:** streamed, downloaded/offline, manual next/previous, gapless
auto-advance, and **crossfade** (produced stayed ~1×, not 2×; no warning).

**Note on `underrun`:** the counter climbs (e.g. ~1,372) and is **expected /
benign** — the DEBUG dev consumer requests 4,096 frames every 60 Hz tick but only
~735 are produced per tick, so each read returns fewer than requested and bumps
the counter. It means "the consumer wanted more than was buffered," NOT dropped
audio; `overflow == 0` is the real loss indicator. The Phase 2 projectM renderer
reads only what it needs per frame, so this counter will not climb the same way.

**Phase 1 status: SIGNED OFF.** Next: Phase 2 (the projectM/MetalANGLE renderer in
the app as a new "MilkDrop" mode, draining this validated PCM ring, alongside the
existing Classic visualizer) — planning only, on approval; not started.

---

## Phase 2A — Vendor wiring + in-app GLES3 clear-screen: ✅ VERIFIED (2026-06-06)

Goal (only): the real `com.vibrdrome.app` target links + embeds the prebuilt
MetalANGLE + projectM frameworks via the fetch-pinned strategy, and a DEBUG-only
in-app `MGLKView` clear-screen proves GLES3 runs inside the app on device + Mac.
**No** projectM renderer, **no** PCM drain, **no** MilkDrop mode, **no** preset
bundle yet — those are 2B onward.

### Vendor strategy (B: fetch pinned prebuilts)
- `scripts/build-metalangle.sh` now injects a **Clang module map** into each
  framework slice so Swift can `import MetalANGLE` with no bridging header. It is
  TARGETED (MGLKit + `GLES3/gl3.h` + `EGL/egl.h` and their transitive
  `gl3platform`/`eglplatform`/`khrplatform`), deliberately excluding `gl.h`/`gl2.h`
  to avoid the GLES1/2/3 symbol-redefinition conflicts a blanket `umbrella "."`
  would cause.
- `scripts/package-vendor.sh` zips the local xcframeworks (`ditto`, to preserve the
  macOS version symlinks), emits SHA-256, and can `upload` to a GitHub Release.
- `scripts/fetch-vendor.sh` downloads the pinned Release assets, **verifies SHA-256**,
  and extracts into the gitignored `Vendor/`. Pins: tag `vendor-frameworks-v1`,
  `MetalANGLE.xcframework.zip` / `projectM.xcframework.zip`. The Release asset is
  **not published yet** — 2A was proven against local `Vendor/` and a `selftest`
  that runs the verify+extract pipeline against the local zips.
- `Vendor/` and `dist/` stay gitignored; no binaries are committed.

### App wiring (`project.yml`, Vibrdrome target only)
- Both `.xcframework`s added as `framework` deps with `embed: true codeSign: true`.
  The Widget/Watch targets do **not** link them.
- `LD_RUNPATH_SEARCH_PATHS += @executable_path/Frameworks @executable_path/../Frameworks @loader_path/../Frameworks`
  (covers iOS + macOS).
- `GCC_PREPROCESSOR_DEFINITIONS += GLES_SILENCE_DEPRECATION=1 GL_SILENCE_DEPRECATION=1`
  (MetalANGLE supplies its own GLES; silences Apple's deprecation warnings to keep
  the 0-warning gate).

### Clear-screen proof (DEBUG only, compiled out of release)
- `Vibrdrome/Features/Visualizer/Debug/MetalANGLEClearScreenView.swift` — an
  `MGLKViewController` GLES3 clear-screen writing a `GL_VERSION`/`GL_RENDERER`/fps
  proof file. Reached via Settings ▸ About ▸ Debug Tools ▸ **MetalANGLE GLES3 Test**.
- A `VIBRDROME_GL_TEST` env hook (`debugGLTestProof()`) shows the clear-screen at
  launch for headless verification — users never set it; whole hook is `#if DEBUG`.

### Verification results
- **Bridging decision:** the **module map worked** (`import MetalANGLE`) — no
  bridging header was needed. (Fallback header was designed but not used.)
- **iOS device (iPhone 17 Pro Max, A19 Pro):** `OpenGL ES 3.0.0 (ANGLE / Metal
  Renderer: Apple A19 Pro GPU)`, `rendering=YES`, **60 fps**.
- **macOS (Apple M5 Pro):** same GL version, `Metal Renderer: Apple M5 Pro`,
  `rendering=YES`, **61 fps**.
- **otool:** the app debug dylib loads `@rpath/MetalANGLE.framework/MetalANGLE`
  (iOS) / `…/Versions/A/MetalANGLE` (mac) and `@rpath/libprojectM-4.4.1.0.dylib` on
  both; frameworks embed under `…/Frameworks`.
- **Release compile-out:** `nm` finds **0** `MetalANGLEClearScreen` / `debugGLTestProof`
  symbols in the Release iOS + macOS binaries; the frameworks are still embedded
  (linked deps, used from 2B).
- **`scripts/verify-build.sh`: RESULT: PASS** (SwiftLint 0, iOS/macOS/watchOS
  0-warning builds, unit + UI rotation tests).
- **Size (informational):** on-device arm64 embedded delta ≈ **10.6 MB**
  (MetalANGLE 9.2 MB + projectM 1.4 MB). Universal/simulator slices are ~2× that;
  the authoritative thinned App Store delta is deferred to an archive/TestFlight
  build before release (Phase 2 decision #3).

### CI follow-up (deferred — not wired in 2A)
The cloud `Build iOS` / `SwiftLint` merge-gate workflow (`.github/workflows/ci.yml`)
runs on PRs to `main` and will need a **`scripts/fetch-vendor.sh` step before the
build** (so the gitignored `Vendor/` is populated in CI). This is **intentionally
not edited yet** — `ci.yml` is the protected merge gate and this branch is not yet
PR'd to `main`. Wire it during PR/main prep, alongside publishing the
`vendor-frameworks-v1` Release so `fetch-vendor.sh` has live assets.

**Phase 2A status: VERIFIED, awaiting commit approval.** Next: 2B (projectM renderer
draining the PCM ring) — design first, separate approval.
