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
| `paletteIndex` | int | palette: 0/1 = legacy 3-stop (fallback only); 2–10 = cosine-gradient themes (2 deep-space, 3 aurora, 4 fire, 5 nebula, 6 rainbow, 7 acid, 8 ice, 9 sunset, 10 mono) |
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
| `swirl` | float? | (Phase 8) radius-modulated angle swirl amount (the spiral/vortex). `decodeIfPresent` → 0 |
| `swirlFreq` | float? | (Phase 8) spatial frequency of the swirl. `decodeIfPresent` → 8 |
| `warpMode` | int? | (Phase 8) 0 = curl-flow, 1 = polar warp (hero vortex). `decodeIfPresent` → 0 |
| `kaleido` | int? | (Phase 8b) kaleidoscope wedge count for the present-time polar fold; 0 = off, 6/8 = wedges. `decodeIfPresent` → 0 |
| `spokes` | int? | (Phase 8c) radial spectrum-spoke (ray) count; 0 = off. `decodeIfPresent` → 0 |
| `spokeLen` | float? | (Phase 8c) radial length of the spectrum bars. `decodeIfPresent` → 0 |
| `spokeInject` | int? | (Phase 8c) 0 = present-only spokes (sharp), 1 = inject spokes into the feedback field (bloom + trails). `decodeIfPresent` → 0 |
| `whirl` | float? | (Phase 8c) whirlpool: center-weighted rotational warp (1/r falloff, bass-swelled) + radius-dependent spiral twist on the spokes. 0 = off. `decodeIfPresent` → 0 |
| `lattice` / `latticeR` / `latticeA` | float? | (Phase 9) polar lattice: intersecting concentric rings (`latticeR` count, → 12) + radial lines (`latticeA` count, → 16) = moiré grid; `lattice` strength → 0 |
| `wash` | float? | (Phase 9) moving full-screen colour-wash overlay. `decodeIfPresent` → 0 |
| `fractal` | int? | (Phase 10) Kaliset fractal-fold iterations on the sample coord (nested mandala). `decodeIfPresent` → 0 |
| `cells` | float? | (Phase 10) Voronoi liquid-cell layer (molten edges). `decodeIfPresent` → 0 |
| `spiral` | float? | (Phase 11) logarithmic (Droste) self-similar spiral warp. `decodeIfPresent` → 0 |
| `tile` | float? | (Phase 12) mirror-tiling grid (domain repetition). `decodeIfPresent` → 0 |
| `pixelate` | float? | (Phase 12) quantise the sample coord to blocks (cubist). `decodeIfPresent` → 0 |
| `truchet` | float? | (Phase 12) Truchet arc-tile maze overlay. `decodeIfPresent` → 0 |
| `tunnel3d` | float? | (Phase 13) demoscene 3D tunnel (angle + 1/r depth). `decodeIfPresent` → 0 |
| `plasma` | float? | (Phase 13) sine-plasma colour field. `decodeIfPresent` → 0 |
| `phyllo` | float? | (Phase 13) phyllotaxis (golden-angle sunflower) seed spiral. `decodeIfPresent` → 0 |
| `ripple` | float? | (Phase 13) multi-source wave-interference ripples. `decodeIfPresent` → 0 |
| `hex` | float? | (Phase 13) hexagonal honeycomb grid. `decodeIfPresent` → 0 |
| `chroma` | float? | (Phase 13) chromatic aberration (RGB channel split on the field sample). `decodeIfPresent` → 0 |
| `sceneMode` | int? | render engine: 0 = 2D feedback engine, 1 = raymarched 3D tunnel (Phase 14), 2 = glowing-orb / metaball field (Phase 15), 3 = screen-space warp starfield (Phase 16), 4 = raymarched gyroid lattice (Phase 17). `decodeIfPresent` → 0 |

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

### Phase 8c — radial spectrum spokes (Radiant)
`spokes > 0` draws the **spectrum geometry family**: the 32 `AudioSpectrum.bands` become
**filled radial bars** whose length tracks each band's energy (`spokeLen`), procedurally in
the present pass. The bands are **folded around the vertical axis** into a bilaterally-
symmetric EQ halo (so it reads ornamental, not a left-to-right bar graph), with thin angular
gaps between rays (crisp), additive-bright on the dark field, hue varying per band, gentle
time rotation + `treblePunch` shimmer, `bassPunch` radial breathing, and `beatPulse` flash.
`spokeInject 0` (Radiant) draws them present-only (sharp, no glow/trails); `spokeInject 1`
(Spectral Spokes) draws them **into the feedback field** so they bloom and trail. No
concentric rings in this checkpoint.

