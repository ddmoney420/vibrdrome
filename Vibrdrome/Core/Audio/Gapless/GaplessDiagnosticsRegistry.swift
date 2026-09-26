#if DEBUG
import Foundation

/// DEBUG-only weak pointer to whichever `GaplessPlaybackController` is currently alive, so the Debug
/// screen can read its lead-time statistics without the app holding a reference it does not
/// otherwise need.
///
/// **Weak on purpose.** A strong reference here would keep a stopped controller — and its engine,
/// buffers, converters and open files — alive for the life of the process, which is precisely the
/// class of retention this engine spent two checkpoints eliminating.
///
/// Compiled out of release builds entirely.
@MainActor
enum GaplessDiagnosticsRegistry {
    /// The controller a diagnostics view should read, if one exists.
    private(set) static weak var current: GaplessPlaybackController?

    static func register(_ controller: GaplessPlaybackController) { current = controller }

    static func unregister(_ controller: GaplessPlaybackController) {
        if current === controller { current = nil }
    }
}
#endif
