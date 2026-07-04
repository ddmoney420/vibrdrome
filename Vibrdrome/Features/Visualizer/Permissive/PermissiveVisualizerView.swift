import Combine
import MetalKit
import QuartzCore
import SwiftUI
import os
import simd

/// Production host for the native Metal feedback visualizer. Embedded as the "Native"
/// mode inside `VisualizerView`, which supplies the close/playback controls. Auto-rotates
/// through the native scenes with a fade-to-black transition and layers a music-reactive
/// spectrum ribbon + particle swarm over the Metal field. Reads `AudioSpectrum` scalar
/// bass/mid/treble (with a synthesized fallback when nothing is playing). A horizontal
/// swipe in the host bumps `advanceToken` to jump to the next scene.
struct NativeVisualizerSurface: View {
    /// Incremented by the host (VisualizerView) on a manual "next scene" gesture.
    var advanceToken: Int = 0

    @State private var presetIndex = 0
    private let presets = PermissivePresetLibrary.presets

    // ── Auto-Transitions v1 (DEBUG-only, host-side; A12). Shuffle-bag over the native scenes
    // (sceneMode ≥ 1), fade-to-black between them. All logic lives in this View — no renderer,
    // shader, uniform, preset, or test changes. ──────────────────────────────────────────────
    private static let dwellSeconds = 18.0          // base dwell per scene
    private static let dwellJitter = 2.0            // ±jitter so it isn't metronomic
    private static let fadeSeconds = 0.35           // fade-to-black each way
    private static let heroOnly = false             // code-level constant (curated demo lane)
    private static let includeAll76 = false         // code-level constant (else native sceneMode ≥ 1)
    private static let heroModes: Set<Int> = [11, 20, 9, 13, 19, 22, 12, 18, 7, 4]

    @State private var autoEnabled = true
    @State private var bag: [Int] = []
    @State private var lastFamily = -1
    @State private var fadeOpacity = 0.0
    @State private var transitionStart: Date?     // non-nil while a fade is in progress
    @State private var didSwitch = false          // whether the scene was already swapped (at full black)
    @State private var dwellDeadline = Date()

    // ── Overlay/Compositing v1 (A13): one fixed audio-reactive spectrum ribbon, SwiftUI-only,
    // reading AudioSpectrum.shared.bands. Sits UNDER the A12 fade so transitions cover it. ──────
    @State private var overlayEnabled = true
    private static let overlayIntensity = 0.45    // subtle opacity / glow scale

    // ── Particles v1 (A14): a sparse music-reactive star/spark swarm (SwiftUI Canvas, additive).
    // CPU-updated, fixed buffer; sits UNDER the ribbon + the A12 fade. Always-on (code constant). ──
    @State private var field = ParticleField(count: 80)
    private static let particlesEnabled = true
    private static let particleIntensity = 0.7
    // Combine timer drives the whole dwell/fade state machine by ELAPSED TIME — it can't die and
    // never depends on animation-completion callbacks (those were dropping → scenes got stuck).
    private let autoTicker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    /// Preset indices eligible for the auto-rotation bag.
    private var eligibleIndices: [Int] {
        let native = presets.indices.filter { Self.includeAll76 ? true : presets[$0].sceneMode >= 1 }
        if Self.heroOnly { return native.filter { Self.heroModes.contains(presets[$0].sceneMode) } }
        return native
    }

    /// Coarse visual family (health-pass taxonomy) keyed by sceneMode, for the same-family-skip rule.
    /// 0 tunnels · 1 blobs · 2 star/space · 3 math-surface · 4 terrain · 5 grids/arch · 6 fracture ·
    /// 7 cymatics · 8 energy · 9 fractals · 10 interior/city · 11 liquid · 12 reaction · 13 hex · 14 circuit.
    private static let familyByScene: [Int: Int] = [
        1: 0, 10: 0, 2: 1, 11: 1, 3: 2, 4: 3, 24: 3, 5: 4, 12: 4,
        6: 5, 9: 5, 14: 5, 7: 6, 8: 6, 13: 7, 15: 8, 16: 8, 17: 9, 20: 9,
        18: 10, 26: 10, 19: 11, 25: 11, 21: 12, 22: 13, 23: 14, 27: 15
    ]
    private func family(_ idx: Int) -> Int {
        Self.familyByScene[presets[idx].sceneMode] ?? -1   // -1 = 2D feedback presets
    }

