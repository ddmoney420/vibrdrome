import Foundation
import QuartzCore
import os
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Smallest possible MGLKit / GLES3 proof: an MGLKViewController subclass that
/// creates a GLES3 context via MetalANGLE and clears the screen to a slowly
/// shifting colour every frame. Logs GL_VERSION/GL_RENDERER once and fps each
/// second so the device run can be verified from the console without a
/// screenshot. No app-pipeline / projectM code here — toolchain proof only.
final class GLClearViewController: MGLKViewController {
    private var glContext: MGLContext?
    private var t: Double = 0
    private var lastFpsLog: CFTimeInterval = 0
    private var lastFrames: Int = 0
    private var frameCount: Int = 0
    private let log = Logger(subsystem: "com.vibrdrome.projectmspike", category: "gl")

    /// Where to write a plain-text render proof (GL_VERSION + frame/fps), so the
    /// spike can be verified from the console / device container without a
    /// screenshot. Env override `SPIKE_PROOF` (Mac), else the app's tmp dir.
    private lazy var proofURL: URL = {
        if let p = ProcessInfo.processInfo.environment["SPIKE_PROOF"] { return URL(fileURLWithPath: p) }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("projectmspike_proof.txt")
    }()

    private func writeProof(_ line: String) {
        try? line.appending("\n").write(to: proofURL, atomically: true, encoding: .utf8)
    }

    // Code-only: provide the MGLKView as this controller's view (no storyboard).
    override func loadView() {
        view = MGLKView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredFramesPerSecond = 60

        let ctx = MGLContext(api: kMGLRenderingAPIOpenGLES3)
        glContext = ctx
        glView?.context = ctx
        MGLContext.setCurrent(ctx)

        let version = glGetString(GLenum(GL_VERSION)).map { String(cString: $0) } ?? "(null)"
        let renderer = glGetString(GLenum(GL_RENDERER)).map { String(cString: $0) } ?? "(null)"
        log.notice("GLES3 context created — GL_VERSION=\(version, privacy: .public) GL_RENDERER=\(renderer, privacy: .public)")
        writeProof("GLES3 context created\nGL_VERSION=\(version)\nGL_RENDERER=\(renderer)\nframes=0")
    }

    override func mglkView(_ view: MGLKView!, drawIn rect: CGRect) {
        t += 1.0 / 60.0
        let r = Float(0.5 + 0.5 * sin(t))
        let g = Float(0.5 + 0.5 * sin(t + 2.094))
        let b = Float(0.5 + 0.5 * sin(t + 4.188))

        let size = glView?.drawableSize ?? .zero
        glViewport(0, 0, GLsizei(size.width), GLsizei(size.height))
        glClearColor(r, g, b, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        frameCount += 1
        let now = CACurrentMediaTime()
        if now - lastFpsLog >= 1.0 {
            let frames = framesDisplayed
            let fps = frames - lastFrames
            log.notice("clear-screen rendering — fps=\(fps)")
            writeProof("GLES3 context created\nGL_VERSION=\(glGetString(GLenum(GL_VERSION)).map { String(cString: $0) } ?? "?")\nrendering=YES\nframes=\(frameCount)\nfps=\(fps)\ncolor=(\(r),\(g),\(b))")
            lastFrames = frames
            lastFpsLog = now
        }
    }
}
