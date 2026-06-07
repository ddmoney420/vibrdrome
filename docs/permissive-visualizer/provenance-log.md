# Permissive Native Visualizer — Provenance Log

**Append-only.** Records the source category consulted for each major technique/idea
and affirms no third-party code was copied or ported. This protects the engine's
clean-room status (see `docs/permissive-visualizer-spike.md`).

**Source categories** (allowed): `apple-metal-docs`, `general-cg-concept`,
`general-dsp-concept`, `our-own-code` (existing Vibrdrome source), `our-design-notes`.

**Forbidden** (never a source): projectM source, Butterchurn source, community `.milk`
presets, or any near-translation of the above. None were used for any entry below.

Every bundled preset will additionally carry an authorship note (added when presets
are authored, research step 3+).

---

## Research Step 1 — technique survey (2026-06-06)

All entries below are concept-level only; design prose was written in our own words in
`design-notes.md`. **No third-party code copied or ported** for any entry.

| # | Technique | Source category | What was taken (concept, our words) |
|---|---|---|---|
| 1 | Render-to-texture / offscreen passes | apple-metal-docs, general-cg-concept | The general idea of drawing into intermediate textures before presenting; mapped to an MTKView render pipeline. No third-party code. |
| 2 | Ping-pong feedback | general-cg-concept | The general technique of alternating two textures to read the prior frame while writing the next (trails/feedback). Our own decay/warp framing. No third-party code. |
| 3 | Warp mesh | general-cg-concept | The general idea of distorting texture lookups by position/time to produce swirl/zoom/tunnel motion; we chose a fragment-warp-first plan. No third-party code; no `.milk` equation language consulted. |
| 4 | Spectrum texture + scalar audio uniforms | our-own-code, general-cg-concept | Feeding audio to shaders as a 1-D spectrum texture + scalar uniforms; sourced from our existing `AudioSpectrum` / `VisualizerPCMSource`. No third-party code. |
| 5 | Waveform overlay | general-dsp-concept, our-own-code | The oscilloscope concept of tracing raw samples as a line; data from our PCM ring. No third-party code. |
| 6 | Palettes / color mapping | general-cg-concept | The general LUT/gradient idea of mapping a scalar field through a color palette. No third-party code. |
| 7 | Blur / bloom | apple-metal-docs, general-cg-concept | Separable Gaussian blur and bright-pass bloom as standard post-process passes. No third-party code. |
| 8 | Beat-reactive parameter mapping | general-dsp-concept, our-own-code | A basic onset signal as "energy rising above a short running average," derived from band data we already compute. Standard DSP, written by us. No third-party beat detector consulted. |
| 9 | Preset-to-preset transitions | general-cg-concept, our-design-notes | The general crossfade idea (blend two parameter sets or two output textures). Mirrors our existing smooth-switch behavior. No third-party code. |

**Affirmation:** for Research Step 1, no projectM, Butterchurn, or community `.milk`
source was opened, referenced side-by-side, copied, ported, or translated. The survey
relied on general graphics/DSP concepts, Apple Metal documentation, and our own
existing Vibrdrome code.

## Research Step 2 — feedback prototype (2026-06-06)

DEBUG-only Metal prototype (`PermissiveFeedbackRenderer` + `PermissiveVisualizerView`).
No third-party code copied or ported; no projectM / Butterchurn / `.milk` consulted.

| Technique | Source category | Notes (our words) |
|---|---|---|
| ping-pong feedback | general-cg-concept | two alternating `rgba16Float` textures; our own decay/zoom/rotate framing |
| fragment warp + decay | general-cg-concept | warp the prior-frame sample around center, fade by decay; original |
| procedural palette | general-cg-concept | hand-rolled 3-stop gradient with a shifting position; original |
| radial audio pulse | our-own-code | soft pulse scaled by `AudioSpectrum` bass/mid/treble (our existing DSP) |
| fullscreen-triangle pass | apple-metal-docs, general-cg-concept | standard 3-vertex fullscreen draw; original implementation |

**Guardrail:** the inline Metal source is a **hardcoded DEBUG constant** compiled at
runtime (`makeLibrary(source:)`) solely to keep the prototype out of the release
metallib. It is **NOT** a downloaded/arbitrary-shader system; future user/community
presets must not compile arbitrary shader code without a separate security/provenance
review.

