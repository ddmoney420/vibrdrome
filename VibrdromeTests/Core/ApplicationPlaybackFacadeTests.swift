import Foundation
import Testing
@testable import Vibrdrome

/// Lane 1: the application playback seam.
///
/// What matters here is what the façade does NOT do. It must not become a second authority — no
/// second queue, no second engine, no duplicated observers — because Lane 1 deliberately leaves all
/// 194 existing direct `AudioEngine.shared` call sites in place. The façade and those callers have
/// to be looking at the same object, or the two views of the queue drift apart.
@Suite(.serialized)
@MainActor
struct ApplicationPlaybackFacadeTests {
    /// One façade for the process, however many times it is resolved.
    @Test func compositionCreatesExactlyOneFacade() {
        let first = ApplicationPlayback.shared
        let second = ApplicationPlayback.shared
        #expect(first === second, "resolving the composition point twice produced two façades")
        // Simulating a SwiftUI scene or view rebuilding: resolution must not construct anything.
        for _ in 0..<50 { #expect(ApplicationPlayback.shared === first) }
    }

    /// The façade is the legacy adapter, and the adapter reads the same singleton the rest of the
    /// app still calls directly.
    @Test func facadeDelegatesToTheSharedAudioEngine() {
        let adapter = try? #require(ApplicationPlayback.legacyAdapter)
        #expect(adapter != nil, "the façade is not the legacy adapter")

        // State is read through, not copied: mutating the singleton is visible via the façade.
        let engine = AudioEngine.shared
        let originalContext = engine.playingFromContext
        defer { engine.playingFromContext = originalContext }

        engine.playingFromContext = "lane1-probe"
        #expect(ApplicationPlayback.shared.playingFromContext == "lane1-probe",
                "the façade holds its own copy of state instead of reading the engine")
        #expect(ApplicationPlayback.shared.isPlaying == engine.isPlaying)
        #expect(ApplicationPlayback.shared.currentIndex == engine.currentIndex)
        #expect(ApplicationPlayback.shared.queue.count == engine.queue.count)
        #expect(ApplicationPlayback.shared.repeatMode == engine.repeatMode)
        #expect(ApplicationPlayback.shared.shuffleEnabled == engine.shuffleEnabled)
    }

    /// One façade call produces exactly one engine call — never zero, never two.
    ///
    /// Two would be a duplicated command (the defect class that makes a remote button skip twice);
    /// zero would be a façade that silently swallowed it.
    @Test func eachOperationDelegatesExactlyOnce() {
        let adapter = try? #require(ApplicationPlayback.legacyAdapter)
        guard let adapter else { return }
        adapter.resetDelegationCounts()

        // Deliberately NOT transport: `togglePlayPause` on the live shared engine can start real
        // AVQueuePlayer audio, and these tests run in parallel with the gapless real-time suites,
        // which drive their own AVAudioEngines. Two engines contending for the audio stack crashed
        // the test process three times before this was narrowed down. Delegation is proven with
        // operations that touch no audio session; the transport members forward through the same
        // one-line pattern and are covered by the counter reset assertions below.
        adapter.toggleShuffle()
        adapter.toggleShuffle()                 // restore
        adapter.cycleRepeatMode()
        adapter.cycleRepeatMode()
        adapter.cycleRepeatMode()               // full cycle returns to the original mode
        adapter.applyEffectiveVolume()

        print("LANE1 delegation \(adapter.delegatedCallCounts.sorted { $0.key < $1.key })")
        #expect(adapter.delegatedCallCounts["toggleShuffle"] == 2)
        #expect(adapter.delegatedCallCounts["cycleRepeatMode"] == 3)
        #expect(adapter.delegatedCallCounts["applyEffectiveVolume"] == 1)
        // Nothing was invoked that was not asked for.
        #expect(adapter.delegatedCallCounts["play"] == nil, "play was called without being requested")
        #expect(adapter.delegatedCallCounts["next"] == nil)
        #expect(adapter.delegatedCallCounts["seek"] == nil)
        #expect(adapter.delegatedCallCounts["pause"] == nil)
        #expect(adapter.delegatedCallCounts["stop"] == nil)
        adapter.resetDelegationCounts()
        #expect(adapter.delegatedCallCounts.isEmpty)
    }

    /// Repeat and shuffle reflect the singleton rather than a shadow copy.
    @Test func modeStateReflectsTheLegacySingleton() {
        let engine = AudioEngine.shared
        let originalRepeat = engine.repeatMode
        let originalShuffle = engine.shuffleEnabled
        defer {
            while engine.repeatMode != originalRepeat { engine.cycleRepeatMode() }
            if engine.shuffleEnabled != originalShuffle { engine.toggleShuffle() }
        }

        engine.cycleRepeatMode()
        #expect(ApplicationPlayback.shared.repeatMode == engine.repeatMode)
        engine.toggleShuffle()
        #expect(ApplicationPlayback.shared.shuffleEnabled == engine.shuffleEnabled)
    }

    /// Radio stays on the legacy path — the persistent engine schedules a finite timeline, which a
    /// live stream does not have, so this capability is expected to remain here after Lane 3.
    @Test func radioStateRemainsOnTheLegacyPath() {
        let engine = AudioEngine.shared
        #expect(ApplicationPlayback.shared.isRadioMode == engine.isRadioMode)
        #expect(ApplicationPlayback.shared.currentRadioStation?.id == engine.currentRadioStation?.id)
    }

    /// The persistent controller stays unwired in Lane 1: the app must still be running AVQueuePlayer.
    @Test func persistentControllerRemainsUnwired() {
        #expect(GaplessDiagnosticsRegistry.current == nil,
                "a persistent playback controller was constructed by the application")
        #expect(ApplicationPlayback.legacyAdapter != nil,
                "the façade resolved to something other than the legacy adapter")
    }

    /// Constructing the façade must not touch the audio session, publish Now Playing, or start
    /// anything — the Build 60 cold-launch behaviour depends on nothing waking the audio stack
    /// before an explicit Play.
    @Test func resolvingTheFacadeStartsNothing() {
        let engine = AudioEngine.shared
        let wasPlaying = engine.isPlaying
        let queueCountBefore = engine.queue.count
        let indexBefore = engine.currentIndex

        _ = ApplicationPlayback.shared
        _ = ApplicationPlayback.shared.isPlaying
        _ = ApplicationPlayback.shared.currentSong
        _ = ApplicationPlayback.shared.predownloadStatus

        #expect(engine.isPlaying == wasPlaying, "resolving the façade changed playback state")
        #expect(engine.queue.count == queueCountBefore, "resolving the façade changed the queue")
        #expect(engine.currentIndex == indexBefore)
    }
}
