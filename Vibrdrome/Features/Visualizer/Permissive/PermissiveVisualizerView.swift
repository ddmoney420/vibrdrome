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
    var body: some View {
        PermissiveMetalContainer()
            .ignoresSafeArea()
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

        let u = PermissiveUniforms(
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: time, bass: audio.bass, mid: audio.mid, treble: audio.treble,
            decay: 0.94, zoom: 0.03, rotate: 0.02, paletteShift: 0)
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

    private struct AudioFrame { let real: Bool; let energy: Float; let bass: Float; let mid: Float; let treble: Float }

    /// Use the real audio signal (AudioSpectrum, fed by the EQ tap) when energy is
    /// present; otherwise synthesize a gentle beat so the field animates idle.
    /// AudioSpectrum is non-isolated/Sendable, so no main-actor hop is needed.
    private static func sampleAudio(time: Float) -> AudioFrame {
        let s = AudioSpectrum.shared
        let energy = s.energy
        if energy > 0.02 {
            return AudioFrame(real: true, energy: energy, bass: s.bass, mid: s.mid, treble: s.treble)
        }
        return AudioFrame(real: false, energy: energy,
                          bass: 0.35 + 0.30 * sinf(time * 2.1),
                          mid: 0.30 + 0.25 * sinf(time * 1.6 + 1.0),
                          treble: 0.25 + 0.25 * sinf(time * 2.7 + 2.0))
    }

    private func writeProof(fps: Int, audio: AudioFrame, px: (UInt8, UInt8, UInt8)) {
        let text = """
        engine=PermissiveFeedback
        api=Metal
        fps=\(fps)
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
    func makeCoordinator() -> PermissiveCoordinator { PermissiveCoordinator() }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        return view
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}
}
#else
struct PermissiveMetalContainer: NSViewRepresentable {
    func makeCoordinator() -> PermissiveCoordinator { PermissiveCoordinator() }
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        return view
    }
    func updateNSView(_ nsView: MTKView, context: Context) {}
}
#endif
#endif