## Research Step 3 — preset format v0 + example presets (2026-06-06)

Original Vibrdrome preset format (`docs/permissive-visualizer/preset-format-v0.md`)
and two original presets (`vibrdrome_aurora`, `vibrdrome_pulse`). No third-party code
or preset content copied/ported; no projectM / Butterchurn / `.milk` consulted.

| Item | Source category | Notes (our words) |
|---|---|---|
| v0 preset schema | our-design-notes | parameters-only JSON; field set derived from our Step-2 engine knobs |
| `vibrdrome_aurora` / `vibrdrome_pulse` | our-own-code | original presets authored from the parameter knobs; not derived from any preset |
| palette selection (2 built-ins) | general-cg-concept | hand-rolled gradients selected by index; original |

**Guardrail:** the format is **parameters only** — no embedded shader code or
expressions; a preset can never execute arbitrary code. Presets load from **inline
DEBUG strings** (`PermissivePresetLibrary`), so **no `.json` is bundled into the app**;
the `docs/.../presets/*.json` files are reference examples, never app resources.

## Research Step 4 — visual-depth (bloom + spectrum overlay) (2026-06-06)

Added two DEBUG-only visual-depth features + two original presets. No third-party
code or preset content copied/ported; no projectM / Butterchurn / `.milk` consulted.

| Item | Source category | Notes (our words) |
|---|---|---|
| light bloom | general-cg-concept | bright-pass + small 3×3 box blur at half-res, added in present; our single-pass approach |
| audio-spectrum overlay | general-cg-concept, our-own-code | glowing curve whose height follows `AudioSpectrum.bands` (our existing FFT); original |
| `vibrdrome_nebula` / `vibrdrome_spectrum` | our-own-code | original presets authored from the parameter knobs |

**Guardrails intact:** format remains **parameters only** (no shader/expression
execution); presets load from **inline DEBUG strings** (no `.json` bundled). The
overlay uses `AudioSpectrum.bands` only — **not** `VisualizerPCMSource` — so the
engine stays independent of projectM's PCM-ring consumer model.

## Research Step 6 — flow-field engine rewrite + onset detector + cosine palette (2026-06-06)

DEBUG-only rewrite of the motion model and colour pipeline after the Step 5 visual gate
failed (see `step5-postmortem.md`). New hero `vibrdrome_flux`. No third-party code or
preset content copied/ported; no projectM / Butterchurn / `.milk` consulted.

| Item | Source category | Notes (our words) |
|---|---|---|
| value noise + 2-octave fbm | general-cg-concept | standard hash/value-noise/fbm; original constants |
| curl-noise advection | general-cg-concept | advect the prior frame along the curl of an fbm potential (divergence-free → circulating, non-centered flow); our own formulation |
| legacy center fallback gate | our-own-code | the old rotate/zoom warp kept only for `flow == 0` presets |
| spectral-flux onset detector | general-dsp-concept, our-own-code | positive band-to-band flux vs a rolling average → attack/decay `beatPulse`; standard onset DSP, written by us from our `AudioSpectrum.bands` |
| cosine-gradient palette | general-cg-concept | IQ-style `a + b·cos(2π(c·t + d))`; original coefficients, dark base for depth |
| vignette / depth falloff | general-cg-concept | radial edge darkening on the hero path |
| beat-driven flow/bloom/hue | our-own-code | route `beatPulse` to flow acceleration, bloom kick, and a small hue shift |

**Guardrails intact:** format remains **parameters only** (`flow`/`flowScale`/`beatFlow`/
`beatBloom`/`hueDrift` are floats with safe `decodeIfPresent` defaults; no shader/expression
execution; **no `.milk`**). The onset detector reads `AudioSpectrum.bands` only — **not**
`VisualizerPCMSource`. Presets still load from **inline DEBUG strings** (no `.json` bundled).
No projectM/Classic/CI/Vendor/release changes.

## Research Step 7 — waveform-into-feedback (raw PCM, fine-line look) (2026-06-06)

DEBUG-only addition after Step 6 still read as a soft field with no fine detail. The audio
**waveform** is now drawn as thin bright additive geometry into the feedback texture so the
warp/flow/tunnel loop pulls it into filaments. No third-party code or preset content
copied/ported; no projectM / Butterchurn / `.milk` consulted — only the projectM PCM *feed*
(`VisualizerPCMSource`, our own code) is read, DEBUG-only.

