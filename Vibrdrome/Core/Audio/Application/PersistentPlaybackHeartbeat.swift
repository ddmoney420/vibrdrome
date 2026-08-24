import Foundation

/// What the heartbeat is doing, for the Debug screen. Closed and numeric — no URL, path, credential
/// or header can reach it.
struct PersistentHeartbeatDiagnostics: Equatable, Sendable {
    var isRunning = false
    /// The planning generation this heartbeat belongs to.
    var sessionGeneration: UInt64 = 0
    var tickCount = 0
    /// Seconds since the last completed tick, or nil if none has run.
    var lastTickAge: TimeInterval?
    var startCount = 0
    var cancellationCount = 0
    /// Ticks executing right now. **Must be 0 or 1.**
    var concurrentCount = 0
    /// Highest `concurrentCount` ever observed, so a duplicate heartbeat is caught after the fact
    /// rather than only if a test happens to look during the overlap.
    var peakConcurrentCount = 0

    var summary: String {
        """
        Persistent heartbeat: \(isRunning ? "Running" : "Stopped")
        Heartbeat session generation: \(sessionGeneration)
        Heartbeat tick count: \(tickCount)
        Last tick age: \(lastTickAge.map { String(format: "%.3f s", $0) } ?? "never")
        Heartbeat start count: \(startCount)
        Heartbeat cancellation count: \(cancellationCount)
        Concurrent heartbeat count: \(peakConcurrentCount)
        """
    }
}

/// Drives `GaplessPlaybackController.tick()` for the persistent session that currently owns audio.
///
/// **Why a heartbeat is needed at all.** Buffer *refill* is already self-sustaining: the recycle
/// inbox signals `pump()` as the node finishes with each buffer. What only happens inside `tick()`
/// is observing the render clock, draining boundary events, advancing the session, and topping the
/// prefetch window — so without something driving it, the first track plays, no boundary is ever
/// observed, the queue never advances, and the engine runs dry at the end of the track.
///
/// **One session, at most one heartbeat.** `start` cancels whatever was running before it installs
/// anything, and every tick is gated on the session generation it was started for, so a loop
/// belonging to a replaced session cannot drain boundaries for its successor, advance the new
/// queue, or mark it audible. Cancellation is cooperative, so that guard — not the cancel — is what
/// makes the invariant hold.
@MainActor
final class PersistentPlaybackHeartbeat {

    /// **50 ms.**
    ///
    /// There is no existing production cadence to inherit: the only repeating drivers in the
    /// project are `AudioEngine`'s 0.5 s periodic time observer (playback progress for Now Playing
    /// and scrobble accounting), `SleepTimer`'s 1 s countdown, and `PCMDebugMonitor`'s 60 Hz
    /// visualizer sampler — and none of them drives this controller. The gapless test harnesses use
    /// 4 ms, which exists to make sub-second fixtures resolve promptly rather than to model
    /// production.
    ///
    /// 50 ms is chosen against what a tick is actually responsible for. Audio continuity does not
    /// depend on it, because refill is inbox-driven; what depends on it is how quickly a track
    /// boundary is *observed*, which is when the queue index and current song change at a gapless
    /// join. An order of magnitude inside the 0.5 s the legacy engine already uses for progress
    /// keeps that invisible, while costing 20 main-actor wakeups a second instead of 250.
    static let interval: Duration = .milliseconds(50)

    /// Weak: the controller owns its session, and a heartbeat must never be the reason a torn-down
    /// engine stays alive.
    private weak var controller: GaplessPlaybackController?
    private var task: Task<Void, Never>?

    private(set) var sessionGeneration: UInt64 = 0
    private(set) var tickCount = 0
    private(set) var startCount = 0
    private(set) var cancellationCount = 0
    private(set) var peakConcurrentCount = 0
    private var concurrentCount = 0
    private var lastTickAt: Date?

    var isRunning: Bool { task != nil }

    var diagnostics: PersistentHeartbeatDiagnostics {
        PersistentHeartbeatDiagnostics(
            isRunning: isRunning,
            sessionGeneration: sessionGeneration,
            tickCount: tickCount,
            lastTickAge: lastTickAt.map { Date().timeIntervalSince($0) },
            startCount: startCount,
            cancellationCount: cancellationCount,
            concurrentCount: concurrentCount,
            peakConcurrentCount: peakConcurrentCount)
    }

    /// Begin driving `controller` for `generation`.
    ///
    /// Cancels anything already running first, so calling it twice for the same session — or for a
    /// replacement — can never leave two loops ticking one controller.
    /// Run after every tick, on the main actor. This is where the session's observable presentation
    /// state is refreshed — SwiftUI only re-renders because a stored property it read has changed,
    /// and the gapless session is not itself observable.
    private var afterTick: (@MainActor () -> Void)?

    func start(controller: GaplessPlaybackController, generation: UInt64,
               afterTick: (@MainActor () -> Void)? = nil) {
        cancel()
        self.controller = controller
        self.afterTick = afterTick
        sessionGeneration = generation
        startCount += 1
        task = Task { [weak self] in
            // Sequential by construction: the next tick cannot begin until the previous one has
            // returned and the interval has elapsed, so `tick()` never overlaps itself.
            while !Task.isCancelled {
                guard let self, self.sessionGeneration == generation,
                      let controller = self.controller else { return }
                self.concurrentCount += 1
                self.peakConcurrentCount = max(self.peakConcurrentCount, self.concurrentCount)
                await controller.tick()
                self.concurrentCount -= 1
                // A cancel that landed while that tick was in flight makes it the last one. It is
                // deliberately not counted: a tick recorded after cancellation would show up in
                // diagnostics as a heartbeat still running, which is the exact condition these
                // counters exist to catch.
                guard self.sessionGeneration == generation else { return }
                self.tickCount += 1
                self.lastTickAt = Date()
                self.afterTick?()
                // Suspends rather than blocks, and throws on cancellation — the loop condition
                // above is what acts on that.
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// Stop driving, and release the controller.
    ///
    /// Bumping the generation is what makes this immediate in effect: a loop that is mid-tick or
    /// mid-sleep when this returns will fail its guard on the next iteration and do no further
    /// work, whatever the task's own cancellation state has got round to.
    func cancel() {
        guard task != nil else { return }
        task?.cancel()
        task = nil
        controller = nil
        sessionGeneration &+= 1
        cancellationCount += 1
    }

    #if DEBUG
    /// Run exactly one tick synchronously, for a test that needs a deterministic beat rather than a
    /// wall-clock one. Never used in production — the loop above is the production driver.
    func tickOnceForTesting() async {
        await controller?.tick()
        tickCount += 1
        lastTickAt = Date()
    }
    #endif
}
