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
| `sceneMode` | int? | render engine: 0 = 2D feedback engine; 3D scenes — 1 = tunnel, 2 = orbs, 3 = warp starfield, 4 = gyroid, 5 = ocean, 6 = synthwave highway, 7 = Voronoi fracture, 8 = crystal cluster, 9 = kaleido mirror chamber (Phase 22), 10 = spiraling endless elevator (Phase 23), 11 = Perlin blob (Phase 24), 12 = fault terrain (Phase 25), 13 = cymatic plate (Phase 26), 14 = horizon dome (Phase 27), 15 = vortex tornado (Phase 28), 16 = supernova shockwave (Phase 29), 17 = menger sponge (Phase 30), 18 = urban canyon (Phase 31), 19 = liquid chrome (Phase 32), 20 = apollonian gasket (Phase 33), 21 = reaction membrane (Phase 34), 22 = hex honeycomb (Phase 35), 23 = truchet circuit (Phase 36), 24 = torus-knot surface (Phase 37). `decodeIfPresent` → 0 |

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

### Phase 18 — audio ocean (sceneMode 5)
`sceneMode 5` **raymarches a heightfield** water surface: layered directional sine waves
(`bass`=swells + forward speed, `mid`=ripples, `treble`=fine chop, `beatPulse`=amplitude surge +
crest flash + camera bob) marched until the ray drops below the surface, then **bisection-refined**
for a clean waterline. Shading = height-gradient normal + **fresnel** (bright crests/horizon) +
diffuse + specular sun-glint; rays that escape draw a sky gradient + luminous horizon band. Reuses
the 3D route (iOS quarter-res), bloom, present. avgSteps ~26. Preset: `vibrdrome_ocean`.

### Phase 19 — synthwave highway (sceneMode 6)
`sceneMode 6` is **screen-space procedural** (no march, O(1)/pixel, `avgSteps≈2`): the retro neon
outrun grid. Below the horizon, each pixel is analytically projected onto the ground plane and
grid lines are drawn with **`fwidth` antialiasing** (so they stay clean at quarter-res); above, a
sky gradient + a banded synthwave **sun**. Audio: `bass`+`bassPunch`=scroll speed + grid pulse,
`beatPulse`=flash + sun pulse, `mid`=rolling hills, `treble`=sparkle, `energy`=brightness. Reuses
the 3D route, bloom, present. Preset: `vibrdrome_highway`.

### Phase 20 — Voronoi fracture (sceneMode 7)
`sceneMode 7` raymarches a **3D Voronoi/Worley** cell field as shattered glowing crystalline
chunks separated by dark fracture gaps, each cell its own palette colour (hashed cell id). One
27-cell pass tracks the two nearest centres; the cheap **F2−F1** difference approximates the
distance to the cell wall (half the cost of the IQ two-pass edge — the perf mitigation that took
it from over-budget to 60fps after a step-size trim). Emissive front-to-back accumulation (dark
interiors, sharp bright walls = contrast, not wash). Audio: `bass`/`bassPunch`=separation + speed,
`beatPulse`=edge flash, `mid`=cell scale, `treble`=sparkle/hue. Preset: `vibrdrome_fracture`.

