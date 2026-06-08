# Permissive Native Visualizer — Design Notes (Research Step 1)

**Status:** documentation only. No code, no shaders, no Swift. Survey of high-level
rendering techniques in our own words, plus a proposed v0 minimal feature set.

These notes are written from general computer-graphics concepts, Apple Metal
documentation, and our own existing code (`Shaders.metal`, `AudioSpectrum`,
`VisualizerPCMSource`). No projectM, Butterchurn, or `.milk` source was consulted.
Provenance is tracked in `provenance-log.md`.

The aim is an **original** Vibrdrome engine. We describe *what each technique is* and
*how it would map onto Metal and our app* — not anyone else's implementation.

---

## 1. Render-to-texture / offscreen passes
**Concept.** Instead of drawing straight to the screen, a frame is built up in one or
more intermediate (offscreen) textures, then composited to the drawable. This lets a
frame be processed in stages — draw geometry, then post-process, then present.

**How it maps here.** A native engine would use an `MTKView`/`CAMetalLayer` with its
own render pipeline and a small set of offscreen color textures sized to the drawable.
This is fundamentally different from our Classic path (SwiftUI `TimelineView` +
`Rectangle().colorEffect`, a single-pass fragment effect with no persistent
intermediate buffers). Offscreen passes are the prerequisite for feedback (§2) and
blur (§7).

**v0:** in scope — it's the foundation for everything else.

## 2. Ping-pong feedback
**Concept.** The signature "trails / tunnels / motion-smear" look comes from sampling
the **previous** frame, transformed slightly (scaled, rotated, warped) and faded
(decayed), then drawing the new frame on top. Because reading and writing the same
texture in one pass is unsafe, two textures are alternated: read from A, write to B;
next frame read from B, write to A — "ping-pong."

**How it maps here.** Two offscreen textures, swapped each frame. Each frame: sample
the prior texture through a warp + decay, composite the new audio-reactive layers,
present. Decay rate, warp strength, and zoom become preset parameters.

**v0:** in scope — this is the single most important effect; without it the engine is
"just a shader," not a feedback visualizer.

## 3. Warp mesh
**Concept.** A grid of vertices laid over the frame, where each vertex's texture
coordinates are nudged per-frame by a function of position + time + audio. Sampling
the feedback texture through this distorted grid produces swirls, zooms, ripples, and
tunnels. (A pure fullscreen-quad fragment warp is a simpler special case; a real mesh
gives smoother, more controllable large-scale motion.)

**How it maps here.** Start with a fullscreen-quad fragment-level warp (cheapest);
evaluate a coarse vertex grid later if more organic motion is needed. The warp
function is driven by preset parameters + audio uniforms.

**v0:** in scope, **fragment-level warp first**; vertex grid deferred unless needed.

## 4. Spectrum texture and scalar audio uniforms
**Concept.** Audio reaches the shader two ways: (a) a small **1-D texture** holding the
current frequency spectrum (so the shader can index "energy at frequency x"), and
(b) a handful of **scalar uniforms** (overall level, bass, mid, treble, beat) for
cheap, broad reactions.

**How it maps here.** We already produce both kinds of data: `AudioSpectrum.shared`
(FFT bands + bass/mid/treble) and `VisualizerPCMSource` (raw interleaved-stereo PCM
ring). The engine uploads the band array into a 1-D texture each frame and passes the
scalars as a uniform buffer. **No new audio plumbing** — we consume existing outputs.
If the PCM ring is used, its single-consumer discipline applies.

**v0:** in scope — scalar bass/mid/treble uniforms first; the 1-D spectrum texture
right after.

## 5. Waveform overlay
**Concept.** A line/curve traced from the raw audio samples (the oscilloscope look),
drawn over the field. Adds a crisp, directly-audio-coupled element on top of the
softer feedback motion.

**How it maps here.** Read a window of samples from the PCM ring, build a thin line
strip (or render it in a fragment pass from a samples texture), composite additively.
Color/opacity/thickness become preset parameters.

