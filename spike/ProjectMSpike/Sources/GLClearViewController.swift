import Foundation
import QuartzCore
import os
import projectM
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// projectM's own log output (captures the GLResolver/GLAD/create failure reason)
// routed to a file so the spike run can be diagnosed without the unified log.
private let pmLogURL = URL(fileURLWithPath:
    ProcessInfo.processInfo.environment["SPIKE_PMLOG"] ?? (NSTemporaryDirectory() + "pm_pmlog.txt"))
private func spikeAppendPMLog(_ s: String) {
    guard let data = (s + "\n").data(using: .utf8) else { return }
    if let fh = try? FileHandle(forWritingTo: pmLogURL) {
        defer { try? fh.close() }; _ = try? fh.seekToEnd(); fh.write(data)
    } else { try? data.write(to: pmLogURL) }
}
private let spikePMLogCallback: projectm_log_callback = { msg, level, _ in
    spikeAppendPMLog("pm[\(level.rawValue)] " + (msg.map { String(cString: $0) } ?? "?"))
}

/// Phase 0 render-wiring proof: drive libprojectM through MetalANGLE's GLES3
/// context. Creates a projectM instance with `projectm_create_with_opengl_load_proc`
/// fed by MetalANGLE's `eglGetProcAddress`, loads one bundled `.milk` preset,
/// feeds synthetic PCM, and renders each frame into the MGLKView's framebuffer.
/// Writes a plain-text proof (version, preset, fps, pcm energy) so the run can be
/// verified on device/Mac without a screenshot. Falls back to a clear-screen if
/// projectM can't be created, so failure is observable.
final class GLClearViewController: MGLKViewController {
    private var glContext: MGLContext?
    private var pm: OpaquePointer?
    private var t: Double = 0
    private var frameCount: Int = 0
    private var lastFpsLog: CFTimeInterval = 0
    private var lastFrames: Int = 0
    private var presetLoaded = false
    private var pmVersion = "?"
    private let log = Logger(subsystem: "com.vibrdrome.projectmspike", category: "gl")

    // Interleaved stereo synthetic PCM scratch (512 frames * 2 ch).
    private static let pcmFrames = 512
    private var pcm = [Float](repeating: 0, count: pcmFrames * 2)

    private lazy var proofURL: URL = {
        if let p = ProcessInfo.processInfo.environment["SPIKE_PROOF"] { return URL(fileURLWithPath: p) }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("projectmspike_proof.txt")
    }()
    private func writeProof(_ s: String) { try? (s + "\n").write(to: proofURL, atomically: true, encoding: .utf8) }

    override func loadView() { view = MGLKView(frame: .zero) }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredFramesPerSecond = 60

        try? "".write(to: pmLogURL, atomically: true, encoding: .utf8)   // reset
        projectm_set_log_level(PROJECTM_LOG_LEVEL_TRACE, false)
        projectm_set_log_callback(spikePMLogCallback, false, nil)

        let ctx = MGLContext(api: kMGLRenderingAPIOpenGLES3)
        glContext = ctx
        glView?.context = ctx
        MGLContext.setCurrent(ctx)