### Phase 8b — kaleidoscope waveform (Kaleidoscope)
`kaleido > 0` adds a **present-time polar wedge fold**: decompose to radius/angle, wrap the
angle into `kaleido` wedges and mirror within each (reflected, seam-free), then sample the
already-waveform-fed/warped field from the folded coordinate. It folds **only at present** —
the feedback physics stay un-folded and alive, so the vortex doesn't collapse to a centred
blob; instead the fine waveform filaments **multiply into a mandala**. A slow time drift +
`treblePunch` turns it. This is the *radial* kaleidoscope (distinct from the rectilinear
`symmetry` mirror); a preset may use either or both.

### Phase 8 — polar warp + envelope followers (the vortex)
`warpMode 1` switches the feedback warp from curl-flow to a **polar warp**: decompose to
radius/angle, add a radius-modulated swirl to the angle (`swirl` / `swirlFreq` — the
spiral), and zoom the radius a tiny amount per frame (the breathing tunnel). Seam-free —
the angle is recomposed with `cos/sin` (periodic), so the `atan2` branch cut vanishes; small
per-frame transforms compound through feedback into hypnotic motion. Per-band
**spectral-flux punches** (host side — positive band rises grouped into bass/mid/treble,
peak-held with decay; robust to clipped/loud levels) feed `bassPunch`/`midPunch`/
`treblePunch`, which drive zoom/swirl/brightness/bloom. The spectral-flux `beatPulse` stays
for discrete hits.

## Example presets (authorship notes)
- **`vibrdrome_flux` ("Flux")** — original Vibrdrome preset; **hero (Phase 8)**. Restrained,
  hypnotic **polar vortex** (`warpMode 1`, `swirl`/`swirlFreq`): a circular waveform drawn
  into the feedback and pulled into a breathing tunnel by the polar warp; envelope-follower
  punches drive zoom/swirl/brightness/bloom; cosine-gradient palette (idx 2); spin off,
  bilateral mirror. Authored from scratch; not derived from any third-party preset.
- **`vibrdrome_kaleidoscope` ("Kaleidoscope")** — **Kaleidoscope Waveform family (Phase 8b)**. A 6-wedge
  present-time kaleidoscope (`kaleido 6`, `symmetry 0`) over an intentionally **asymmetric**
  source — curl-flow (`warpMode 0`, `flow`) + a horizontal **scope** waveform (`waveStyle 2`) —
  so the fold has angular detail to mirror into a turning mandala (a rotationally-symmetric
  source would just fold back to a circle). Nebula magenta/blue palette (idx 5),
  `treblePunch`-driven rotation. Authored from scratch; not derived from any third-party preset.
- **`vibrdrome_radiant` ("Radiant")** — **Radial Spectrum Spokes family (Phase 8c)**. The 32
  FFT bands as **filled radial bars** (`spokes 16`, `spokeLen`) folded into a bilaterally-
  symmetric, hue-cycling EQ halo on a dark field; `bassPunch` breathes the inner radius,
  `treblePunch` rotates, `beatPulse` flashes. No waveform (the spokes are the geometry).
  Rainbow palette (idx 6). Present-only (`spokeInject 0`) — sharp, no glow/trails. Authored
  from scratch; not derived from any third-party preset.
- **`vibrdrome_spectralspokes` ("Spectral Spokes")** — the **injected** spectrum-spokes variant
  (`spokeInject 1`): the radial bars drawn **into the feedback field** so they bloom and leave
  trails (longer `decay`, gentle `flow`), plus three overlaid oscillations for a trippy look —
  a **vibrating-string ripple** travelling along each spoke, **oscillating tips** (per-band
  sine), and the **real PCM waveform** ring (`waveStyle 1`) overlaid on top. Authored from
  scratch.

The library now holds **50 original presets** spanning the families above plus the Phase 9–13
layers — vortices, kaleidoscope mandalas, radial spectrum spokes, whirlpool spirals, lattice
moiré, colour washes, fractal folds, Voronoi liquid cells, log-spirals, tiling/pixelate/Truchet
geometry, demoscene 3D tunnels, sine plasma, phyllotaxis, ripples, hex grids, and chromatic
aberration, across cosine palettes 2–10. Each is original Vibrdrome work, not derived from any
third-party preset. **The inline `PermissivePresetLibrary` string is the source of truth;** the
`docs/permissive-visualizer/presets/*.json` files are byte-for-byte reference copies (one per
preset) regenerated from it.

## Phase 14 — 3D raymarch (sceneMode)
`sceneMode 1` switches the renderer from the 2D feedback engine to a **raymarched 3D tunnel**:
a fullscreen fragment pass sphere-traces a signed-distance tunnel (winding centerline + ring
ribs), shades it (fog vanishing point + emissive ribs + headlight glow), and writes the lit
colour into the feedback-format target; the existing **quarter-res bloom** + **present** passes
are reused (present has a `sceneMode` branch that skips all the 2D waveform/feedback logic and
just composites bloom + a mild vignette). The 2D feedback path (`sceneMode 0`, the 50 presets)
is unchanged. Audio: `bass` → forward speed + tunnel pulse, `bassPunch` → forward surge,
`beatPulse` → camera kick + light burst, `treble` → rib shimmer. Colour reuses the cosine
palettes (`paletteIndex`) and `vibrance`/`bloomStrength`. Marching is **bounded** (64 steps);
the proof reports `sceneMode`/`marchSteps`/`avgSteps`/`raymarchScale`.

