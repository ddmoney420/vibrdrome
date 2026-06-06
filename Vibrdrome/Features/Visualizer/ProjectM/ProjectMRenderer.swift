import Foundation
import MetalANGLE   // eglGetProcAddress (exposed via the Phase 2A module map)
import projectM

/// Thread-confined projectM engine (Phase 2B). Owns the `projectm_handle` and is
/// the sole consumer of `VisualizerPCMSource`'s PCM ring while alive.
///
/// INVARIANT: every `projectm_*` call here runs on the render thread — the
/// `MGLKView` display-link thread, i.e. the **main thread**. `@unchecked Sendable`
/// is justified ONLY by that confinement; the raw handle is never touched off that
/// thread.
final class ProjectMRenderer: @unchecked Sendable {
    private var pm: OpaquePointer?
    private var triedCreate = false
    private var lastSize: CGSize = .zero

    /// projectM's GL loader: resolve via `dlsym(RTLD_DEFAULT, …)` first (MetalANGLE
    /// exports the GLES core symbols), then fall back to `eglGetProcAddress`. This
    /// is the exact pattern proven in the Phase 0 spike. It is a non-capturing
    /// closure so it can be used as a C function pointer.
    private static let loadProc: projectm_load_proc = { name, _ in
        guard let name else { return nil }
        // Darwin's RTLD_DEFAULT pseudo-handle. `<dlfcn.h>` defines it as
        // `((void *)-2)`, a macro Swift does not import, so we reconstruct the same
        // value here. `dlsym(RTLD_DEFAULT, …)` searches every image loaded in the
        // process — including the GLES core symbols MetalANGLE exports — so the gl*
        // entry points resolve even when `eglGetProcAddress` alone won't on ANGLE.
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        if let symbol = dlsym(rtldDefault, name) { return symbol }
        return unsafeBitCast(eglGetProcAddress(name), to: UnsafeMutableRawPointer?.self)
    }

    var isCreated: Bool { pm != nil }

    /// Create lazily on the first frame that has a real drawable size (creation
    /// before an FBO is bound returns NULL — confirmed in the spike). Loads the
    /// given preset (or the first bundled `.milk` as a fallback) and keeps projectM
    /// preset-locked — every transition is Swift-driven (Phase 2D), no playlist lib.
    func createIfNeeded(drawableSize size: CGSize, initialPreset: URL?) {
        guard pm == nil, !triedCreate, size.width > 0, size.height > 0 else { return }
        triedCreate = true
        guard let handle = projectm_create_with_opengl_load_proc(Self.loadProc, nil) else { return }
        pm = handle
        projectm_set_window_size(handle, Int(size.width), Int(size.height))
        lastSize = size
        let preset = initialPreset
            ?? Bundle.main.urls(forResourcesWithExtension: "milk", subdirectory: nil)?.first
        if let preset {
            preset.path.withCString { projectm_load_preset_file(handle, $0, false) }
        }
        projectm_set_preset_locked(handle, true)
    }

    /// Switch to a preset on the render thread. `hardCut: false` blends smoothly.
    func loadPreset(url: URL, hardCut: Bool = false) {
        guard let pm else { return }
        url.path.withCString { projectm_load_preset_file(pm, $0, hardCut) }
    }

    /// Feed interleaved-stereo frames (length `frames * 2`). projectM keeps a
    /// rolling window, so feeding everything drained keeps visuals current.
    func feed(_ pcm: UnsafePointer<Float>, frames: Int) {
        guard let pm, frames > 0 else { return }
        projectm_pcm_add_float(pm, pcm, UInt32(frames), PROJECTM_STEREO)
    }

    /// Render one frame into the view's framebuffer. Updates projectM's window size
    /// only when the drawable size actually changes (rotation / window resize).
    func render(fbo: UInt32, drawableSize size: CGSize) {
        guard let pm else { return }
        if size != lastSize, size.width > 0, size.height > 0 {
            projectm_set_window_size(pm, Int(size.width), Int(size.height))
            lastSize = size
        }
        projectm_opengl_render_frame_fbo(pm, fbo)
    }

    /// Destroy on the render thread. Idempotent; after this `feed`/`render` no-op
    /// and the next `createIfNeeded` re-creates.
    func destroy() {
        if let pm { projectm_destroy(pm) }
        pm = nil
        triedCreate = false
        lastSize = .zero
    }
}