| Item | Source category | Notes (our words) |
|---|---|---|
| waveform line into feedback | general-cg-concept, general-dsp-concept | oscilloscope line traced from PCM, drawn additively into the feedback field; the feedback-of-a-line filament idea is general CG; our own implementation |
| circular / horizontal waveform | general-dsp-concept | map PCM around a circle (radius = base + sample) or across a scope; original |
| raw PCM source | our-own-code | reads `VisualizerPCMSource` (our existing ring) via the DEBUG `setActiveForTesting` flag, only while the spike screen is visible; never while projectM owns the ring |
| tunnel pull | general-cg-concept | sample slightly outward so the field flows toward the viewer; original |
| additive line blend + bloom glow | apple-metal-docs, general-cg-concept | standard additive blending; thin bright lines glow via the existing bloom pass |

**Step 7b follow-ups (visual feedback):** fixed an `atan2` branch-cut seam in the hero hue
(switched to a smooth radial driver — general-cg); added a **bilateral vertical-axis mirror**
(`symmetry`, a simple L/R fold — general-cg, not a polar kaleidoscope) and a **vibrance**
saturation/brightness lift (`vibrance` — general-cg). No third-party source consulted.

**Step 7c "wow" rework:** all five presets moved onto the flow engine, each with a distinct
cosine palette (idx 2–6 — original coefficients, general-cg) and personality. Added
**field spin** (`spin`, time/beat rotation — general-cg), **beat amplitude burst**
(`beatWave`, scales the waveform deviation on the onset — our own DSP mapping), **quad
symmetry** (`symmetry 2`, a rectilinear 4-fold — general-cg, not polar), and **colour-dance**
(treble→hue, bass→brightness, from our own `AudioSpectrum`). No projectM/Butterchurn/`.milk`
consulted; no third-party code or preset content copied.

**Guardrails intact:** the format stays **parameters only** (`waveStyle`/`waveAmp`/
`waveBright`/`tunnel`/`symmetry`/`vibrance` are scalars with `decodeIfPresent` defaults; the
preset carries no shader code, expressions, or PCM). PCM use is **DEBUG-only**, enabled solely while the
native-visualizer screen is on-screen and gated off when projectM owns the ring — the
**shipping projectM consumer path is unchanged**. Presets still load from inline DEBUG
strings (no `.json` bundled). No projectM/Classic/CI/Vendor/release changes.

## Research Step 8 — polar warp + envelope followers (the vortex) (2026-06-07)

DEBUG-only. Adds a polar feedback warp (the hero path) and smoothed audio envelopes, after
the busy spin/quad additions failed to "wow". General-CG/DSP concepts; no third-party code
or preset content copied; no projectM / Butterchurn / `.milk` consulted.

| Item | Source category | Notes (our words) |
|---|---|---|
| polar warp (radius/angle) | general-cg-concept | decompose to polar, modulate angle by radius+time (swirl), zoom radius per frame (tunnel); recompose with cos/sin (seam-free); our own formulation |
| band-limited spectral-flux punches | general-dsp-concept, our-own-code | positive per-frame band rises grouped into bass/mid/treble, peak-held + decay; robust to clipped/loud levels (a fast/slow level EMA collapsed to 0 when bands pinned at 1.0); standard onset DSP, written by us from `AudioSpectrum.bands` |
| punch-driven modulation | our-own-code | route bass/mid/treble punches to zoom/swirl/brightness/bloom; continuous bands kept secondary |

**Guardrails intact:** parameters-only (`swirl`/`swirlFreq`/`warpMode`, `decodeIfPresent`
defaults; no shader code/expressions/PCM in the preset). No new busy effects — this dials the
look toward a restrained polar vortex. Continuous bands secondary; `beatPulse` kept for hits.
No projectM/Classic/CI/Vendor/release changes.

**Known limitation (DEBUG prototype):** the raw-PCM feed (`pcm=on/off` in the proof) is
intermittent — it depends on the playing item being the EQ tap's designated visualizer
source, which is not always set the instant the spike screen opens. When `pcm=off` the
waveform falls back to a synthesized line; the vortex, punch, and beat reactivity are
unaffected. PCM source-designation hardening is deferred (not in scope for 8a).

