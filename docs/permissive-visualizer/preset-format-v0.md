# Permissive Native Visualizer — Preset Format v0 (Research Step 3)

A minimal, **parameters-only** preset format for the native Metal feedback engine.
Original Vibrdrome format — **not** `.milk`, no projectM/Butterchurn lineage.

## Design constraints
- **JSON / Swift `Codable`**, **versioned** (`version`).
- **Parameters only** — no embedded shader code, no expressions, no executable content.
  A preset can never run arbitrary code; it only sets numeric/string knobs the engine
  already understands. (This enforces the spike guardrail against a downloaded-shader
  system.)
- **Sandbox-safe by construction** and forward-migratable via `version`.
- **Original presets only.**

## Where presets live
- **In the spike:** the prototype loads presets from **inline DEBUG string constants**
  (`PermissivePresetLibrary`, `#if DEBUG`). **No `.json` is bundled into the app** —
  the `Vibrdrome/` resource glob would otherwise ship `.json` in Release, which we do
  not want for a spike.
- **These `docs/permissive-visualizer/presets/*.json` files are reference /
  authorship examples only** — documentation, never app resources. They match the
  inline copies byte-for-byte in intent.

## Fields (v0)
| Field | Type | Meaning |
|---|---|---|
| `version` | int | format version (currently `1`) |
| `id` | string | stable identifier, e.g. `vibrdrome_aurora` |
| `name` | string | display name |
| `author` | string | preset author (`Vibrdrome`) |
| `license` | string? | preset license (placeholder `permissive-tbd` until the community-license decision) |
| `decay` | float | feedback persistence, 0..1 |
| `zoom` | float | base per-frame feedback zoom |
| `rotate` | float | base per-frame feedback rotation |
| `paletteIndex` | int | palette: 0/1 = legacy 3-stop (fallback only); 2–6 = cosine-gradient themes (2 deep-space, 3 aurora, 4 fire, 5 nebula, 6 rainbow) |
| `paletteShift` | float | palette position offset |
| `pulseScale` | float | radial audio-pulse intensity |
| `zoomBass` | float | audio mapping: bass → extra zoom |
| `rotateTreble` | float | audio mapping: treble → extra rotation |
| `pulseBass` | float | audio mapping: bass → pulse |
| `bloomStrength` | float? | (Phase 4) glow intensity, 0..1 (0 = off). `decodeIfPresent` → 0 |
| `waveformStrength` | float? | (Phase 4) audio-spectrum overlay intensity, 0..1 (0 = off). `decodeIfPresent` → 0 |
| `flow` | float? | (Phase 6) curl-noise flow-field advection strength, 0..1. **0 = legacy center path.** `decodeIfPresent` → 0 |
| `flowScale` | float? | (Phase 6) spatial frequency of the flow field. `decodeIfPresent` → 2.5 |
| `beatFlow` | float? | (Phase 6) `beatPulse` → flow acceleration. `decodeIfPresent` → 0 |
| `beatBloom` | float? | (Phase 6) `beatPulse` → bloom kick. `decodeIfPresent` → 0 |
| `hueDrift` | float? | (Phase 6) colour drift speed for the cosine-palette path. `decodeIfPresent` → 0 |
| `waveStyle` | int? | (Phase 7) waveform geometry: 0 = off, 1 = circular, 2 = horizontal scope. `decodeIfPresent` → 0 |
| `waveAmp` | float? | (Phase 7) waveform displacement amount. `decodeIfPresent` → 0 |
| `waveBright` | float? | (Phase 7) waveform line brightness (the glow). `decodeIfPresent` → 0 |
| `tunnel` | float? | (Phase 7) zoom-in pull that drags the lines into a tunnel/spiral. `decodeIfPresent` → 0 |
| `symmetry` | int? | (Phase 7b/c) 0 = off, 1 = vertical (L/R) mirror, 2 = quad (4-way) kaleidoscope. `decodeIfPresent` → 0 |
| `vibrance` | float? | (Phase 7b) saturation + brightness multiplier for the flow path (1 = neutral). `decodeIfPresent` → 1.0 |
| `spin` | float? | (Phase 7c) field rotation speed (time + beat driven). `decodeIfPresent` → 0 |
| `beatWave` | float? | (Phase 7c) `beatPulse` → waveform amplitude burst (the kick "explosion"). `decodeIfPresent` → 0 |