### Phase 15 — glowing-orb / metaball field (sceneMode 2)
`sceneMode 2` reuses the same raymarch route for a second 3D scene: **8 soft spheres** combined
with a **polynomial smooth-min union** (metaballs that merge), drifting on deterministic
Lissajous orbits spread in depth, lit with diffuse + **fresnel rim** + specular and **glow
accumulated along the ray** (halos into the dark). An **orbiting camera** circles the cluster.
Audio: `bass` breathes the radii, `bassPunch` expands them, `beatPulse` pushes the camera +
flashes, `treble` shimmers the highlights. Bounded to the shared 64-step cap; tone-mapped (no
blowout) via the present pass. Preset: `vibrdrome_orbs`.

**iOS raymarch resolution:** the raymarch pass (both 3D scenes) renders into a separate target at
`raymarchScale` and the linear present sampler upscales it. On iPhone this is fixed at **0.25**
(quarter-res); macOS stays full-res. On-device profiling showed the march is resolution-bound
*and* the GPU drops to a low power state under sustained load — quarter-res keeps the frame light
enough (~10 ms) to hold a locked 60 fps, and the smooth orbs/tunnel upscale cleanly. Platform-
fixed and deterministic (no adaptive scaling, no per-preset knob); reported as `raymarchScale`.

### Phase 16 — warp starfield (sceneMode 3)
`sceneMode 3` is a **screen-space procedural** hyperspace warp tunnel — **not raymarched**: O(1)
per pixel over a fixed 3-shell loop (so `avgSteps≈3`, far cheaper than Orbs/Tunnel). Star streaks
are born at the centre vanishing point and fly outward, generated by a **deterministic per-angular
-cell hash** (no RNG state) — motion comes only from `camZ`/`time`. Each shell layers stars at a
different angular density for parallax; a bright core glows at the vanishing point. Audio:
`bass`+`bassPunch` drive forward warp speed/depth, `beatPulse` elongates streaks + flares the core,
`energy` (bass+mid+treble) sets global brightness, `treble` sharpens/sparkles, `mid` opens the
funnel. Reuses the 3D route (so the iOS quarter-res policy above applies), bloom, and present.
Preset: `vibrdrome_warpfield`. The first scene built screen-space rather than via SDF raymarch.

### Phase 17 — gyroid lattice (sceneMode 4)
`sceneMode 4` raymarches the **gyroid** triply-periodic minimal surface
(`sin x·cos y + sin y·cos z + sin z·cos x`) as a finite-thickness glowing membrane you fly
through — an organic/alien/mathematical lattice. The field is an **implicit surface, not a true
SDF** (gradient isn't unit), so it under-steps conservatively (×0.5). A **depth-domain twist**
corkscrews the lattice into vortices; an **off-axis curving camera** gives parallax/depth. Shading
= low-ambient + punchy diffuse (for contrast/detail) + fresnel rim + proximity glow, depth-fogged.
Audio: `bass`+`bassPunch` = camera speed + membrane breathing/twist, `beatPulse` = glow/thickness
pulse + camera kick, `mid` = lattice scale/openness, `treble` = rim sharpness + hue drift, `energy`
= brightness. Reuses the 3D route (iOS quarter-res policy applies), bloom, present. avgSteps ~9–15.
Preset: `vibrdrome_gyroid`. (A head-on kaleidoscope fold was tried and rejected — it flattens the
3D fly-through into a 2D mandala; symmetry, if revisited, must preserve depth.)

### Future hooks (designed, NOT implemented in Phase 1)
- **2D-over-3D overlay compositing:** a future overlay pass would render a chosen 2D preset into
  a second texture and the 3D scene into another, then the present pass blends them. The texture
  separation that makes this a drop-in is already in place.
- **Future overlay fields:** `overlayPreset` (string id of a 2D preset), `overlayBlend` (int:
  add/screen/alpha), `overlayOpacity` (float). Not added in Phase 1 — only `sceneMode` exists.
- **Auto-transitions:** the coordinator would hold `current` + `next` preset + a transition timer
  and crossfade between scenes (or lerp uniforms for same-engine transitions). App-level fields
  (duration/curve), not preset fields. Not implemented in Phase 1.
- **More 3D scenes** select via the same `sceneMode` enum later (5 = lattice tunnel, then Mandelbulb/Mandelbox, …).

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
