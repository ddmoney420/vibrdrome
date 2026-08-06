import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Lane 3C: the persistent stack becomes constructible from production, and stays unselected.
///
/// **The claim under test is "inert".** Construction attaches and connects the fixed 44.1 kHz
/// stereo graph, and that is all: the engine is not started, the session is not activated, no source
/// file is opened, no converter exists, no buffer is scheduled, and the buffer pool is not even
/// allocated — the scheduler that owns it is a `lazy var` on the backend, documented there as "built
/// lazily so a backend that is never started allocates no pool".
///
/// **Routing does not move.** `selectedBackend` stays `.legacy` before, during and after
/// preparation, and every application operation still reaches the legacy adapter.
@Suite(.serialized)
@MainActor
struct PersistentPlaybackAssemblyTests {

    /// A router with its own legacy adapter and builder, so these tests never disturb the shared
    /// composition point that the rest of the suite asserts on.
    private func makeRouter(
        builder: any PersistentPlaybackAssemblyBuilding = ProductionPersistentPlaybackAssemblyBuilder()
    ) -> ApplicationPlaybackRouter {
        ApplicationPlaybackRouter(legacy: LegacyAudioEngineAdapter(), persistentBuilder: builder)
    }

    /// Refuses to build, so failure isolation can be tested without a device-only substitute.
    private struct FailingBuilder: PersistentPlaybackAssemblyBuilding {
        let failure: PersistentPreparationFailure
        func build() throws -> PersistentPlaybackAssembly { throw failure }
    }

    /// Counts build attempts, to prove one construction per successful preparation.
    private final class CountingBuilder: PersistentPlaybackAssemblyBuilding {
        private(set) var buildCount = 0
        let inner = ProductionPersistentPlaybackAssemblyBuilder()
        func build() throws -> PersistentPlaybackAssembly {
            buildCount += 1
            return try inner.build()
        }
    }

    // MARK: - Lazy construction

