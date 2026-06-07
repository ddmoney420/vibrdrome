#if DEBUG
import MetalKit
import QuartzCore
import SwiftUI
import os
import simd

/// Research Step 2 — DEBUG-only host for the native Metal feedback prototype. Reached
/// via Settings ▸ About ▸ Debug Tools ▸ Developer ▸ "Native Visualizer Test". Reads
/// `AudioSpectrum` scalar bass/mid/treble (with a synthesized fallback when nothing is
/// playing) and writes a proof file once per second.
struct PermissiveVisualizerView: View {
    @State private var presetIndex = 0
    private let presets = PermissivePresetLibrary.presets

    var body: some View {
        PermissiveMetalContainer(presetIndex: presetIndex)
            .ignoresSafeArea()
            // Top placement: the mini-player floats over the bottom of the app, so
            // a bottom control would be blocked.
            .overlay(alignment: .top) {
                if !presets.isEmpty {
                    Button {
                        presetIndex = (presetIndex + 1) % presets.count
                    } label: {
                        Text("\(presets[presetIndex].name) — tap to switch")
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .accessibilityIdentifier("permissivePresetSwitch")
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Native Visualizer Test")
    }
}

/// MTKView delegate. MetalKit invokes `draw(in:)` / `drawableSizeWillChange` on the
/// main thread, so the `@MainActor` audio read is reached via `assumeIsolated`.
final class PermissiveCoordinator: NSObject, MTKViewDelegate {
    let device: MTLDevice?
    private let renderer: PermissiveFeedbackRenderer?

    private let startTime = CACurrentMediaTime()
    private var frames = 0
    private var lastProofTime: CFTimeInterval = 0
    private var lastProofFrames = 0
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "PermissiveViz")

    // Spectral-flux onset detector state (Step 6). `beatPulse` is a 0..1 envelope that
    // punches to ~1 on a transient and decays — the primary reactivity signal.
    private var prevBands = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    private var fluxAvg: Float = 0
    private var beatPulse: Float = 0

    // Step 7 — raw-PCM waveform geometry (DEBUG-only). We enable the PCM ring's tap only
    // while this screen is visible (and never while projectM owns the ring), drain it into
    // a rolling mono window, and build a circular/scope line that the renderer draws into
    // the feedback field.
    static let waveWindow = 256
    private var pcmEnabledByMe = false
    private var waveHistory = [Float](repeating: 0, count: PermissiveCoordinator.waveWindow)
    private var waveWriteIdx = 0
    private var pcmScratch = [Float](repeating: 0, count: 4096 * 2)   // interleaved stereo
    private var lastPcmOn = false
    private var lastSampleCount = 0

    /// Enable the PCM tap for the duration this DEBUG screen is visible. No-op (and leaves
    /// `pcmEnabledByMe == false`) if projectM already owns the ring, so the two renderers
    /// never consume it at once.
    func enablePCM() {
        let src = VisualizerPCMSource.shared
        guard !src.hasActiveConsumer else { pcmEnabledByMe = false; return }
        src.setActiveForTesting(true)
        pcmEnabledByMe = true
    }

    func disablePCM() {
        guard pcmEnabledByMe else { return }
        // Clear the active flag so the tap's next write is a no-op. Deliberately do NOT
        // call reset() — the audio-tap producer may still be running, and reset() is not
        // producer-quiesce-safe (mirrors VisualizerPCMSource.endRenderConsumer). Leftover
        // ring data is harmless; the next consumer drains it.
        VisualizerPCMSource.shared.setActiveForTesting(false)
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

    /// Build the waveform line in NDC. `style` 1 = circular (classic MilkDrop ring),
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

    private lazy var proofURL: URL = {
        if let override = ProcessInfo.processInfo.environment["VIBRDROME_PERMISSIVE_PROOF"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("permissive_proof.txt")
    }()

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
        let pulse = updateBeat(bands: audio.bands)

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
            symmetry: Float(p.symmetry), vibrance: p.vibrance, spin: p.spin)
        renderer.render(in: view, uniforms: u)
        frames += 1

        // Proof + 1×1 center readback ONCE PER SECOND (never per frame).
        if now - lastProofTime >= 1.0 {
            let fps = frames - lastProofFrames
            let px = renderer.readCenter()
            writeProof(fps: fps, audio: audio, px: px)
            lastProofTime = now
            lastProofFrames = frames
        }
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

    /// Spectral-flux onset → attack/decay envelope. Sums the positive band-to-band
    /// increase, compares it to its own rolling average (adaptive threshold), punches
    /// `beatPulse` up on a transient, and decays it each frame. Continuous bass/mid/treble
    /// stay as secondary modulation in the shader; this is the primary beat signal.
    private func updateBeat(bands: [Float]) -> Float {
        var flux: Float = 0
        let n = min(bands.count, prevBands.count)
        for i in 0..<n { flux += max(0, bands[i] - prevBands[i]) }
        prevBands = bands
        fluxAvg = fluxAvg * 0.93 + flux * 0.07
        if flux > fluxAvg * 1.5 && flux > 0.04 {
            beatPulse = min(1.0, beatPulse + 0.9)       // fast attack
        }
        beatPulse *= 0.88                               // decay (~0.2s tail)
        return beatPulse
    }

    private func writeProof(fps: Int, audio: AudioFrame, px: (UInt8, UInt8, UInt8)) {
        let text = """
        engine=PermissiveFeedback
        api=Metal
        fps=\(fps)
        preset=\(activePreset.id)
        bloom=\(String(format: "%.2f", activePreset.bloomStrength))
        overlay=\(String(format: "%.2f", activePreset.waveformStrength))
        flow=\(String(format: "%.2f", activePreset.flow))
        beatPulse=\(String(format: "%.3f", beatPulse))
        waveStyle=\(activePreset.waveStyle)
        symmetry=\(activePreset.symmetry)
        vibrance=\(String(format: "%.2f", activePreset.vibrance))
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
    }
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
#endif