## Research Step 8b — Kaleidoscope (kaleidoscope waveform family) (2026-06-07)

DEBUG-only. New `vibrdrome_kaleidoscope` preset + a present-time polar wedge fold. General-CG
concept; no third-party code or preset content copied; no projectM / Butterchurn / `.milk`
consulted.

| Item | Source category | Notes (our words) |
|---|---|---|
| polar wedge fold (kaleidoscope) | general-cg-concept | wrap the angle into N wedges + mirror within each (reflected, seam-free via cos/sin recompose); applied at present only; original |
| fold the field, not the geometry | our-design-notes | fold the already-waveform-fed/warped field at sample time; feedback physics stay un-folded so it doesn't collapse to a centred blob (the Step 5 failure) |
| asymmetric source for the fold | our-design-notes | a kaleidoscope only mirrors *angular* detail; the source is intentionally asymmetric (curl-flow `warpMode 0` + horizontal scope `waveStyle 2`) so the wedges show distinct detail — a rotationally-symmetric source (polar vortex + circular wave) folds back to a plain circle |
| treble-driven mandala rotation | our-own-code | slow time drift + `treblePunch` rotate the wedge pattern |

**Why this isn't the Step 5 mirror failure:** Step 5 folded a soft structureless field around
the centre → "wet galaxy / blob". Kaleidoscope folds a field that already carries fine PCM-waveform
filament structure, folds **only at present** (the recursive feedback stays un-folded), and
keeps a dark base + thin bright lines — so the fold multiplies detail into a mandala instead
of smearing.

**Guardrails intact:** parameters-only (`kaleido` Int, `decodeIfPresent → 0`; no shader
code/expressions/PCM in the preset). `kaleido 0` leaves every other preset unchanged. No
projectM/Classic/CI/Vendor/release changes.

## Research Step 8c — Radiant (radial spectrum spokes family) (2026-06-07)

DEBUG-only. New `vibrdrome_radiant` preset — the first spectrum-geometry family. General-CG
concept; no third-party code or preset content copied; no projectM / Butterchurn / `.milk`
consulted.

| Item | Source category | Notes (our words) |
|---|---|---|
| radial spectrum bars | general-cg-concept, our-own-code | the 32 `AudioSpectrum.bands` mapped to filled radial bars (length = band energy), procedural in the present pass; our own formulation |
| bilateral band fold | general-cg-concept | fold the bands around the vertical axis so the halo is symmetric/ornamental, not a left-to-right bar graph |
| anti-debug-graph treatment | our-design-notes | thin angular gaps (crisp rays) + additive bright on a dark field + per-band hue + bloom/beat flash, so it reads as an EQ halo, not an overlay |
| punch-driven dynamics | our-own-code | `bassPunch` breathes the inner radius, `treblePunch` rotates, `beatPulse` flashes; the bands are the geometry |

| feedback spoke injection | our-own-code, general-cg-concept | present-only spokes read flat, so a second variant draws the same procedural spokes INTO the feedback field (`spokeInject 1`) so they bloom (bloom pass) + trail (feedback decay); bands buffer bound to the feedback pass; original |
| spoke oscillation overlays | general-cg-concept, our-own-code | Spectral Spokes adds three overlaid oscillations — a traveling sine ripple along each spoke (vibrating string), per-band sine tip wobble, and the real PCM circular waveform (`waveStyle 1`) overlaid; standard sine/oscilloscope ideas, our own formulation |
| whirlpool warp + spiral twist | general-cg-concept | center-weighted rotational warp (angle ∝ 1/r) on the feedback sample coord, plus a radius-dependent twist on the spoke angle so the rays bend into spiral arms drawn into the centre (a drain/vortex); the L/R `symmetry` mirror re-symmetrizes it; original |

**Scope note:** two variants — `vibrdrome_radiant` (present-only, sharp) and
`vibrdrome_spectralspokes` (injected → bloom + trails). No concentric rings in this checkpoint.

**Guardrails intact:** parameters-only (`spokes`/`spokeInject` Int, `spokeLen` Float,
`decodeIfPresent → 0`; no shader code/expressions/PCM in the preset). `spokes 0` leaves every
other preset unchanged. No projectM/Classic/CI/Vendor/release changes.

## Third-party dependencies considered
None in Steps 1–8c. (Any future permissive dependency must have its license recorded
here before use.)