    private func refillBag() {
        var b = eligibleIndices.shuffled()
        if let first = b.first, first == presetIndex, b.count > 1 { b.swapAt(0, b.count - 1) }  // no seam-repeat
        bag = b
    }

    /// Pop the next scene; if it's the same family as the last, swap in a different-family one.
    private func advanceToNext() {
        if bag.isEmpty { refillBag() }
        guard !bag.isEmpty else { return }
        var idx = bag.removeFirst()
        if family(idx) == lastFamily, let altPos = bag.firstIndex(where: { family($0) != lastFamily }) {
            let alt = bag.remove(at: altPos)
            bag.insert(idx, at: 0)        // keep the same-family one for later
            idx = alt
        }
        presetIndex = idx
        lastFamily = family(idx)
    }

    private func nextDwell() -> Double {
        Self.dwellSeconds + Double.random(in: -Self.dwellJitter...Self.dwellJitter)
    }

    /// Start a fade-to-black. The visual tween is `withAnimation`; the *switch* and *reset* are
    /// decided by elapsed time in tick(), so a dropped animation completion can never strand it.
    @MainActor private func beginTransition() {
        guard transitionStart == nil else { return }
        transitionStart = Date()
        didSwitch = false
        withAnimation(.easeInOut(duration: Self.fadeSeconds)) { fadeOpacity = 1.0 }
    }

    /// Combine tick (~0.1s): advances any in-flight transition by elapsed time, else auto-advances
    /// when the dwell deadline passes. Purely time-driven → cannot get stuck.
    private func tick() {
        if let start = transitionStart {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= Self.fadeSeconds, !didSwitch {
                advanceToNext()                           // switch only at full black
                didSwitch = true
                withAnimation(.easeInOut(duration: Self.fadeSeconds)) { fadeOpacity = 0.0 }
            }
            if elapsed >= 2 * Self.fadeSeconds {          // fade-in done → transition complete
                transitionStart = nil
                didSwitch = false
                fadeOpacity = 0.0
            }
            return
        }
        if autoEnabled, Date() >= dwellDeadline {
            beginTransition()
            dwellDeadline = Date().addingTimeInterval(nextDwell())
        }
    }

    private func manualNext() {
        dwellDeadline = Date().addingTimeInterval(nextDwell())       // a manual swipe restarts the dwell
        beginTransition()
    }

    var body: some View {
        PermissiveMetalContainer(presetIndex: presetIndex)
            .ignoresSafeArea()
            // Star/spark particle swarm — bottom-most overlay (under the ribbon + the fade).
            .overlay {
                if Self.particlesEnabled {
                    ParticleSwarm(field: field, intensity: Self.particleIntensity).allowsHitTesting(false)
                }
            }
            // Audio-reactive spectrum ribbon — placed BEFORE the fade overlay so the fade covers it.
            .overlay {
                if overlayEnabled {
                    SpectrumRibbon(intensity: Self.overlayIntensity).allowsHitTesting(false)
                }
            }
            // Deliberate fade-to-black between scenes (no extra Metal targets; cheap layer composite).
            .overlay { Color.black.opacity(fadeOpacity).ignoresSafeArea().allowsHitTesting(false) }
            // Seed the bag + jump into the native rotation when the surface appears.
            .onAppear {
                if bag.isEmpty {
                    refillBag()
                    advanceToNext()    // jump into the native rotation at startup
                }
                dwellDeadline = Date().addingTimeInterval(nextDwell())
            }
            // Host (VisualizerView) horizontal swipe → advance to the next scene.
            .onChange(of: advanceToken) { _, _ in manualNext() }
            // Combine timer drives the dwell check — robust (auto-cancels on disappear, never "exits").
            .onReceive(autoTicker) { _ in tick() }
    }
}

