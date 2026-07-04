# Research Step 5 — Visual-Quality Refinement: Postmortem (FAILED visual gate)

**Date:** 2026-06-06
**Outcome:** Objective checks PASS, **visual-quality gate FAILED.** Code reverted; not
committed. Working tree reset to `5c9c002` (committed Step 4 state).

## What was attempted
A "hero refinement" of `vibrdrome_nebula`: two new parameters-only knobs (`warp`,
`mirror`), a dedicated palette index 2, hue decoupled from luminance, vignette, gamma/
contrast/saturation tone shaping, and a softened overlay.

## Objective result (all PASS — but irrelevant to the real bar)
- `scripts/verify-build.sh` PASS (SwiftLint/iOS/macOS/watchOS/tests/UI-rotation).
- Updated `PermissivePresetTests` PASS.
- Release iOS/macOS compile-out clean (0 `.json` bundled, 0 DEBUG strings).
- Built + installed on device; macOS Debug launched.

## Visual result: FAILED
Judged on device + macOS. The output was not interesting, not trippy, not MilkDrop-level.

### Failure modes (root causes, mapped to the engine)
1. **Center-anchored rotating blob.** The dominant motion is a center `rotate + zoom`
   (`pv_feedback`: rotate `uv-0.5`, then `*= (1 - zoom)`). Everything orbits one point by
   construction. The flow-field term was only a thin perturbation on top, so the center
   always wins → a wobbling "main-character" blob.
2. **Mirror fold amplified the center bias.** The polar-angle `mirror` fold forced a
   centered kaleidoscope symmetry — it made the "wet galaxy around a blob" worse, not
   better. Net-negative for this look.
3. **Muddy palette / RGB oil-slick.** A 3-stop RGB `mix` between distant hues
   (navy→magenta→teal) passes through gray at the midpoint; the universal saturation
   boost cranked that mud. Purple/green/cyan fought and all lost.
4. **Weak/mushy reactivity.** Continuous, smoothed band levels mapped straight to
   zoom/pulse → laggy smear, never a punch on the beat ("flinches randomly").
5. **No real beat/onset detection** anywhere — the core reason it does not feel reactive.
6. **Spins in place instead of flowing/breathing** — the warp field was two fixed
   sinusoids, no organic curl/flow.

## Lessons for Step 6
- Replace the center `rotate/zoom` as the **dominant** motion with **flow-field /
  curl-noise advection** that moves the whole frame (no anchor point).
- **Remove `mirror` from the hero path** (centered symmetry is the enemy here).
- Add a **real onset/beat pulse** (transient detector), used as the primary reactivity;
  keep continuous bass/mid/treble as secondary modulation only.
- Use a **coherent palette model** (HSV-style hue rotation or a curated dark-base
  gradient that never passes through gray), not muddy multi-hue RGB mixing.
- Lean on **bloom + dark-base contrast** for the trippy glow, not saturation/contrast
  cranking.
- **Make visual quality the gate**, not just tests/fps. "Technically working" is not the
  target; "awesome/trippy/reactive" is.

## Process note
The clean-room/provenance rules held (no projectM/Butterchurn/`.milk` consulted), the
format stayed parameters-only, and nothing shipped in Release. The failure was aesthetic,
and the engine's center-transform premise was the ceiling — a tune could not escape it.