    /// Cold launch: the router exists, legacy is authoritative, persistent is not constructed.
    @Test func routerConstructionDoesNotBuildPersistent() {
        let router = makeRouter()
        #expect(router.persistentPreparationState == .notConstructed)
        #expect(router.persistentAssembly == nil, "the router built persistent at init")
        #expect(router.selectedBackend == .legacy)

        // Reading diagnostics and evaluating the Lane 3B policy must not construct either.
        _ = router.diagnostics
        _ = router.persistentPreparationState
        _ = PlaybackBackendPolicy.decision(for: PlaybackRoutingSource(
            contentKind: .finiteTrack, delivery: .localOriginal, codec: .flac,
            channelCount: 2, hasFiniteDuration: true, gaplessMetadata: .notRequired))
        #expect(router.persistentAssembly == nil,
                "reading diagnostics or evaluating the policy constructed persistent")
        #expect(router.persistentPreparationState == .notConstructed)
    }

    /// The shared production router — the one every seam resolves — is still unprepared.
    @Test func theSharedRouterIsNotPreparedByAnythingInTheApp() {
        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        #expect(router.persistentPreparationState == .notConstructed,
                "something in the app prepared the persistent stack")
        #expect(router.persistentAssembly == nil)
        #expect(router.selectedBackend == .legacy)
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "a persistent controller exists without explicit preparation")
    }

    /// Explicit preparation builds exactly one assembly, and repeats return the same one.
    @Test func explicitPreparationConstructsOnceAndIsIdempotent() throws {
        let builder = CountingBuilder()
        let router = makeRouter(builder: builder)

        let first = try router.preparePersistentBackend()
        #expect(router.persistentPreparationState == .ready)
        #expect(builder.buildCount == 1)

        for _ in 0..<50 {
            let again = try router.preparePersistentBackend()
            #expect(again === first, "preparation produced a second assembly")
        }
        #expect(builder.buildCount == 1,
                "50 preparations produced \(builder.buildCount) constructions")
        #expect(router.persistentAssembly === first)
        #expect(router.selectedBackend == .legacy, "preparation changed the routing decision")
    }

    // MARK: - Inert state

    /// After construction: graph assembled, nothing running, nothing allocated, nothing open.
    @Test func theConstructedAssemblyIsInert() throws {
        let router = makeRouter()
        let categoryBefore = AVAudioSession.sharedInstance().category
        let modeBefore = AVAudioSession.sharedInstance().mode
        let engineBefore = AudioEngine.shared.isPlaying
        let registrationsBefore = RemoteCommandManager.shared.registrationCount

        let assembly = try router.preparePersistentBackend()
        let inert = assembly.diagnostics

        #expect(inert.engineRunning == false, "construction started the persistent engine")
        #expect(inert.playerNodePlaying == false, "construction started the player node")
        #expect(inert.bufferPoolAllocated == false,
                "construction allocated the buffer pool; the scheduler should still be lazy")
        #expect(inert.liveSourceFiles == 0, "construction opened a source file")
        #expect(inert.liveConverters == 0, "construction created a converter")
        #expect(inert.scheduledBuffers == 0, "construction scheduled a buffer")
        #expect(inert.graphFormat == "44100 Hz / 2 ch / Float32",
                "the graph format changed: \(inert.graphFormat)")

        // The engine itself agrees.
        #expect(assembly.backend.engine.engine.isRunning == false)
        #expect(assembly.backend.engine.player.isPlaying == false)
        #expect(assembly.backend.engine.renderFormat.sampleRate == 44_100)
        #expect(assembly.backend.engine.renderFormat.channelCount == 2)

        // Nothing outside the assembly moved.
        #expect(AVAudioSession.sharedInstance().category == categoryBefore,
                "construction changed the audio session category")
        #expect(AVAudioSession.sharedInstance().mode == modeBefore,
                "construction changed the audio session mode")
        #expect(AudioEngine.shared.isPlaying == engineBefore, "construction started legacy playback")
        #expect(RemoteCommandManager.shared.registrationCount == registrationsBefore,
                "construction registered remote commands")
    }

    /// The session is built empty — construction must not adopt or evaluate the current queue.
    @Test func constructionDoesNotTouchTheQueue() throws {
        let engine = AudioEngine.shared
        let queueBefore = engine.queue.map(\.id)
        let indexBefore = engine.currentIndex

        let router = makeRouter()
        let assembly = try router.preparePersistentBackend()

        #expect(assembly.session.queue.items.isEmpty,
                "construction adopted a queue")
        #expect(engine.queue.map(\.id) == queueBefore, "construction changed the legacy queue")
        #expect(engine.currentIndex == indexBefore)
    }

    // MARK: - Legacy isolation after preparation

    /// Every representative operation still reaches the legacy adapter, exactly once, after the
    /// persistent stack exists.
    @Test func legacyStillRoutesEverythingAfterPreparation() throws {
        let adapter = LegacyAudioEngineAdapter()
        let router = ApplicationPlaybackRouter(
            legacy: adapter, persistentBuilder: ProductionPersistentPlaybackAssemblyBuilder())
        let assembly = try router.preparePersistentBackend()
        #expect(router.selectedBackend == .legacy)

        let engine = AudioEngine.shared
        let shuffleBefore = engine.shuffleEnabled
        let repeatBefore = engine.repeatMode
        let eqBefore = engine.eqEnabled
        defer {
            if engine.shuffleEnabled != shuffleBefore { engine.toggleShuffle() }
            while engine.repeatMode != repeatBefore { engine.cycleRepeatMode() }
            engine.applyEQToggle(enabled: eqBefore)
        }
        adapter.resetDelegationCounts()

        let playback: any ApplicationPlaybackControlling = router
        playback.seek(to: 12_345)
        playback.skipToIndex(Int.max)
        playback.removeFromQueue(atAbsolute: Int.max)
        playback.moveInUpNext(from: IndexSet(), to: 0)
        playback.updateQueueSongStarred(id: "3c-absent", starred: true)
        playback.toggleShuffle()
        playback.cycleRepeatMode()
        playback.applyEQToggle(enabled: !eqBefore)
        playback.applyEffectiveVolume()
        playback.saveQueueLocally()
        playback.stopRadioMode()

        let counts = adapter.delegatedCallCounts
        for member in ["seek", "skipToIndex", "removeFromQueue", "moveInUpNext",
                       "updateQueueSongStarred", "toggleShuffle", "cycleRepeatMode",
                       "applyEQToggle", "applyEffectiveVolume", "saveQueueLocally",
                       "stopRadioMode"] {
            #expect(counts[member] == 1,
                    "\(member) produced \(counts[member] ?? 0) legacy calls after preparation")
        }

        // The persistent controller received nothing at all.
        #expect(assembly.backend.engine.player.isPlaying == false,
                "an operation reached the persistent player node")
        #expect(assembly.backend.state == .idle,
                "an operation moved the persistent backend out of idle: \(assembly.backend.state)")
        #expect(router.selectedBackend == .legacy)
    }

    /// Diagnostics tell the truth after preparation: constructed, ready, still not selected.
    @Test func diagnosticsReportConstructedButUnselected() throws {
        let router = makeRouter()
        let before = router.diagnostics
        #expect(before.preparationDescription == "Not constructed")
        #expect(before.summary.contains("Playback authority: none"))

        try router.preparePersistentBackend()
        let after = router.diagnostics

        #expect(after.preparationDescription == "Ready")
        #expect(after.selectedBackend == .legacy)
        #expect(after.summary.contains("Persistent preparation: Ready"))
        #expect(after.summary.contains("Active transport backend: Legacy"))
        // Constructed is not selected: preparation builds the stack, authority is what routes to it.
        #expect(after.summary.contains("Playback authority: none"))
        #expect(after.summary.contains("Active transport backend: Persistent") == false,
                "diagnostics claimed the persistent engine is selected")
    }

    // MARK: - Failure isolation

    /// A construction failure leaves legacy fully operational and retains no partial assembly.
    @Test func constructionFailureLeavesLegacyOperational() {
        for failure in PersistentPreparationFailure.allCases {
            let adapter = LegacyAudioEngineAdapter()
            let router = ApplicationPlaybackRouter(
                legacy: adapter, persistentBuilder: FailingBuilder(failure: failure))

            #expect(throws: PersistentPreparationFailure.self) {
                try router.preparePersistentBackend()
            }

            #expect(router.persistentPreparationState == .failed(failure),
                    "failure state was \(router.persistentPreparationState)")
            #expect(router.persistentAssembly == nil, "a partial assembly was retained")
            #expect(router.selectedBackend == .legacy, "failure changed the routing decision")

            // Legacy still works.
            adapter.resetDelegationCounts()
            (router as any ApplicationPlaybackControlling).applyEffectiveVolume()
            #expect(adapter.delegatedCallCounts["applyEffectiveVolume"] == 1,
                    "legacy stopped working after a persistent construction failure")

            // Repeated attempts keep failing deterministically — no retry storm, no accumulation.
            for _ in 0..<10 {
                #expect(throws: PersistentPreparationFailure.self) {
                    try router.preparePersistentBackend()
                }
            }
            #expect(router.persistentPreparationState == .failed(failure))
            #expect(router.persistentAssembly == nil)
        }
    }

    /// A failure reason must never carry a credential, URL, path or token.
    @Test func failureReasonsCarryNoSensitiveDetail() {
        for failure in PersistentPreparationFailure.allCases {
            let raw = failure.rawValue
            #expect(raw.contains("/") == false, "\(raw) looks like a path")
            #expect(raw.lowercased().contains("http") == false)
            #expect(raw.lowercased().contains("token") == false)
            #expect(raw.lowercased().contains("password") == false)
            #expect(raw.isEmpty == false)
        }
    }

    // MARK: - Cost and stability

    /// One construction produces one of everything, and repeated preparation grows nothing.
    ///
    /// Reports the measured construction cost rather than gating on an invented threshold —
    /// unbounded growth, duplicate construction, session activation or active playback are the
    /// failures; a particular megabyte figure is not.
    @Test func constructionCostIsBoundedAndSingular() throws {
        let builder = CountingBuilder()
        let router = makeRouter(builder: builder)

        let fdBefore = Self.openFileDescriptorCount()
        let memoryBefore = Self.residentMemoryBytes()
        let start = ProcessInfo.processInfo.systemUptime

        let assembly = try router.preparePersistentBackend()

        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let memoryAfter = Self.residentMemoryBytes()
        let fdAfter = Self.openFileDescriptorCount()

        // Repeated preparation must allocate nothing further.
        for _ in 0..<25 { _ = try router.preparePersistentBackend() }
        let fdSettled = Self.openFileDescriptorCount()
        let memorySettled = Self.residentMemoryBytes()

        #expect(builder.buildCount == 1, "repeated preparation constructed again")
        #expect(router.persistentAssembly === assembly)
        #expect(assembly.diagnostics.bufferPoolAllocated == false)
        #expect(fdSettled <= fdAfter,
                "file descriptors grew from \(fdAfter) to \(fdSettled) across repeated preparation")

        let deltaKB = (memoryAfter &- memoryBefore) / 1024
        let settledDeltaKB = (memorySettled &- memoryBefore) / 1024
        print("""
            LANE3C construction cost: \(String(format: "%.1f", elapsed * 1000)) ms, \
            memory delta \(deltaKB) KB, settled delta \(settledDeltaKB) KB, \
            fd \(fdBefore) -> \(fdAfter) -> \(fdSettled), \
            assemblies \(builder.buildCount)
            """)
    }

    /// Resolving the shared router repeatedly, and rebuilding views, constructs nothing.
    @Test func stableIdentityAndNoConstructionFromReconstruction() {
        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        for _ in 0..<50 {
            #expect(ApplicationPlayback.shared === router)
            _ = ContentView()
            _ = router.diagnostics
        }
        #expect(router.persistentAssembly == nil,
                "resolving the router or rebuilding views constructed the persistent stack")
        #expect(router.persistentPreparationState == .notConstructed)
        #expect(router.selectedBackend == .legacy)
    }

    // MARK: - Measurement helpers

    private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    private static func openFileDescriptorCount() -> Int {
        var count = 0
        let limit = min(Int(getdtablesize()), 4096)
        for fd in 0..<limit where fcntl(Int32(fd), F_GETFD) != -1 { count += 1 }
        return count
    }
}