/// A13 — audio-reactive spectrum ribbon (DEBUG-only). A vertically-CENTERED symmetric spectrum: the
/// 32 `AudioSpectrum.shared` bands reach up AND down from a glowing centerline (brightest at center,
/// fading to the mirrored edges). Redrawn at ~30fps via `TimelineView`; pure SwiftUI Canvas (no Metal,
/// no buffers). Subtle, additive, preserves dark space. (The native test screen is portrait-only.)
private struct SpectrumRibbon: View {
    let intensity: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            Canvas { ctx, size in
                let spec = AudioSpectrum.shared
                let bands = spec.bands
                guard bands.count > 1 else { return }
                let n = bands.count
                let t = context.date.timeIntervalSinceReferenceDate
                let idle = spec.energy < 0.02

                let centerY = size.height * 0.5                 // vertically centered
                let amp = size.height * 0.11                    // reach each direction from the centerline

                // Mirrored outlines (up + down) and the silhouette between them.
                var topPath = Path(); var botPath = Path(); var fillPath = Path()
                var pts = [CGPoint](); pts.reserveCapacity(n)
                for i in 0..<n {
                    let raw = idle
                        ? 0.12 + 0.10 * sin(t * 1.4 + Double(i) * 0.5)   // idle: gentle breathing
                        : Double(min(max(bands[i], 0), 1))
                    let x = size.width * CGFloat(i) / CGFloat(n - 1)
                    pts.append(CGPoint(x: x, y: CGFloat(raw) * amp))      // y = half-height from centre
                }
                for (i, p) in pts.enumerated() {
                    let up = CGPoint(x: p.x, y: centerY - p.y), dn = CGPoint(x: p.x, y: centerY + p.y)
                    if i == 0 { topPath.move(to: up); botPath.move(to: dn); fillPath.move(to: up) } else {
                        topPath.addLine(to: up); botPath.addLine(to: dn); fillPath.addLine(to: up)
                    }
                }
                for p in pts.reversed() { fillPath.addLine(to: CGPoint(x: p.x, y: centerY + p.y)) }
                fillPath.closeSubpath()

                // Colour from bass/mid/treble; glow scales with energy. Localized to the band only.
                let r = Double(min(max(spec.bass, 0), 1))
                let g = Double(min(max(spec.mid, 0), 1))
                let b = Double(min(max(spec.treble, 0), 1))
                let glow = 0.6 + 0.5 * Double(min(max(spec.energy, 0), 1))
                let col = Color(red: 0.40 + 0.55 * r, green: 0.45 + 0.50 * g, blue: 0.60 + 0.40 * b)
                let bright = Color(red: 0.7 + 0.3 * r, green: 0.75 + 0.25 * g, blue: 0.85 + 0.15 * b)

                ctx.opacity = intensity * glow                 // soft body, brightest at the centerline
                ctx.fill(fillPath, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: col.opacity(0.0), location: 0.0),
                        .init(color: col.opacity(0.9), location: 0.5),
                        .init(color: col.opacity(0.0), location: 1.0)
                    ]),
                    startPoint: CGPoint(x: size.width / 2, y: centerY - amp),
                    endPoint: CGPoint(x: size.width / 2, y: centerY + amp)))
                ctx.opacity = min(1.0, intensity * glow * 1.8)  // crisp mirrored outlines so it reads clearly
                ctx.stroke(topPath, with: .color(bright), lineWidth: 1.8)
                ctx.stroke(botPath, with: .color(bright), lineWidth: 1.8)
            }
            .ignoresSafeArea()
        }
    }
}

/// A14 — CPU-updated star/spark swarm (DEBUG-only). A fixed pre-allocated array of points drifting in a
/// faked-3D volume, streamed toward the camera by bass; updated in place each tick (no per-frame alloc).
private final class ParticleField {
    struct P { var pos: SIMD3<Float>; var vel: SIMD3<Float>; var seed: Float }
    var ps: [P]
    private var lastBass: Float = 0
    let near: Float = 0.4
    let far: Float = 4.6

    init(count: Int) { ps = (0..<count).map { _ in ParticleField.spawn(atFar: false) } }

    private static func spawn(atFar: Bool) -> P {
        let z = atFar ? Float.random(in: 3.6...4.6) : Float.random(in: 0.4...4.6)
        return P(pos: SIMD3(Float.random(in: -1.5...1.5), Float.random(in: -1.5...1.5), z),
                 vel: SIMD3(Float.random(in: -0.05...0.05), Float.random(in: -0.05...0.05), 0),
                 seed: Float.random(in: 0...1))
    }

