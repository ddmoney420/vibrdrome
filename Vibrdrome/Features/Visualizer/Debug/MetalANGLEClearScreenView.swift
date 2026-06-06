#if DEBUG
import MetalANGLE
import QuartzCore
import SwiftUI
import os
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Phase 2A wiring proof (DEBUG only, never compiled into release).
///
/// Drives an `MGLKView` GLES3 context inside the real `com.vibrdrome.app` bundle
/// and animates a clear-screen, proving that the embedded **MetalANGLE** +
/// **projectM** frameworks link, load, and run GLES3 in-app. It does NOT touch
/// projectM's renderer, the audio PCM pipeline, or any user-facing visualizer —
/// that is Phase 2B onward. Reached only via Settings ▸ About ▸ Debug Tools ▸
/// MetalANGLE GLES3 Test, which is itself `#if DEBUG`.
///
/// Writes a plain-text proof (GL_VERSION / GL_RENDERER / fps) so an on-device run
/// can be verified by pulling the file, without a screenshot. The proof path is
/// `$VIBRDROME_GL_PROOF` if set, else the app tmp dir.
final class MetalANGLEClearScreenViewController: MGLKViewController {
    private var glContext: MGLContext?
    private var t: Double = 0
    private var frameCount = 0
    private var lastFpsLog: CFTimeInterval = 0
    private var lastFrames = 0
    private var glVersion = "?"
    private var glRenderer = "?"
    private let log = Logger(subsystem: "com.vibrdrome.app", category: "MetalANGLEProof")

    private lazy var proofURL: URL = {
        if let p = ProcessInfo.processInfo.environment["VIBRDROME_GL_PROOF"] {
            return URL(fileURLWithPath: p)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("metalangle_proof.txt")
    }()
    private func writeProof(_ s: String) {
        try? (s + "\n").write(to: proofURL, atomically: true, encoding: .utf8)
    }

    override func loadView() { view = MGLKView(frame: .zero) }

    // `glView` is an inherited MGLKViewController property (the bound MGLKView).

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredFramesPerSecond = 60

        let ctx = MGLContext(api: kMGLRenderingAPIOpenGLES3)
        glContext = ctx
        glView?.context = ctx
        MGLContext.setCurrent(ctx)

        glVersion = glString(GL_VERSION)
        glRenderer = glString(GL_RENDERER)
        log.notice("MetalANGLE GLES3 context: \(self.glVersion, privacy: .public) | \(self.glRenderer, privacy: .public)")
        writeProof("gl_version=\(glVersion)\ngl_renderer=\(glRenderer)\nrendering=pending(first-frame)")
    }

    private func glString(_ name: Int32) -> String {
        guard let s = glGetString(GLenum(name)) else { return "?" }
        return String(cString: s)
    }

    override func mglkView(_ view: MGLKView!, drawIn rect: CGRect) {
        t += 1.0 / 60.0
        let size = glView?.drawableSize ?? .zero

        // Animated clear so a live context is visually obvious (cycling hue).
        glViewport(0, 0, GLsizei(size.width), GLsizei(size.height))
        glClearColor(Float(0.5 + 0.5 * sin(t)),
                     Float(0.5 + 0.5 * sin(t + 2.094)),
                     Float(0.5 + 0.5 * sin(t + 4.188)), 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        frameCount += 1
        let now = CACurrentMediaTime()
        if now - lastFpsLog >= 1.0 {
            let fps = framesDisplayed - lastFrames
            log.notice("MetalANGLE clear-screen fps=\(fps) frames=\(self.frameCount)")
            writeProof("gl_version=\(glVersion)\ngl_renderer=\(glRenderer)\nrendering=YES\nframes=\(frameCount)\nfps=\(fps)")
            lastFrames = framesDisplayed
            lastFpsLog = now
        }
    }
}

/// SwiftUI host for the clear-screen controller (DEBUG only).
struct MetalANGLEClearScreenView: View {
    var body: some View {
        ClearScreenContainer()
            .ignoresSafeArea()
            .navigationTitle("MetalANGLE GLES3 Test")
    }
}

extension View {
    /// DEBUG verification hook: when the app is launched with the
    /// `VIBRDROME_GL_TEST` environment variable set, show the MetalANGLE
    /// clear-screen in place of the normal UI so the GLES3 render proof can be
    /// captured headlessly on device/Mac (no manual navigation). Users never set
    /// this variable; the whole hook is compiled out of release.
    @ViewBuilder
    func debugGLTestProof() -> some View {
        if ProcessInfo.processInfo.environment["VIBRDROME_GL_TEST"] != nil {
            MetalANGLEClearScreenView()
        } else {
            self
        }
    }
}

#if canImport(UIKit)
private struct ClearScreenContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> MetalANGLEClearScreenViewController {
        MetalANGLEClearScreenViewController()
    }
    func updateUIViewController(_ vc: MetalANGLEClearScreenViewController, context: Context) {}
}
#else
private struct ClearScreenContainer: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> MetalANGLEClearScreenViewController {
        MetalANGLEClearScreenViewController()
    }
    func updateNSViewController(_ vc: MetalANGLEClearScreenViewController, context: Context) {}
}
#endif
#endif