**v0:** deferred to a later iteration (nice-to-have; not needed to prove the
architecture). Keep the data path in mind so it slots in cleanly.

## 6. Palettes / color mapping
**Concept.** Visual interest comes largely from color. A scalar "intensity" field is
mapped through a **palette** (a color lookup table / gradient) rather than used as raw
grayscale. Cycling or audio-shifting the palette gives life without changing geometry.

**How it maps here.** A small 1-D gradient texture (the palette) sampled by an
intensity value; palette selection + an animated offset are preset parameters. Cheap
and high-impact.

**v0:** in scope — a few built-in palettes; palette index + offset as parameters.

## 7. Blur / bloom
**Concept.** Softening and glow. A **separable Gaussian blur** (horizontal pass then
vertical pass, each cheap) smooths the feedback; a **bloom** adds glow by blurring the
bright parts and adding them back. Both are extra offscreen passes.

**How it maps here.** One or two downsampled blur passes on the feedback texture, with
an optional bright-pass for bloom. Blur amount/threshold become parameters. Cost is
the main concern on device — keep passes downsampled.

**v0:** a single light blur pass in scope; full bloom deferred (cost/quality tradeoff
to measure in Step 2).

## 8. Beat-reactive parameter mapping
**Concept.** Beyond continuous bass/treble levels, a **beat/onset** signal (a sudden
energy jump) can trigger discrete events — a zoom pulse, a palette flip, a warp kick.
This is what makes a visualizer feel "on the beat" rather than just "loud-reactive."

**How it maps here.** Reuse the band energy we already compute; derive a simple onset
signal (energy rising sharply above a short running average) on the app side and feed
it as a uniform/event. We are **not** importing anyone's beat detector — a basic
threshold-over-moving-average is general DSP, written by us.

**v0:** a minimal onset→pulse mapping in scope; richer tempo tracking deferred.

## 9. Preset-to-preset transitions
**Concept.** Switching presets shouldn't hard-cut. A **crossfade** blends the old and
new looks over a short window; because the engine already feeds the previous frame
back, a transition can also be expressed as temporarily blending two parameter sets or
two output textures.

**How it maps here.** Cross-blend either the parameter sets (cheap, if presets share a
fixed-function shape) or two rendered textures (general, costlier). Mirrors the smooth
preset switching we already do for projectM via `hardCut: false`.

**v0:** deferred — single preset first; design the parameter model so a future
crossfade is a blend of two parameter structs.

---

## Proposed v0 minimal feature set
The smallest engine that proves the architecture and can host a plausibly-shippable
preset:

**In scope for v0**
- `MTKView`/`CAMetalLayer` engine with offscreen passes (§1).
- Ping-pong feedback with decay + zoom (§2).
- Fragment-level warp driven by parameters + audio (§3).
- Scalar audio uniforms (bass/mid/treble), then a 1-D spectrum texture (§4).
- Palette color mapping with a few built-ins + animated offset (§6).
- One light blur pass (§7).
- Minimal beat/onset → pulse mapping (§8).
- One **original Vibrdrome preset** expressed as a parameter set.

**Deferred (post-v0)**
- Vertex-grid warp mesh (§3), waveform overlay (§5), full bloom (§7), tempo tracking
  (§8), preset crossfades (§9), the preset-format/DSL design (research step 3).

**Explicit constraints carried forward**
- No `.milk` parser/importer; no MilkDrop-compatibility promise.
- Permissive/own-licensed only; no LGPL/GPL; no projectM/Butterchurn code.
- Reuse `AudioSpectrum` + `VisualizerPCMSource`; no new audio plumbing.
- Must coexist with Classic (SwiftUI shaders) and projectM (`MGLKView`) surfaces and
  honor reduce-motion / photosensitivity / simulator gating.

**Sets up Step 2:** a DEBUG-only `MTKView` ping-pong feedback prototype reacting to
`AudioSpectrum`, targeting ~60 fps on a physical device, with this v0 feature set.