    /// Integrate one step. `bass` streams particles toward the camera (with a Δbass burst); `mid` swirls.
    func update(dt: Float, bass: Float, mid: Float) {
        let dBass = max(0, bass - lastBass); lastBass = bass
        let push = 0.45 + 2.0 * bass + 6.0 * dBass               // forward stream speed (z toward camera)
        let swirl = 0.4 * mid * dt
        let cs = cos(swirl), sn = sin(swirl)
        for i in ps.indices {
            var p = ps[i]
            let nx = cs * p.pos.x - sn * p.pos.y, ny = sn * p.pos.x + cs * p.pos.y  // gentle swirl
            p.pos.x = nx + p.vel.x * dt
            p.pos.y = ny + p.vel.y * dt
            p.pos.z -= push * dt
            if p.pos.z < near { p = ParticleField.spawn(atFar: true) }   // streamed past → reseed at far
            ps[i] = p
        }
    }
}

/// A14 — draws the swarm with additive blending (small glowing dots, perspective size/brightness by depth).
private struct ParticleSwarm: View {
    let field: ParticleField
    let intensity: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            Canvas { ctx, size in
                let spec = AudioSpectrum.shared
                let t = context.date.timeIntervalSinceReferenceDate
                field.update(dt: 1.0 / 30.0, bass: spec.bass, mid: spec.mid)

                let cx = size.width / 2, cy = size.height / 2
                let focal = size.height * 0.5
                let baseR = size.height * 0.006
                let energy = Double(min(max(spec.energy, 0), 1))
                let treble = Double(min(max(spec.treble, 0), 1))
                let star = Color(red: 0.82, green: 0.88, blue: 1.0)

                ctx.blendMode = .plusLighter                    // additive glow where dots overlap
                for p in field.ps {
                    let z = max(p.pos.z, 0.05)
                    let invz = CGFloat(1.0 / z)
                    let sx = cx + CGFloat(p.pos.x) * invz * focal
                    let sy = cy + CGFloat(p.pos.y) * invz * focal
                    if sx < -30 || sx > size.width + 30 || sy < -30 || sy > size.height + 30 { continue }
                    let r = max(0.6, baseR * invz)
                    let flick = 0.7 + 0.3 * sin(t * 9.0 + Double(p.seed) * 37.0)      // sparkle
                    let depthB = min(1.0, Double(invz) * 0.45)
                    let bright = depthB * (0.45 + 0.6 * energy) * (1.0 - 0.5 * treble + 0.5 * treble * flick)
                    ctx.opacity = min(0.9, bright * intensity)
                    ctx.fill(Path(ellipseIn: CGRect(x: sx - r * 1.4, y: sy - r * 1.4, width: r * 2.8, height: r * 2.8)),
                             with: .color(star.opacity(0.30)))   // smaller halo (less additive overdraw)
                    ctx.fill(Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)),
                             with: .color(star))                 // core
                }
            }
            .ignoresSafeArea()
        }
    }
}

/// MTKView delegate. MetalKit invokes `draw(in:)` / `drawableSizeWillChange` on the
/// main thread, so the `@MainActor` audio read is reached via `assumeIsolated`.
final class PermissiveCoordinator: NSObject, MTKViewDelegate {
    let device: MTLDevice?
    private let renderer: PermissiveFeedbackRenderer?

