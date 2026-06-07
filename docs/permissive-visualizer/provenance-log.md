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

## Third-party dependencies considered
None in Steps 1–4. (Any future permissive dependency must have its license recorded
here before use.)
