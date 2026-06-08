# Permissive Native Visualizer — Spike Charter

**Branch:** `feature/permissive-native-visualizer-spike` (R&D only — never merged into
the release path during the spike).

**Status:** exploratory, non-blocking, **no implementation yet**.

This document is the charter for exploring a permissively-licensed, native (Metal)
visualizer engine for Vibrdrome — independent of projectM. It exists to keep the
exploration original, legally clean, and clearly separate from the shipping
projectM/MilkDrop release.

---

## Goal
A **permissively-licensed, native (Metal) visualizer engine** that could eventually
become an alternative/fallback Vibrdrome visualizer mode. Strategic value: a
**fully App-Store-clean** path (no LGPL relink exposure) and a **legally clean
community-preset ecosystem** (our format, our license).

## Non-goals (initially)
- **No MilkDrop / `.milk` compatibility promise** — reimplementing the `.milk`
  language ≈ reimplementing projectM; defeats the purpose.
- **No projectM dependency** of any kind.
- **Not a replacement** for the shipping projectM/MilkDrop path.
- **No production UI / mode-picker integration** in the spike — DEBUG-only proof.
- Not aiming for projectM visual parity at first — aiming to prove the architecture
  is viable (but see the visual-quality exit criterion below).

## Licensing constraints
- **Everything permissive:** MIT / BSD / Apache-2.0 / public-domain / Vibrdrome-
  original only. **No LGPL/GPL.** Metal/MetalKit (Apple SDK) is fine.
- Any third-party noise/math/SIMD helper must be permissive (or we write our own).
- **Presets: original Vibrdrome only**, under our chosen permissive/own license →
  clean redistribution, no relink problem, App-Store-clean.
- Net effect: this engine, if shipped, carries **zero LGPL/iOS-relink risk**.

---

## Clean-room / provenance constraint
Use a clean-room-ish approach appropriate for an indie/open-source project. The
goal is to keep this engine clearly **original** and avoid accidentally copying from
projectM, Butterchurn, or community `.milk` presets.

**Allowed:**
- Study high-level visualizer **concepts**: feedback textures, warp meshes, waveform
  overlays, spectrum textures, palettes, decay, blur, beat-reactive parameters,
  transitions.
- Use public graphics, math, and Apple **Metal documentation**.
- Use Apple **sample code only according to its license**.
- Write **design notes in our own words** before implementation.
- Implement **original Vibrdrome code** from those notes.

**Not allowed:**
- Copying, porting, translating, or closely following **projectM** implementation code.
- Copying, porting, translating, or closely following **Butterchurn** implementation
  code without a separate license/provenance review.
- Copying community **`.milk`** preset code.
- Creating **near-clones of named community presets**.
- Using projectM, Butterchurn, or community preset source as a **side-by-side
  implementation reference**.

**Process:**
- Keep a **provenance log** for major techniques and preset ideas.
- Every bundled preset must have an **authorship note**.
- If a third-party permissive dependency is considered, **record its license before
  use**.
- If projectM or Butterchurn must be inspected for *compatibility research*, capture
  that as a **separate research note** and **do not directly translate code** into
  the native engine.

## `.milk` boundary (strict)
- **No `.milk` parser, importer, or compatibility layer** in this spike.
- **No community `.milk` presets.**
- **No "MilkDrop-compatible" promise.**
- This is a **native Vibrdrome visualizer engine, not a projectM clone.**

---

## Relationship to the current projectM/MilkDrop release path
**Fully separate and non-blocking.** projectM/MilkDrop is the current, decided
release path (merged to `main`, shipping under best-effort LGPL — see
`docs/projectm-integration-plan.md`).

This branch is R&D only and must **not** block the current MilkDrop/projectM release
track. Specifically, this spike involves:
- **No build-number changes.**
- **No release docs.**
- **No TestFlight/App Store work.**
- **No impact on the current projectM path** (no edits to projectM/MilkDrop code).

Possible long-term outcomes (decided later, not by this spike): a second "Vibrdrome
Visualizer" mode alongside Classic + MilkDrop; the clean home for a community-preset
ecosystem; or an eventual projectM replacement *if* the LGPL/iOS risk ever
materializes. None are committed by the spike.

## Architecture areas to investigate
- **Render surface:** `MTKView` / `CAMetalLayer` with a real multi-pass pipeline —
  **not** the Classic path. (Classic = SwiftUI `TimelineView` + `Rectangle().colorEffect`
  single-pass `[[stitchable]]` fragment shaders in `Shaders.metal`; no persistent
  feedback buffer, which a feedback-style look requires.)