    private let startTime = CACurrentMediaTime()
    private var frames = 0
    #if DEBUG
    // Proof scaffolding — dev-only. Never runs in Release (the 1×1 GPU readback would
    // otherwise cost a per-second pipeline sync in a shipping build).
    private var lastProofTime: CFTimeInterval = 0
    private var lastProofFrames = 0
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "PermissiveViz")
    #endif

    // Spectral-flux onset detector state (Step 6). `beatPulse` is a 0..1 envelope that
    // punches to ~1 on a transient and decays — the primary reactivity signal.
    private var prevBands = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    private var fluxAvg: Float = 0
    private var beatPulse: Float = 0

    // Step 8a — band-limited spectral-flux punch envelopes. Positive per-frame band rises
    // (the same signal that drives beatPulse) grouped into bass/mid/treble, peak-held with
    // decay. Robust to level saturation: it measures RISES, not absolute (clippable) level —
    // the fast/slow level EMA collapsed to 0 when bass/mid pinned at 1.0 on loud music.
    private var bassPunchEnv: Float = 0
    private var midPunchEnv: Float = 0
    private var treblePunchEnv: Float = 0
    private var lastPunch: SIMD3<Float> = .zero
    private var punchPeak: SIMD3<Float> = .zero   // peak over the last proof window (proof only)

    // Phase 14 — host-accumulated forward camera position for the 3D raymarch tunnel.
    private var camZ: Float = 0
    private var lastFrameTime: CFTimeInterval = 0

    // Step 7 — raw-PCM waveform geometry. We enable the PCM ring's tap only
    // while this surface is visible (and never while another consumer owns the ring), drain it into
    // a rolling mono window, and build a circular/scope line that the renderer draws into
    // the feedback field.
    static let waveWindow = 256
    private var pcmEnabledByMe = false
    private var waveHistory = [Float](repeating: 0, count: PermissiveCoordinator.waveWindow)
    private var waveWriteIdx = 0
    private var pcmScratch = [Float](repeating: 0, count: 4096 * 2)   // interleaved stereo
    private var lastPcmOn = false
    private var lastSampleCount = 0

    /// Become the PCM render consumer for as long as this surface is visible. No-op (and
    /// leaves `pcmEnabledByMe == false`) if another consumer already owns the ring, so two
    /// renderers never drain the single-producer/single-consumer ring at once.
    func enablePCM() {
        let src = VisualizerPCMSource.shared
        guard !src.hasActiveConsumer else { pcmEnabledByMe = false; return }
        src.beginRenderConsumer()
        pcmEnabledByMe = true
    }

    func disablePCM() {
        guard pcmEnabledByMe else { return }
        // Release ownership + turn the tap write off. endRenderConsumer() deliberately does
        // NOT reset() — the audio-tap producer may still be running, and reset() is not
        // producer-quiesce-safe. Leftover ring data is harmless; the next consumer drains it.
        VisualizerPCMSource.shared.endRenderConsumer()
        pcmEnabledByMe = false
    }

    /// Drain whatever PCM is available into the rolling mono window. Returns whether any
    /// real samples arrived this frame (→ `pcm=on` in the proof).
    private func drainPCM() -> Bool {
        guard pcmEnabledByMe else { return false }
        var any = false
        pcmScratch.withUnsafeMutableBufferPointer { buf in
            let got = VisualizerPCMSource.shared.read(into: buf.baseAddress!, maxFrames: 4096)
            if got > 0 {
                any = true
                for i in 0..<got {
                    waveHistory[waveWriteIdx] = 0.5 * (buf[2 * i] + buf[2 * i + 1])
                    waveWriteIdx = (waveWriteIdx + 1) % Self.waveWindow
                }
            }
        }
        return any
    }

    /// Build the waveform line in NDC. `style` 1 = circular (classic oscilloscope ring),
    /// 2 = horizontal scope. When PCM isn't live we synthesize a moving line so the idle
    /// screen still animates (the real test is with music).
    private func buildWave(style: Int, amp: Float, aspect: Float, live: Bool, time: Float) -> [SIMD2<Float>] {
        guard style != 0 else { return [] }
        let w = Self.waveWindow
        func sample(_ i: Int) -> Float {
            if live { return waveHistory[(waveWriteIdx + i) % w] }
            return 0.6 * sinf(time * 3.0 + Float(i) * 0.20) + 0.3 * sinf(time * 5.0 + Float(i) * 0.05)
        }
        var pts = [SIMD2<Float>](); pts.reserveCapacity(w + 1)
        if style == 1 {
            let baseR: Float = 0.45
            for i in 0..<w {
                let ang = 2 * Float.pi * Float(i) / Float(w)
                // Hann-window the displacement so the first/last sample both meet at baseR:
                // the oscilloscope window wrap then closes seamlessly instead of drawing a
                // fixed-angle chord that the feedback smears into a static line.
                let win = 0.5 - 0.5 * cosf(2 * Float.pi * Float(i) / Float(w - 1))
                let r = baseR + amp * sample(i) * win
                var x = r * cosf(ang), y = r * sinf(ang)
                if aspect >= 1 { x /= aspect } else { y *= aspect }
                pts.append(SIMD2(x, y))
            }
            pts.append(pts[0])   // close the ring (now seamless: both ends at baseR)
        } else {
            for i in 0..<w {
                let x = -1 + 2 * Float(i) / Float(w - 1)
                let y = amp * sample(i) * (aspect >= 1 ? 1 : aspect)
                pts.append(SIMD2(x, y))
            }
        }
        return pts
    }

    private let presets = PermissivePresetLibrary.presets
    private var presetIndex = 0
    private var activePreset: PermissivePreset {
        presets.indices.contains(presetIndex) ? presets[presetIndex] : .fallback
    }

    func setPresetIndex(_ index: Int) {
        guard !presets.isEmpty else { return }
        presetIndex = ((index % presets.count) + presets.count) % presets.count
    }

    #if DEBUG
    private lazy var proofURL: URL = {
        if let override = ProcessInfo.processInfo.environment["VIBRDROME_PERMISSIVE_PROOF"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("permissive_proof.txt")
    }()
    #endif

    override init() {
        let dev = MTLCreateSystemDefaultDevice()
        device = dev
        renderer = dev.flatMap { PermissiveFeedbackRenderer(device: $0) }
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer?.resize(to: size)
    }

    func draw(in view: MTKView) {
        // MetalKit calls this on the main thread; isolate so the @MainActor MTKView /
        // AudioEngine access is well-defined.
        MainActor.assumeIsolated { drawMainActor(in: view) }
    }

    @MainActor
    private func drawMainActor(in view: MTKView) {
        guard let renderer else { return }
        let now = CACurrentMediaTime()
        let time = Float(now - startTime)
        let audio = Self.sampleAudio(time: time)
        let p = activePreset
        let (pulse, punch) = updateAudio(bands: audio.bands)

        // 3D tunnel: integrate forward camera position from speed (bass + bass-punch surge).
        let dt = lastFrameTime == 0 ? 0 : Float(now - lastFrameTime)
        lastFrameTime = now
        if p.sceneMode > 0 { camZ += dt * (1.5 + 3.0 * audio.bass + 4.0 * punch.x) }

        // Build the waveform line from raw PCM (or a synthesized fallback when idle).
        let w = Float(view.drawableSize.width), h = Float(view.drawableSize.height)
        let aspect = h > 0 ? w / h : 1
        let pcmOn = drainPCM()
        // Beat amplitude burst: the waveform deviations grow on each kick (the "explosion").
        let waveAmp = p.waveAmp * (1 + p.beatWave * pulse)
        let wavePts = buildWave(style: p.waveStyle, amp: waveAmp, aspect: aspect, live: pcmOn, time: time)
        lastPcmOn = pcmOn
        lastSampleCount = wavePts.count

        renderer.setBands(audio.bands)
        renderer.setWaveform(wavePts)
        let u = PermissiveUniforms(
            resolution: SIMD2(w, h),
            time: time, bass: audio.bass, mid: audio.mid, treble: audio.treble,
            decay: p.decay, zoom: p.zoom, rotate: p.rotate, paletteShift: p.paletteShift,
            paletteIndex: Float(p.paletteIndex), pulseScale: p.pulseScale,
            zoomBass: p.zoomBass, rotateTreble: p.rotateTreble, pulseBass: p.pulseBass,
            bloomStrength: p.bloomStrength, waveformStrength: p.waveformStrength,
            flow: p.flow, flowScale: p.flowScale, beatFlow: p.beatFlow,
            beatBloom: p.beatBloom, hueDrift: p.hueDrift, beatPulse: pulse,
            tunnel: p.tunnel, waveBright: p.waveBright,
            symmetry: Float(p.symmetry), vibrance: p.vibrance, spin: p.spin,
            swirl: p.swirl, swirlFreq: p.swirlFreq, warpMode: Float(p.warpMode),
            bassPunch: punch.x, midPunch: punch.y, treblePunch: punch.z,
            kaleido: Float(p.kaleido), spokes: Float(p.spokes), spokeLen: p.spokeLen,
            spokeInject: Float(p.spokeInject), whirl: p.whirl,
            lattice: p.lattice, latticeR: p.latticeR, latticeA: p.latticeA, wash: p.wash,
            fractal: Float(p.fractal), cells: p.cells, spiral: p.spiral,
            tile: p.tile, pixelate: p.pixelate, truchet: p.truchet,
            tunnel3d: p.tunnel3d, plasma: p.plasma, phyllo: p.phyllo,
            ripple: p.ripple, hex: p.hex, chroma: p.chroma,
            sceneMode: Float(p.sceneMode), camZ: camZ)
        renderer.render(in: view, uniforms: u)
        frames += 1

        #if DEBUG
        // Proof + 1×1 center readback ONCE PER SECOND (never per frame). Dev-only.
        if now - lastProofTime >= 1.0 {
            let fps = frames - lastProofFrames
            let px = renderer.readCenter()
            writeProof(fps: fps, audio: audio, px: px)
            lastProofTime = now
            lastProofFrames = frames
        }
        #endif
    }

    private struct AudioFrame {
        let real: Bool; let energy: Float; let bass: Float; let mid: Float; let treble: Float
        let bands: [Float]
    }

    /// Use the real audio signal (AudioSpectrum, fed by the EQ tap) when energy is
    /// present; otherwise synthesize a gentle beat so the field animates idle.
    /// AudioSpectrum is non-isolated/Sendable, so no main-actor hop is needed.
    private static func sampleAudio(time: Float) -> AudioFrame {
        let s = AudioSpectrum.shared
        let energy = s.energy
        if energy > 0.02 {
            return AudioFrame(real: true, energy: energy, bass: s.bass, mid: s.mid, treble: s.treble, bands: s.bands)
        }
        // Fallback: synthesized beat + a moving 32-band pattern so the overlay animates.
        let bands = (0..<AudioSpectrum.bandCount).map { i in
            0.30 + 0.30 * sinf(time * 2.0 + Float(i) * 0.4)
        }
        return AudioFrame(real: false, energy: energy,
                          bass: 0.35 + 0.30 * sinf(time * 2.1),
                          mid: 0.30 + 0.25 * sinf(time * 1.6 + 1.0),
                          treble: 0.25 + 0.25 * sinf(time * 2.7 + 2.0),
                          bands: bands)
    }

    /// Combined audio reactivity from one pass over the band deltas. The overall positive
    /// spectral flux drives the beat onset (adaptive threshold → attack/decay `beatPulse`);
    /// band-grouped flux drives bass/mid/treble PUNCH envelopes (peak-hold + decay). Using
    /// per-frame flux (RISES, not absolute level) keeps punch alive on loud/clipped audio.
    private func updateAudio(bands: [Float]) -> (beat: Float, punch: SIMD3<Float>) {
        let n = min(bands.count, prevBands.count)
        var total: Float = 0, bF: Float = 0, mF: Float = 0, tF: Float = 0
        for i in 0..<n {
            let d = max(0, bands[i] - prevBands[i])
            total += d
            if i < 6 { bF += d } else if i < 17 { mF += d } else { tF += d }   // bass / mid / treble
        }
        prevBands = bands

        // Beat onset (adaptive threshold on the overall flux). Slice 2A: threshold
        // 1.5→1.35 so more beats register on busy/dense tracks; decay 0.88→0.86 for a
        // slightly snappier envelope. The `>0.04` floor stays as an over-trigger guard.
        fluxAvg = fluxAvg * 0.93 + total * 0.07
        if total > fluxAvg * 1.35 && total > 0.04 { beatPulse = min(1.0, beatPulse + 0.9) }
        beatPulse *= 0.86

        // Band punches: peak-hold the scaled group flux, decay each frame (VU-meter feel).
        // Slice 2B: mid/treble scale 1.5→1.8 (more ripple/swirl/bloom/grid/color snap) with a
        // snappier 0.82→0.78 snap-back. BASS punch is left byte-for-byte unchanged — it feeds
        // several 3D scenes' forward speed via u.bassPunch (Warpfield/Highway/Menger/Urban Canyon/
        // calm-glide) plus camZ, so touching it would risk faster 3D plunge. Bass stays as-is.
        bassPunchEnv = max(bassPunchEnv * 0.82, min(1.0, bF * 2.5))
        midPunchEnv = max(midPunchEnv * 0.78, min(1.0, mF * 1.8))
        treblePunchEnv = max(treblePunchEnv * 0.78, min(1.0, tF * 1.8))
        lastPunch = SIMD3(bassPunchEnv, midPunchEnv, treblePunchEnv)
        punchPeak = max(punchPeak, lastPunch)
        return (beatPulse, lastPunch)
    }

    #if DEBUG
    private func writeProof(fps: Int, audio: AudioFrame, px: (UInt8, UInt8, UInt8)) {
        let text = """
        engine=PermissiveFeedback
        api=Metal
        fps=\(fps)
        preset=\(activePreset.id)
        sceneMode=\(activePreset.sceneMode)
        marchSteps=\(PermissiveFeedbackRenderer.marchSteps)
        avgSteps=\(activePreset.sceneMode > 0 ? (renderer?.readAvgSteps() ?? 0) : 0)
        raymarchScale=\(String(format: "%.2f", Double(renderer?.raymarchScale ?? 1.0)))
        bloom=\(String(format: "%.2f", activePreset.bloomStrength))
        overlay=\(String(format: "%.2f", activePreset.waveformStrength))
        flow=\(String(format: "%.2f", activePreset.flow))
        beatPulse=\(String(format: "%.3f", beatPulse))
        waveStyle=\(activePreset.waveStyle)
        symmetry=\(activePreset.symmetry)
        vibrance=\(String(format: "%.2f", activePreset.vibrance))
        warpMode=\(activePreset.warpMode)
        swirl=\(String(format: "%.2f", activePreset.swirl))
        kaleido=\(activePreset.kaleido)
        spokes=\(activePreset.spokes)
        spokeLen=\(String(format: "%.2f", activePreset.spokeLen))
        spokeInject=\(activePreset.spokeInject)
        whirl=\(String(format: "%.2f", activePreset.whirl))
        bassPunch=\(String(format: "%.3f", punchPeak.x)) midPunch=\(String(format: "%.3f", punchPeak.y))
        treblePunch=\(String(format: "%.3f", punchPeak.z))
        pcm=\(lastPcmOn ? "on" : "off")
        samples=\(lastSampleCount)
        audio_source=\(audio.real ? "real" : "fallback")
        energy=\(String(format: "%.3f", audio.energy))
        bass=\(String(format: "%.3f", audio.bass)) mid=\(String(format: "%.3f", audio.mid)) treble=\(String(format: "%.3f", audio.treble))
        center_px=(\(px.0),\(px.1),\(px.2))
        third_party=none
        lgpl=none
        """
        try? (text + "\n").write(to: proofURL, atomically: true, encoding: .utf8)
        log.notice("PermissiveFeedback fps=\(fps) src=\(audio.real ? "real" : "fallback", privacy: .public) px=(\(px.0),\(px.1),\(px.2))")
        punchPeak = .zero   // reset the per-window peak after each proof write
    }
    #endif
}

#if canImport(UIKit)
struct PermissiveMetalContainer: UIViewRepresentable {
    let presetIndex: Int
    func makeCoordinator() -> PermissiveCoordinator { PermissiveCoordinator() }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        context.coordinator.setPresetIndex(presetIndex)
        context.coordinator.enablePCM()
        return view
    }
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.setPresetIndex(presetIndex)
    }
    static func dismantleUIView(_ uiView: MTKView, coordinator: PermissiveCoordinator) {
        coordinator.disablePCM()
    }
}
#else
struct PermissiveMetalContainer: NSViewRepresentable {
    let presetIndex: Int
    func makeCoordinator() -> PermissiveCoordinator { PermissiveCoordinator() }
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        context.coordinator.setPresetIndex(presetIndex)
        context.coordinator.enablePCM()
        return view
    }
    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.setPresetIndex(presetIndex)
    }
    static func dismantleNSView(_ nsView: MTKView, coordinator: PermissiveCoordinator) {
        coordinator.disablePCM()
    }
}
#endif