`bloomStrength`, `waveformStrength`, `flow`, `beatFlow`, `beatBloom`, and `hueDrift` are
**optional** and default to `0` when absent; `flowScale` defaults to `2.5`. Older
`version: 1` presets remain valid (the field set is a backward-compatible superset).

### Phase 6 — flow engine + beat reactivity (still parameters-only)
`flow > 0` switches the feedback pass from the legacy center rotate/zoom to **curl-noise
advection** (a divergence-free flow field, so trails circulate instead of collapsing to
the center). Beat reactivity comes from a **spectral-flux onset detector** (host side) that
emits a `beatPulse` envelope; `beatFlow`/`beatBloom` route it to flow/bloom, and continuous
bass/mid/treble remain secondary. Colour for `paletteIndex >= 2` uses a **cosine-gradient
palette** (vivid, no muddy midpoint, dark base for depth). These are all **parameters** —
no shader code, expressions, or executable content in the preset.

### Phase 7 — waveform-into-feedback (the fine-line look)
`waveStyle > 0` draws the live audio **waveform** as a thin bright additive line **into the
feedback texture** each frame; the warp/flow/`tunnel` loop then pulls each frame's line into
the next → glowing **filaments and tunnels** (the MilkDrop/projectM fine-detail look).
The waveform geometry is built **host-side from raw PCM** (`VisualizerPCMSource`,
**DEBUG-only**, enabled only while the native-visualizer screen is visible and never while
projectM owns the ring). Still **parameters-only** — the preset selects a style and
intensities; it does not carry code, expressions, or PCM.

## Example presets (authorship notes)
- **`vibrdrome_flux` ("Flux")** — original Vibrdrome preset; **hero (Phase 6 → 7)**. A
  bright **circular waveform** (`waveStyle 1`) drawn into the feedback and dragged into
  glowing filaments by curl-`flow` + `tunnel`; the spectral-flux `beatPulse` punches
  flow/bloom/tunnel/line brightness; cosine-gradient hero palette (idx 2); no center
  transform (`zoom`/`rotate` = 0). Authored from scratch for the flow engine; not derived
  from any third-party preset.
All five presets now run the flow engine (Phase 7c "wow" rework) — each draws a real PCM
waveform into the feedback, with a distinct palette, form, motion, and beat behaviour:
- **`vibrdrome_aurora` ("Aurora")** — calm flowing curtains: circular waveform, aurora
  green/teal palette (idx 3), slow flow, high decay, gentle spin, soft beat. Authored from
  scratch.
- **`vibrdrome_pulse` ("Pulse")** — aggressive fire kaleidoscope: circular waveform, fire
  palette (idx 4), fast flow, **quad** symmetry, hard `beatWave`/`beatFlow`/`beatBloom`
  kicks, fast spin. Authored from scratch.
- **`vibrdrome_nebula` ("Nebula")** — dreamy deep tunnel: circular waveform, nebula
  magenta/blue palette (idx 5), slow flow, heavy bloom, deep `tunnel`, gentle spin.
  Authored from scratch.
- **`vibrdrome_spectrum` ("Spectrum")** — rainbow scope kaleidoscope: **horizontal scope**
  waveform (`waveStyle 2`), rainbow palette (idx 6), **quad** symmetry, strong beat, mid
  spin. Authored from scratch.

See `vibrdrome_flux.json`, `vibrdrome_aurora.json`, `vibrdrome_pulse.json`,
`vibrdrome_nebula.json`, and `vibrdrome_spectrum.json` in this directory.

## Architecture decision
The preset drives the **`MTKView` render-pass engine** (`PermissiveFeedbackRenderer`),
not the Classic SwiftUI `colorEffect` path — Classic cannot do feedback. Confirmed:
the native engine is the target for this format.

## Explicitly out of scope (v0)
- No expression/DSL fields (option (b)/(c) deferred).
- No `.milk` compatibility.
- No import/download, no community packs (a later, separate track — and the
  community-preset license model is still to be decided).
- No production loading path; the v0 loader is DEBUG-only.