### Phase 21 — crystal cluster (sceneMode 8)
`sceneMode 8` raymarches a **hard union of ~8 jagged octahedron shards** (the *sharp* counterpart
to Orbs' soft metaballs) — faceted, per-shard tinted, fresnel-rimmed, with a treble emission flash
and gentle treble vibration; an orbiting camera. NB: an early build had a full-screen `beatBloom`
flash added to every pixel (background included) — removed as a **photosensitivity hazard**; shard
emission/glow carry the beat instead. Audio: `treble`=vibration/sparkle, `beatPulse`=cluster
pulse + camera kick, `bass`=shard size, `mid`=rotation. Preset: `vibrdrome_crystal`.

### Phase 22 — kaleido mirror chamber (sceneMode 9)
`sceneMode 9` raymarches a **depth-preserving kaleidoscopic corridor**: the mirror fold is applied
to the **cross-section (xy) only** (6-fold), while the camera flies **forward along z** (parallax)
and content **repeats in z** → a 3D mirrored shaft you fly *through*, NOT a flat 2D mandala (the
explicit fix for the Gyroid kaleidoscope mistake). Content = glowing struts + orbs at a wedge radius
(replicated ×6 around the axis), z-repeated; a slow axial roll evolves the symmetry. Audio:
`bass`=speed/scale, `beatPulse`=glow + camera kick, `mid`=chamber radius, `treble`=sparkle/hue.
Preset: `vibrdrome_mirrorchamber`.

### Phase 23 — spiraling endless elevator (sceneMode 10)
`sceneMode 10` raymarches an **inside-out box shaft** you fall down endlessly, with a **spiral
twist** (cross-section rotation that grows with depth → corkscrew descent) — z-repeated glowing
light-strips + spiral corner girders streaming past; the walls pulse outward on the beat. Fast
forward fall (`camZ`×1.6). NB: a plain (untwisted) shaft read as boring/static — the spiral makes
it dynamic. Audio: `bass`=descent speed + twist + wall pulse, `beatPulse`=pulse + strip flash,
`mid`=panel density, `treble`=sparkle. No full-screen flash. Preset: `vibrdrome_elevator`.

### Phase 24 — Perlin blob (sceneMode 11)
`sceneMode 11` sphere-traces an **SDF sphere displaced by ridged 3D FBM** — a solid writhing
organic mass, NOT fog/plasma. 3D value noise → ridged FBM (`1-|2n-1|` per octave, 3 octaves) with
a domain-warp pass; the displaced field is non-Lipschitz so the march uses a conservative under-step
(`d×0.55`, cap 46). Gradient normals are lit with **diffuse + colored fresnel rim + specular** so the
surface reads as a solid with depth; crevices darken via a noise-driven AO term. Audio: `bass`=radius
inflate, `bassPunch`=spike burst, `mid`=turbulence/domain-warp, `treble`=high-freq ridge shimmer + rim,
`beatPulse`=localized surface swell (no full-screen flash). Slow camera orbit for parallax. Verified
iPhone 60fps @0.25 (avgSteps≈9), mac full-res. Preset: `vibrdrome_perlinblob`.

### Phase 25 — fault terrain (sceneMode 12)
`sceneMode 12` reuses the **Ocean-style heightfield march** (proven cost profile) but with **ridged FBM**
(4 octaves) → sharp cracked rock plates. The hit point is bisection-refined, normal-shaded, and tinted
**gloomy purple** (rock + atmosphere) with **deep-red magma** emission concentrated in the low crevices
(`smoothstep` on height), flickering with `treble`. A **camera torch** (proximity × `dot(n,-rd)`, slow
full-spectrum colour cycle) lights approaching plates/crevices as they rush in, plus a rim term for ridge
silhouettes. Forward fly-through is intentionally a **slow drift** (`camZ×0.35`, calmer than the elevator)
so it's not a 500-mph plunge; `bass` still pushes. Audio: `bass`=terrain amplitude + fly speed, `mid`=ridge
sharpness, `treble`=magma flicker, `beatPulse`=localized magma flare (cracks only, no full-screen flash).
Verified iPhone 60fps @0.25 (avgSteps≈3–14), mac full-res. Preset: `vibrdrome_faultline`.

### Phase 26 — cymatic plate (sceneMode 13)
`sceneMode 13` is **screen-space procedural** (no march, O(1)/pixel): a top-down Chladni square-plate.
The nodal lines (zeros of the standing-wave field) glow like sand collecting on a vibrating plate.
Field = a superposition of 4 resonant modes `cos(nπx)cos(mπy) − cos(mπx)cos(nπy)`, each weighted by an
audio band (bass→coarse `(2,3)`, treble→fine `(5,7)`) and oscillating at its own rate, so the figure
visibly restructures with the music. Lines are `fwidth`-antialiased (no shimmer at iOS 0.25). Audio:
`bass`/`mid`/`treble`=mode weights (coarse→fine), `mid`=plate spin, `treble`=line sharpness,
`beatPulse`=thicken/brighten the nodal lines only (no full-screen flash). Verified iPhone 61fps @0.25 /
mac 59–60 full-res, `avgSteps≈2`. Preset: `vibrdrome_cymatic`.

### Phase 27 — horizon dome (sceneMode 14)
`sceneMode 14` is **screen-space procedural** analytic projection (no march, O(1)/pixel): the camera is
pitched up ~36° into a vast wireframe dome. Longitude ribs + latitude rings (`asin` elevation / `atan2`
azimuth) converge toward a zenith overhead; below the horizon a polar floor grid (concentric rings +
the same ribs) recedes with `1/sin(elev)` perspective; a bright **curved horizon band** sits where they
meet. Glow-fill keeps it from ever reading empty. Lines `fwidth`-antialiased. Audio: `bass`=dome spin +
floor-ring travel, `mid`=grid density, `treble`=shimmer/brightness, `beatPulse`=pulses grid + horizon
band only (no full-screen flash). NB: a flat head-on first attempt read as lame/flat (no dome) — pitching
the camera up so ribs converge to a zenith + a curved horizon fixed it. Verified iPhone 61fps @0.25 /
mac 59–60 full-res, `avgSteps≈2`. Preset: `vibrdrome_horizondome`.

### Phase 28 — vortex tornado (sceneMode 15)
`sceneMode 15` is a **thin-shell emission raymarch** around the Y axis: a vertical funnel (narrow at
the bottom, flared at the top via `Rf(y)=0.12+0.55·exp((y+1)·0.45)`) built from sharp spiral filaments
(`pow(0.5+0.5·sin(N·(φ + y·twist + spin)), 8)` — the `y·twist` term makes them *spiral* up, not ring)
on a tight shell (`exp(−(ρ−Rf)²·60)`) + a bright axial core. Front-to-back accumulation → near wall
occludes far wall (real depth); the camera orbits for parallax. Audio: `bass`=spin + funnel flare,
`bassPunch`=expansion pulse, `mid`=twist (spiral tightness), `treble`=filament count + sharpness,
`beatPulse`=shell/core brightness only (no full-screen flash). Bounded 48 steps (runs near the cap —
thin shell rarely early-breaks). Verified iPhone 60fps @0.25 (avgSteps≈cap) / mac 60 full-res. Preset:
`vibrdrome_vortex`.

### Phase 29 — supernova shockwave (sceneMode 16)
`sceneMode 16` is **screen-space procedural** (no march, O(1)/pixel): a bright core star + a stream of
expanding shockwave rings. K shells at `Rk=fract(time·speed − k·0.25)`, each a Gaussian ring
`exp(−((r−Rk·Rmax)/w)²)` that widens + dims as it grows (energy spreads), modulated by sharp radial
filaments `pow(0.5+0.5·cos(M·φ), 6)` so it reads as arcs/streaks, not smooth circles. **Photosensitivity-
safe:** energy lives in thin rings + a small core; dark space between rings; **no term multiplies the whole
frame by `beatPulse`** — beat raises only the youngest ring + core (both localized), and global gain is
capped (`min(0.8+0.7·energy, 1.6)`) so there is no white-out. Audio: `bass`=expansion speed,
`bassPunch`=ring amplitude, `mid`=ring sharpness + shell count, `treble`=filament count + shimmer,
`beatPulse`=leading ring + core only. Verified iPhone 60fps @0.25 / mac 59 full-res, `avgSteps≈2`.
Preset: `vibrdrome_shockwave` (display "Supernova Shockwave"; the id `vibrdrome_supernova` was already
taken by an original 2D feedback preset, so this scene uses `vibrdrome_shockwave`).

### Phase 30 — menger sponge (sceneMode 17)
`sceneMode 17` raymarches the **canonical Menger distance estimator** (fixed `ITER=4` — bounded, **not**
Mandelbox): `d = sdBox(p,1)`; then per scale `s×=3`, `a = mod(p·s,2)−1`, carve `d = max(d, (min over the
three max-pairs of |1−3|a|| − 1)/s)`. The DE is **domain-repeated** (period 2) into an infinite sponge
lattice so the camera dives through aligned holes forever (a single bounded cube went black once you flew
past it). Gradient-normal shaded (diffuse + fresnel edge glow + step-count AO + fog). `mid` breathes a
uniform scale only (never the iteration structure). Audio: `bass`=fly speed + (camera roll) tumble,
`bassPunch`=zoom kick, `mid`=breathing, `treble`=edge-glow sharpness, `beatPulse`=edge glow only (no
full-screen flash). No FBM/trig in the DE → cheap per step. Verified iPhone 60fps @0.25 / mac 60 full-res
(avgSteps swings with camera position). Preset: `vibrdrome_menger`.

### Phase 31 — urban canyon (sceneMode 18)
`sceneMode 18` raymarches a **neon city canyon** via domain repetition: buildings tile the xz plane
(`floor(p.xz/spacing)` + per-cell hash height), with the central street carved clear (`|x|<streetHalf`
empty) so they line **both sides**; occasional cross-streets (`hash(row)` gap). On hit, the facade gets a
**lit window grid** (per-window on/off hash + treble flicker), the street gets scrolling lane lines, and
above the rooflines is a dark sky + horizon haze; exponential fog gives depth and near buildings occlude
far. Real forward motion (`camZ`). Deliberately **not** Highway (that's a flat single ground plane, no
walls) and **not** Elevator (single box tube): side walls + varying-height buildings + windows + street +
sky. Audio: `bass`=fly speed + sway, `bassPunch`=speed kick, `mid`=building height/density, `treble`=window
flicker, `beatPulse`=lit windows + edges only (no full-screen flash). Verified iPhone 60fps @0.25 / mac
59–60 full-res (avgSteps≈10–44). Preset: `vibrdrome_urbancanyon`.

### Phase 32 — liquid chrome (sceneMode 19)
`sceneMode 19` raymarches a **smooth-min metaball surface shaded as chrome/glass** (reuses `pv_smin`): at
each hit, Schlick fresnel mixes a **mirror reflection** and a **refracted** sample of a *structured analytic
background* (`pv_chromeBG`: spherical grid + palette bands + lights), with **chromatic dispersion** (2 refract
samples at offset eta → R from low / B from high → rainbow edges) and a **sharp specular glint**. No emissive
glow — the anti-Orbs differentiator. No second geometry march (refraction samples the analytic background, not
the blobs). Audio: `bass`=blob inflate/merge, `bassPunch`=expansion pulse, `mid`=orbit speed + wobble,
`treble`=dispersion width, `beatPulse`=specular glint only (no full-screen flash). Verified iPhone 60–61fps
@0.25 (after trimming dispersion 3→2 samples + dropping `asin`) / mac 59–60 full-res. Preset: `vibrdrome_chrome`.

### Phase 33 — apollonian gasket (sceneMode 20)
`sceneMode 20` raymarches the **canonical Apollonian sphere-inversion distance estimator** (fixed `ITER=7`,
`k` **clamped** to [1.0,1.25]): reflective fold `p = -1+2·fract(0.5p+0.5)`, then sphere inversion `p *= k/r2`,
accumulating `scale`; `orb = min(r2)` is the **orbit trap** → tiered nested-sphere colouring. **Bounded — NOT
Mandelbox** (no box/min-radius sphere fold with `scale·p+offset` escape) and **NOT Mandelbulb** (no polar
power). Curved recursive packing, distinct from Menger's cubes. Shaded with diffuse + **SDF ambient occlusion**
(5 DE taps along the normal — carves the recursive crevices so the small spheres read, instead of broad colour
bands) + fresnel edge glow + fog. **All camera motion is smooth monotonic time** (an early `time×bass` rotation
snapped backward when bass dropped, and a `fract(camZ)` zoom sawtooth jumped — both replaced). Audio: `bass`
(via energy/glow), `mid`→`k` breathe (clamped), `treble`→edge sharpness, `beatPulse`→edges only. Verified
iPhone 61fps @0.25 / mac 59–61 full-res (avgSteps swings with view). Preset: `vibrdrome_apollonian`.

### Phase 34 — reaction membrane (sceneMode 21)
`sceneMode 21` is **screen-space procedural** (no march, O(1)/pixel): a procedural **Turing/Gray-Scott
approximation** (NOT a multi-frame solver — single frame, no sim state). Domain-warped FBM `v = fbm(q +
0.55·fbm-warp)` is thresholded at its **edge** → `vein = pow(1 − smoothstep(0, vw, |v − thr|), 0.7)` for
fat, solid-cored labyrinthine ridges (not soft plasma). Relief comes from **hardware screen derivatives**
(`dfdx`/`dfdy` of `v`) → an embossed normal lit by an orbiting light (no extra FBM taps). Audio: `bass`
shifts `thr` (spots↔maze restructuring) AND swells vein width; `mid`=warp amount + evolution speed;
`treble`=vein sharpness; `beatPulse`=vein width swell + brightness flare (veins only, no full-screen flash).
fwidth-AA. Verified iPhone 61fps @0.25 / mac 59–60 full-res, `avgSteps≈2`. Preset: `vibrdrome_reaction`.

### Phase 35 — hex honeycomb (sceneMode 22)
`sceneMode 22` raymarches a **3D extruded honeycomb heightfield**: the xz plane is hex-tiled (two-lattice
positive-mod fold → cell id + local), each cell a prism risen to an audio + slow-morph height, with the
surface dropping to a gap near the hex edge (the honeycomb walls). Ocean-class heightfield march (bisection
refine + finite-difference normal), **glowing edge walls** (`smoothstep` on the hex-edge distance), per-cell
neon hue (`hash(id)`), exponential fog → near cells occlude far. Per-cell heights = a **slow undulation**
(`sin(time·0.5 + hash)`, ~12s — morphy/trippy) with a gentle per-band audio pulse on top; forward fly is a
**crawl** (`camZ·0.08`). Distinct from Highway (flat) and the 2D `vibrdrome_honeycomb` preset. Audio: `bass`
=crawl speed + (per-cell) height, `treble`=edge glow, `beatPulse`=cell/edge pulse only (no full-screen flash).
Verified iPhone 61fps @0.25 / mac 59–60 full-res (avgSteps≈8–18). Preset: `vibrdrome_hex` (the id
`vibrdrome_honeycomb` was already an original 2D preset).

### Phase 36 — truchet circuit (sceneMode 23)
`sceneMode 23` raymarches a **3D circuit board in relief**: Truchet tiling (per-cell hashed orientation,
two quarter-arcs connecting edge midpoints → continuous winding traces) carved as **raised copper traces**
on a dark board via a heightfield (`smoothstep` on the trace-centerline distance). Ocean-class heightfield
march (bisection + finite-difference normal); **data pulses** flow along each trace (`sin` of the along-arc
angle scrolled by time → white-hot packets), glowing neon traces (full cosine palette per cell), fog +
occlusion; flown over at a **crawl**. Distinct from Highway (flat grid) and Hex (cells). Audio: `bass`=crawl
+ pulse-flow speed, `bassPunch`=pulse burst, `mid`=trace fineness, `treble`=glow sharpness, `beatPulse`=
traces/pulses only (no full-screen flash). Verified iPhone 61fps @0.25 / mac 60–61 full-res (avgSteps≈9–19).
Preset: `vibrdrome_truchet` (the id `vibrdrome_circuit` was already an original 2D preset).

### Phase 37 — torus-knot surface (sceneMode 24)
`sceneMode 24` raymarches an **analytic (kp,kq) torus-knot SDF** (trefoil-class 3,2): main-axis angle +
tube cross-section coords, distance to the nearest of `kp` strand passes via wrapped tube-angle difference
→ one continuous **self-occluding knotted tube** (distinct from the Gyroid lattice). Surface **ridges**
(`sin` along the tube, treble→count, continuous so it never snaps) + diffuse/fresnel/specular + glow + hue
**along the tube length**; slow multi-axis tumble for self-occlusion + depth. Bounded (fixed winding,
clamped tube radius) — **not** Mandelbox/Mandelbulb. All motion is smooth monotonic time (a `time×bass`
rotation snapped backward; fixed). Audio: `bass`(via energy/glow), `mid`→tube radius, `treble`→ridges,
`beatPulse`→tube rim only (no full-screen flash). Verified iPhone 60fps @0.25 / mac 59–60 full-res
(avgSteps≈7–19). Preset: `vibrdrome_torusknot`.

### Future hooks (designed, NOT implemented in Phase 1)
- **2D-over-3D overlay compositing:** a future overlay pass would render a chosen 2D preset into
  a second texture and the 3D scene into another, then the present pass blends them. The texture
  separation that makes this a drop-in is already in place.
- **Future overlay fields:** `overlayPreset` (string id of a 2D preset), `overlayBlend` (int:
  add/screen/alpha), `overlayOpacity` (float). Not added in Phase 1 — only `sceneMode` exists.
- **Auto-transitions:** the coordinator would hold `current` + `next` preset + a transition timer
  and crossfade between scenes (or lerp uniforms for same-engine transitions). App-level fields
  (duration/curve), not preset fields. Not implemented in Phase 1.
- **More 3D scenes** select via the same `sceneMode` enum later (11+ per the 50-scene roadmap; particle + mesh subsystems and Mandelbox come in later tracks).

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