- **Feedback textures:** ping-pong render-to-texture (sample the warped previous
  frame) — the signature trails/tunnels effect.
- **Warp mesh:** a grid distorted per-frame by audio-reactive parameters.
- **Layers:** waveform/spectrum overlays, palettes, blur/bloom passes.
- **Coexistence:** confirm a Metal `MTKView` engine can live beside the SwiftUI
  Classic shaders and the projectM `MGLKView` without conflict.
- **Accessibility parity:** reduced-motion / photosensitivity / sim-gating rules to
  match the existing visualizer.

## Audio input strategy
Reuse what's already in the app — **no new audio plumbing**:
- `AudioSpectrum.shared` (FFT bands + bass/mid/treble) — the Classic input.
- `VisualizerPCMSource` (the SPSC PCM ring built for projectM) — raw waveform.

The engine consumes these as Metal uniforms/textures (e.g., a 1-D spectrum texture +
scalar bands). The PCM ring's single-consumer discipline still applies if used.

## Preset format / DSL thoughts
**Our own format, not `.milk`.** Options to evaluate:
- **(a) JSON / Swift `Codable`** of fixed-function knobs (warp amount, decay,
  palette, layer toggles, audio→param mappings). Simplest; safe; less expressive.
- **(b) A small expression DSL** (our own minimal grammar) — more expressive; more
  work; needs a **safe, sandboxed evaluator** (no arbitrary code execution).
- **(c) Hand-authored Metal shader snippets** per preset (like Classic's
  `[[stitchable]]`) + a JSON manifest — most powerful, least accessible.

Start with **(a)** for the spike; design with **(b)/(c)** as a growth path. The format
must be **versioned** and **sandbox-safe** (downloaded presets must never execute
arbitrary code).

## Community contribution model
Because presets are **our format + permissively licensed**, community authoring and
sharing is **legally clean** (unlike `.milk`). Investigate a documented schema, an
in-app import path, optional user-downloaded packs (user-initiated, removable, per-
pack attribution — per the "Future Community Presets" note in
`docs/projectm-integration-plan.md`), and a contribution/review pipeline.

### Community preset license model (research item)
Decide whether future community presets should use **MIT**, **CC0**, or another
permissive preset license. Document:
- **author attribution**
- **pack metadata**
- **preset provenance**
- **deletion/removal behavior**
- **how imported or community presets stay separate from bundled Vibrdrome presets**

---

## Exit criteria for the spike
The spike **succeeds** if it demonstrates, on a physical iPhone + Mac, all of:
1. A **Metal `MTKView` engine** rendering an **audio-reactive, feedback-based** visual
   at **~60 fps**, fed by the existing `AudioSpectrum` / `VisualizerPCMSource`.
2. At least **one original Vibrdrome preset** loaded from **our own preset format**,
   that **feels plausibly shippable as a beta visualizer mode** — not just a technical
   proof with moving pixels.
3. **Zero LGPL/GPL dependencies** (permissive-only), verified.
4. A written **effort/risk assessment**: rough path + cost to reach "good enough to
   ship as a mode," and whether the preset format can support a community ecosystem.

The spike **fails / pauses** if a permissive feedback engine can't hit ~60 fps on
device, or the effort to reach acceptable visual quality is disproportionate.

### Clean exit requirements
The spike must end with:
- **no LGPL/GPL dependencies**
- **no copied projectM, Butterchurn, or community preset code**
- a short **provenance note for the engine architecture**
- **authorship notes** for any included presets
- a **recommendation** on whether the native permissive engine is worth continuing

## First 2–3 research steps
1. **Technique survey (no code):** document the feedback-visualizer technique (warp
   mesh + feedback + per-frame parameters + waveforms) **in our own words**, and which
   parts are reproducible permissively from scratch; decide the minimal v0 feature set.
   Start the provenance log here.
2. **Minimal feedback prototype (DEBUG-only):** an `MTKView` ping-pong render-to-
   texture proof — a warped, decaying feedback field reacting to `AudioSpectrum`
   bass/treble — to validate the architecture + 60 fps on device. (Mirrors how the
   projectM spike started with a clear-screen.)
3. **Preset-format sketch:** define a v0 schema (option (a)) + author **1–2 original
   presets** (with authorship notes), and decide `MTKView` render-pass vs any reuse of
   the Classic `colorEffect` path.
