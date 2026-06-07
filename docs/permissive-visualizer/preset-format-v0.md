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
| `paletteIndex` | int | selects a built-in palette (0 = Aurora cool, 1 = Pulse warm) |
| `paletteShift` | float | palette position offset |
| `pulseScale` | float | radial audio-pulse intensity |
| `zoomBass` | float | audio mapping: bass → extra zoom |
| `rotateTreble` | float | audio mapping: treble → extra rotation |
| `pulseBass` | float | audio mapping: bass → pulse |
| `bloomStrength` | float? | (Phase 4) glow intensity, 0..1 (0 = off). `decodeIfPresent` → 0 |
| `waveformStrength` | float? | (Phase 4) audio-spectrum overlay intensity, 0..1 (0 = off). `decodeIfPresent` → 0 |

`bloomStrength` and `waveformStrength` are **optional** and default to `0` when absent,
so older `version: 1` presets remain valid (the field set is a backward-compatible
superset).

## Example presets (authorship notes)
- **`vibrdrome_aurora` ("Aurora")** — original Vibrdrome preset. Slow, deep feedback
  (high `decay`), gentle zoom/rotate, cool violet→cyan palette. Authored from the
  engine's parameter knobs; not derived from any third-party preset.
- **`vibrdrome_pulse` ("Pulse")** — original Vibrdrome preset. Punchy, beat-locked
  (low `decay`, high `pulseScale`/`pulseBass`), warm palette. Authored from scratch.

- **`vibrdrome_nebula` ("Nebula")** — original Vibrdrome preset (Phase 4). Long decay,
  heavy **bloom**, no overlay — soft, dreamy glow. Authored from scratch.
- **`vibrdrome_spectrum` ("Spectrum")** — original Vibrdrome preset (Phase 4). Strong
  **audio-spectrum overlay** + moderate bloom, punchier. Authored from scratch.

See `vibrdrome_aurora.json`, `vibrdrome_pulse.json`, `vibrdrome_nebula.json`, and
`vibrdrome_spectrum.json` in this directory.

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