        var maj: Int32 = 0, min: Int32 = 0, pat: Int32 = 0
        projectm_get_version_components(&maj, &min, &pat)
        pmVersion = "\(maj).\(min).\(pat)"
        // Diagnostic: can we resolve a CORE GL symbol? (eglGetProcAddress alone
        // often can't on ANGLE; MetalANGLE exports them so dlsym can.)
        let viaDlsym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "glClear") != nil
        let viaEgl = unsafeBitCast(eglGetProcAddress("glClear"), to: UnsafeMutableRawPointer?.self) != nil
        log.notice("loader probe: glClear dlsym=\(viaDlsym) egl=\(viaEgl); projectM \(self.pmVersion, privacy: .public)")
        writeProof("projectm_version=\(pmVersion)\nloader_glClear_dlsym=\(viaDlsym)\nloader_glClear_egl=\(viaEgl)\nprojectm_created=pending(first-frame)")
    }

    /// projectM resolves GL via this loader: prefer dlsym against the process
    /// (MetalANGLE exports the GLES core symbols), fall back to eglGetProcAddress.
    private let loadProc: projectm_load_proc = { name, _ in
        guard let name else { return nil }
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) { return sym }
        return unsafeBitCast(eglGetProcAddress(name), to: UnsafeMutableRawPointer?.self)
    }

    /// Create projectM lazily on the first frame, when the MGLKView has bound a
    /// real framebuffer + drawable size (creation in viewDidLoad returned NULL).
    private func ensureProjectM(drawableSize size: CGSize) {
        guard pm == nil, !triedCreate else { return }
        triedCreate = true
        pm = projectm_create_with_opengl_load_proc(loadProc, nil)
        guard let pm else {
            log.error("projectm_create_with_opengl_load_proc returned NULL")
            writeProof("projectm_version=\(pmVersion)\nprojectm_created=NO\nNOTE=fell back to clear-screen")
            return
        }
        projectm_set_window_size(pm, Int(size.width), Int(size.height))
        if let path = Bundle.main.path(forResource: "idle", ofType: "milk") {
            path.withCString { projectm_load_preset_file(pm, $0, false) }
            presetLoaded = true
        }
        log.notice("projectM created; preset loaded=\(self.presetLoaded)")
    }
    private var triedCreate = false

    override func mglkView(_ view: MGLKView!, drawIn rect: CGRect) {
        t += 1.0 / 60.0
        let size = glView?.drawableSize ?? .zero
        ensureProjectM(drawableSize: size)

        guard let pm else {
            // Fallback so a creation failure is visibly distinct (pulsing red).
            glViewport(0, 0, GLsizei(size.width), GLsizei(size.height))
            glClearColor(Float(0.5 + 0.5 * sin(t)), 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            return
        }

        // Synthetic stereo PCM: 440Hz sine with an amplitude-modulated envelope,
        // so the preset has a clear "beat" to react to.
        let env = Float(0.15 + 0.85 * pow(0.5 + 0.5 * sin(t * 2.0), 4))   // pulsing beat
        for i in 0..<Self.pcmFrames {
            let ph = Float(t) * 440.0 * 2.0 * .pi + Float(i) * 0.05
            let s = sinf(ph) * env
            pcm[i * 2] = s
            pcm[i * 2 + 1] = s
        }
        pcm.withUnsafeBufferPointer { buf in
            projectm_pcm_add_float(pm, buf.baseAddress, UInt32(Self.pcmFrames), PROJECTM_STEREO)
        }

        projectm_set_window_size(pm, Int(size.width), Int(size.height))
        projectm_opengl_render_frame_fbo(pm, UInt32(view.defaultOpenGLFrameBufferID))

        frameCount += 1
        let now = CACurrentMediaTime()
        if now - lastFpsLog >= 1.0 {
            let fps = framesDisplayed - lastFrames
            // Sample the rendered framebuffer center pixel: a changing value over
            // time proves a live preset (not a static clear); logged with pcm_env
            // so reactivity to the synthetic audio can be inspected.
            var px: [UInt8] = [0, 0, 0, 0]
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), UInt32(view.defaultOpenGLFrameBufferID))
            glReadPixels(GLint(size.width) / 2, GLint(size.height) / 2, 1, 1,
                         GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &px)
            spikeAppendPMLog("sample frame=\(frameCount) fps=\(fps) env=\(String(format: "%.2f", env)) center_px=(\(px[0]),\(px[1]),\(px[2]))")
            log.notice("projectM rendering fps=\(fps) env=\(env) px=(\(px[0]),\(px[1]),\(px[2]))")
            writeProof("projectm_created=YES\nprojectm_version=\(pmVersion)\npreset_loaded=\(presetLoaded)\nrendering=YES\nframes=\(frameCount)\nfps=\(fps)\npcm_env=\(env)\ncenter_px=(\(px[0]),\(px[1]),\(px[2]))")
            lastFrames = framesDisplayed
            lastFpsLog = now
        }
    }
    // (Spike: projectM instance lives for the app's lifetime; the OS reclaims it
    // on exit. A real integration destroys it on teardown from a main-actor hook.)
}
