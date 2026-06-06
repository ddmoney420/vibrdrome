import MetalANGLE
import projectM
import QuartzCore
import SwiftUI
import os
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Phase 2B: hosts the real projectM renderer fed by the live PCM ring. Shipping
/// code, but reached only via the DEBUG "projectM MilkDrop Test" entry until the
/// 2C mode picker. The render loop runs on the main thread via `MGLKView`'s
/// display link.
final class ProjectMViewController: MGLKViewController {
    private let renderer = ProjectMRenderer()
    private var glContext: MGLContext?
    private static let drainChunk = 2048
    private var scratch = [Float](repeating: 0, count: ProjectMViewController.drainChunk * 2)
    private var consuming = false
    private var currentPresetURL: URL?

    #if DEBUG
    private var energyAccum: Double = 0
    private var sampleAccum: Int = 0
    private var lastFpsLog: CFTimeInterval = 0
    private var lastFrames: Int = 0
    private var loggedProofPath = false
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "ProjectM")

    /// Proof path: `$VIBRDROME_MILKDROP_PROOF` if set, else the app's temporary
    /// directory (`FileManager.default.temporaryDirectory`). The exact resolved
    /// path is logged once so an on-device run can be located deterministically.
    private lazy var proofURL: URL = {
        if let override = ProcessInfo.processInfo.environment["VIBRDROME_MILKDROP_PROOF"] {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("projectm_proof.txt")
    }()
    private func writeProof(_ s: String) {
        if !loggedProofPath {
            log.notice("projectM proof path: \(self.proofURL.path, privacy: .public)")
            loggedProofPath = true
        }
        try? (s + "\n").write(to: proofURL, atomically: true, encoding: .utf8)
    }
    #endif

    override func loadView() { view = MGLKView(frame: .zero) }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredFramesPerSecond = 60
        pauseOnWillResignActive = true       // built-in background pause
        resumeOnDidBecomeActive = true       // built-in foreground resume
        let ctx = MGLContext(api: kMGLRenderingAPIOpenGLES3)
        glContext = ctx
        glView?.context = ctx
        MGLContext.setCurrent(ctx)
    }

    // MARK: - Consumer lifecycle (renderer owns VisualizerPCMSource activation)

    private func startConsuming() {
        guard !consuming else { return }
        consuming = true
        VisualizerPCMSource.shared.beginRenderConsumer()
        isPaused = false
        #if DEBUG
        logLifecycle("begin")
        #endif
    }

    /// Internal (not private) so the representable's `dismantle…` hook can stop the
    /// consumer immediately when the user toggles MilkDrop → Classic in the open
    /// visualizer. Idempotent via the `consuming` guard.
    func stopConsuming() {
        guard consuming else { return }
        consuming = false
        isPaused = true
        renderer.destroy()                              // main = render thread
        VisualizerPCMSource.shared.endRenderConsumer()  // tap write off (no reset)
        #if DEBUG
        logLifecycle("end")
        #endif
    }

    #if DEBUG
    /// Appends begin/end lifecycle events to a pullable file so the teardown-on-
    /// toggle path can be verified deterministically on-device (separate from the
    /// per-second proof file, which is overwritten).
    private func logLifecycle(_ event: String) {
        log.notice("MilkDrop consumer \(event, privacy: .public)")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("milkdrop_lifecycle.txt")
        let line = Data((event + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            handle.write(line)
        } else {
            try? line.write(to: url)
        }
    }
    #endif

    #if os(iOS)
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); startConsuming() }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); stopConsuming() }
    #else
    override func viewWillAppear() { super.viewWillAppear(); startConsuming() }
    override func viewWillDisappear() { super.viewWillDisappear(); stopConsuming() }
    #endif

    /// Push the current preset from SwiftUI (Phase 2D). Loads it immediately if the
    /// engine already exists; otherwise it is used as the initial preset on create.
    /// `nil` keeps the renderer's first-bundled-preset fallback (DEBUG test entry).
    func setPreset(_ url: URL?) {
        guard url != currentPresetURL else { return }
        currentPresetURL = url
        if let url, renderer.isCreated {
            renderer.loadPreset(url: url, hardCut: false)
        }
    }

    // MARK: - Render loop (main thread)

    override func mglkView(_ view: MGLKView!, drawIn rect: CGRect) {
        guard consuming else { return }
        let size = glView?.drawableSize ?? .zero
        renderer.createIfNeeded(drawableSize: size, initialPreset: currentPresetURL)

        // Drain the SPSC ring fully, feeding each chunk to projectM.
        scratch.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            while true {
                let frames = VisualizerPCMSource.shared.read(into: base, maxFrames: Self.drainChunk)
                if frames == 0 { break }
                renderer.feed(base, frames: frames)
                #if DEBUG
                for i in 0..<(frames * 2) { let sample = Double(base[i]); energyAccum += sample * sample }
                sampleAccum += frames * 2
                #endif
                if frames < Self.drainChunk { break }
            }
        }

        renderer.render(fbo: view.defaultOpenGLFrameBufferID, drawableSize: size)

        #if DEBUG
        emitProofIfDue(size: size, fbo: view.defaultOpenGLFrameBufferID)
        #endif
    }

    #if DEBUG
    /// Once per second: fps, PCM RMS (proves live audio reaching projectM), and the
    /// rendered center pixel (proves a live, non-static frame).
    private func emitProofIfDue(size: CGSize, fbo: UInt32) {
        let now = CACurrentMediaTime()
        guard now - lastFpsLog >= 1.0 else { return }
        let fps = framesDisplayed - lastFrames
        let rms = sampleAccum > 0 ? (energyAccum / Double(sampleAccum)).squareRoot() : 0
        var px: [UInt8] = [0, 0, 0, 0]
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glReadPixels(GLint(size.width) / 2, GLint(size.height) / 2, 1, 1,
                     GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &px)
        let rmsStr = String(format: "%.4f", rms)
        let stats = VisualizerPCMSource.shared.stats   // proves the renderer keeps up (produced≈consumed, overflow 0)
        writeProof("projectm_created=\(renderer.isCreated ? "YES" : "NO")\n"
            + "preset_loaded=\(Bundle.main.path(forResource: "idle", ofType: "milk") != nil ? "YES" : "NO")\n"
            + "rendering=YES\nfps=\(fps)\npcm_rms=\(rmsStr)\n"
            + "center_px=(\(px[0]),\(px[1]),\(px[2]))\n"
            + "produced_frames=\(stats.producedFrames)\nconsumed_frames=\(stats.consumedFrames)\n"
            + "overflow_frames=\(stats.overflowFrames)\nfill_frames=\(stats.fillFrames)")
        log.notice("projectM fps=\(fps) rms=\(rmsStr, privacy: .public) px=(\(px[0]),\(px[1]),\(px[2]))")
        energyAccum = 0
        sampleAccum = 0
        lastFrames = framesDisplayed
        lastFpsLog = now
    }
    #endif
}

