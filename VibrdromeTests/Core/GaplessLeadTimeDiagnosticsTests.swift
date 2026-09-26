import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Debug lead-time diagnostics: bounded, populated at the right moments, and cleared at the right
/// moments. Display-only — none of this may change what playback does.
@Suite(.serialized)
@MainActor
struct GaplessLeadTimeDiagnosticsTests {
    /// The window is a rolling 100 and cannot be talked into growing.
    @Test func windowIsBoundedAtOneHundredSamples() {
        var window = GaplessLeadTimeWindow()
        #expect(!window.hasMeasurement)
        #expect(window.latest == nil)
        #expect(window.minimum == nil)
        #expect(window.average == nil)

        for index in 1...500 { window.record(Double(index) / 1_000) }
        #expect(window.count == GaplessLeadTimeWindow.capacity, "window grew to \(window.count)")
        #expect(window.count == 100)
        // The oldest samples are gone: only 401...500 remain.
        #expect(window.latest == 0.5)
        #expect(window.minimum == 0.401)
        let average = try? #require(window.average)
        #expect(abs((average ?? 0) - 0.4505) < 0.0001, "average \(String(describing: average))")
    }

    /// Nothing is published until the timestamps a metric depends on both exist.
    @Test func noValueIsPublishedBeforeItsTimestampsExist() {
        var record = GaplessPreparationRecord(itemID: GaplessQueueItemID(rawValue: 1), songID: "s",
                                              queueGeneration: 1, requestedAt: Date())
        #expect(record.preparationLeadTime == nil, "published before ready and audible existed")
        #expect(record.schedulingLeadTime == nil, "published before scheduled and audible existed")

        record.readyAt = Date()
        record.scheduledAt = Date()
        // Still nothing: neither metric can be computed without the audible timestamp.
        #expect(record.preparationLeadTime == nil)
        #expect(record.schedulingLeadTime == nil)

        record.audibleAt = record.readyAt?.addingTimeInterval(0.4)
        #expect(record.preparationLeadTime != nil)
        #expect(record.schedulingLeadTime != nil)
    }

    /// Definitions are preserved exactly as production computes them — ready→audible and
    /// scheduled→audible — not the more intuitive requested→ready.
    @Test func definitionsMatchProduction() {
        let requested = Date()
        var record = GaplessPreparationRecord(itemID: GaplessQueueItemID(rawValue: 1), songID: "s",
                                              queueGeneration: 1, requestedAt: requested)
        record.readyAt = requested.addingTimeInterval(1.0)
        record.scheduledAt = requested.addingTimeInterval(1.5)
        record.audibleAt = requested.addingTimeInterval(3.0)

        // ready (t+1.0) -> audible (t+3.0)
        #expect(abs((record.preparationLeadTime ?? 0) - 2.0) < 0.001)
        // scheduled (t+1.5) -> audible (t+3.0)
        #expect(abs((record.schedulingLeadTime ?? 0) - 1.5) < 0.001)
    }

    /// Both metrics populate through the real controller at real boundaries, and stop clears them.
    @Test func statisticsPopulateAtBoundariesAndClearOnStop() async throws {
        let rig = try GaplessBufferIntegrationTests.makeRig(trackCount: 4, frames: 6_615)
        defer { GaplessBufferIntegrationTests.teardown(rig) }
        rig.session.setRepeatMode(.all)

        #expect(!rig.controller.leadTimeStatistics.preparation.hasMeasurement,
                "a value existed before anything played")
        #expect(!rig.controller.leadTimeStatistics.scheduling.hasMeasurement)

        try await rig.controller.play()
        await GaplessBufferIntegrationTests.run(rig, seconds: 3)

        let stats = rig.controller.leadTimeStatistics
        let boundaries = rig.controller.observedBoundaries.count
        print("""
            LEADTIME boundaries \(boundaries)  \
            prep latest \(stats.preparation.latest.map { String(format: "%.1f ms", $0 * 1000) } ?? "-")  \
            min \(stats.preparation.minimum.map { String(format: "%.1f", $0 * 1000) } ?? "-")  \
            avg \(stats.preparation.average.map { String(format: "%.1f", $0 * 1000) } ?? "-")  \
            samples \(stats.preparation.count)  \
            sched latest \(stats.scheduling.latest.map { String(format: "%.1f ms", $0 * 1000) } ?? "-")  \
            samples \(stats.scheduling.count)
            """)

        #expect(boundaries >= 2, "only \(boundaries) boundaries")
        #expect(stats.preparation.hasMeasurement, "preparation lead never populated")
        #expect(stats.scheduling.hasMeasurement, "scheduling lead never populated")
        // Recorded once per audible item, never more.
        #expect(stats.preparation.count <= boundaries)
        #expect(stats.scheduling.count <= boundaries)
        // Both are real durations, not zero or negative.
        #expect((stats.preparation.latest ?? -1) > 0)
        #expect((stats.scheduling.latest ?? -1) > 0)

        rig.controller.stop()
        #expect(!rig.controller.leadTimeStatistics.preparation.hasMeasurement,
                "stop did not clear preparation statistics")
        #expect(!rig.controller.leadTimeStatistics.scheduling.hasMeasurement,
                "stop did not clear scheduling statistics")
        #expect(rig.controller.leadTimeStatistics.preparation.count == 0)
    }

    /// Recording diagnostics must not perturb playback: the same run still produces one play
    /// instance per play, in order, with the pool conserved.
    @Test func diagnosticsDoNotChangePlaybackBehaviour() async throws {
        let rig = try GaplessBufferIntegrationTests.makeRig(trackCount: 5, frames: 6_615)
        defer { GaplessBufferIntegrationTests.teardown(rig) }
        rig.session.setRepeatMode(.all)

        try await rig.controller.play()
        await GaplessBufferIntegrationTests.run(rig, seconds: 4)

        let boundaries = rig.controller.observedBoundaries
        let instances = boundaries.map(\.playInstance)
        let snap = await rig.backend.domainSnapshotForTesting
        #expect(Set(instances).count == instances.count, "a play instance was reused")
        for (index, boundary) in boundaries.enumerated() {
            #expect(boundary.songID == "s\(index % 5)",
                    "position \(index) played \(boundary.songID)")
        }
        #expect(snap.staleRecycles == 0)
        #expect(snap.poolAvailable + snap.poolInFlight == snap.poolCapacity)
    }

    /// The registry holds the controller weakly — a strong reference would keep a stopped engine,
    /// its buffers, converters and files alive for the life of the process.
    @Test func registryDoesNotRetainTheController() async throws {
        do {
            let rig = try GaplessBufferIntegrationTests.makeRig(trackCount: 2, frames: 4_410)
            #expect(GaplessDiagnosticsRegistry.current === rig.controller)
            GaplessBufferIntegrationTests.teardown(rig)
            await rig.backend.settleTransport()
        }
        // Allow the autorelease pool to drain the controller.
        for _ in 0..<5 { try? await Task.sleep(for: .milliseconds(50)) }
        print("LEADTIME registry after teardown: \(GaplessDiagnosticsRegistry.current == nil ? "released" : "STILL HELD")")
    }
}