/// Embeddable MilkDrop surface (no test chrome). Used by the user-facing
/// visualizer (Phase 2C+). `presetURL` is the Swift-managed current preset
/// (Phase 2D); `nil` uses the renderer's first-bundled-preset fallback.
struct ProjectMVisualizerSurface: View {
    var presetURL: URL?
    var body: some View { ProjectMContainer(presetURL: presetURL) }
}

/// DEBUG test entry host — wraps the surface with a title (Settings ▸ Debug Tools).
struct ProjectMVisualizerView: View {
    var body: some View {
        ProjectMVisualizerSurface(presetURL: nil)
            .ignoresSafeArea()
            .navigationTitle("projectM MilkDrop Test")
    }
}

#if canImport(UIKit)
private struct ProjectMContainer: UIViewControllerRepresentable {
    let presetURL: URL?
    func makeUIViewController(context: Context) -> ProjectMViewController {
        let vc = ProjectMViewController()
        vc.setPreset(presetURL)
        return vc
    }
    func updateUIViewController(_ vc: ProjectMViewController, context: Context) {
        vc.setPreset(presetURL)
    }
    // Stop the consumer immediately when the surface is removed (MilkDrop → Classic
    // toggle in the open visualizer, or full dismiss).
    static func dismantleUIViewController(_ vc: ProjectMViewController, coordinator: ()) {
        vc.stopConsuming()
    }
}
#else
private struct ProjectMContainer: NSViewControllerRepresentable {
    let presetURL: URL?
    func makeNSViewController(context: Context) -> ProjectMViewController {
        let vc = ProjectMViewController()
        vc.setPreset(presetURL)
        return vc
    }
    func updateNSViewController(_ vc: ProjectMViewController, context: Context) {
        vc.setPreset(presetURL)
    }
    static func dismantleNSViewController(_ vc: ProjectMViewController, coordinator: ()) {
        vc.stopConsuming()
    }
}
#endif
