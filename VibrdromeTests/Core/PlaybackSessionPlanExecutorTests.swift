import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Lane 3D-B1b Core: executing a finalized plan starts **exactly one** backend.
///
/// **What these tests are really pinning is an order.** Ownership is granted before the selected
/// backend can become audible; legacy is proven released — by its items, never by its playing flag
/// — before persistent is granted anything; persistent authority is revoked before legacy is
/// rebuilt, so the owner count never transiently reads two; and fallback is legal only while
/// nothing has been heard.
///
/// The executor is invoked here and nowhere else. `ApplicationPlaybackRouter` still routes every
/// application call to legacy, which the last test in this file re-checks.
@Suite(.serialized)
@MainActor
struct PlaybackSessionPlanExecutorTests {

    private static let sampleRate = GaplessBufferFixtures.sampleRate
    private static let partFrames = 8_192

    // MARK: - Fixtures

    private func makeSong(id: String) -> Song {
        Song(id: id, parent: nil, title: "Track \(id)",
             album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
             track: nil, year: nil, genre: nil, coverArt: nil,
             size: nil, contentType: nil, suffix: nil,
             duration: 180, bitRate: nil, path: nil,
             discNumber: nil, created: nil, starred: nil, userRating: nil,
             bpm: nil, replayGain: nil, musicBrainzId: nil)
    }

    private func request(_ songs: [Song], startIndex: Int = 0,
                         startOffsetSeconds: TimeInterval = 0,
                         generation: UInt64 = 1) -> PlaybackSessionSelectionRequest {
        PlaybackSessionSelectionRequest(songs: songs, startIndex: startIndex,
                                        startOffsetSeconds: startOffsetSeconds,
                                        generation: generation)
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("exec-\(UInt64.random(in: 0..<UInt64.max))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    /// Real tone files, so a persistent start is a genuine render rather than a stub.
    private func makeParts(_ ids: [String], in directory: URL) throws -> [String: URL] {
        var files: [String: URL] = [:]
        for (index, id) in ids.enumerated() {
            let url = directory.appendingPathComponent("\(id).wav")
            try GaplessBufferFixtures.writeStereoWav(
                url: url, frequency: 440 + Double(index) * 110,
                frames: Self.partFrames, sampleRate: Self.sampleRate)
            files[id] = url
        }
        return files
    }

    private func makeAssembly(provider: any GaplessFileProviding,
                              directory: URL) -> PersistentPlaybackAssembly {
        PersistentPlaybackAssembly(
            session: GaplessPlaybackSession(sampleRate: Self.sampleRate),
            backend: GaplessRealTimeBackend(),
            preparer: GaplessTrackPreparer(provider: provider, renderSampleRate: Self.sampleRate),
            cacheDirectory: directory)
    }

    /// A real, finalized persistent plan produced by the real planner over the given assembly.
    private func persistentPlan(for song: Song,
                                assembly: PersistentPlaybackAssembly) async throws
        -> (PlaybackSessionSelectionPlan, PreparedPersistentSource) {
        let planner = PlaybackSessionSelectionPlanner(
            prepareAssembly: { assembly }, isPersistentRoutingEnabled: { true })
        let plan = await planner.plan(request: request([song]))
        guard case .persistent(let source, _) = plan else {
            throw PlanFixtureFailure.notPersistent(plan.describedForDiagnostics)
        }
        return (plan, source)
    }

    private enum PlanFixtureFailure: Error { case notPersistent(String) }

    private func makeExecutor(legacy: LegacyPortSpy, persistent: PersistentPortSpy)
        -> PlaybackSessionPlanExecutor {
        let executor = PlaybackSessionPlanExecutor(legacy: legacy, persistent: persistent)
        legacy.ownership = executor.ownership
        persistent.ownership = executor.ownership
        return executor
    }

    /// Drive real ticks until `predicate` holds or the deadline passes.
    private func drive(_ controller: GaplessPlaybackController, seconds: Double,
                       until predicate: () -> Bool = { false }) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            await controller.tick()
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(4))
        }
    }

    // MARK: - Legacy plans

    /// A legacy plan grants legacy, adopts once and starts once — and quiesces nothing.
    @Test func aLegacyPlanAdoptsOnceAndStartsOnce() async {
        let legacy = LegacyPortSpy()
        let persistent = PersistentPortSpy()
        let executor = makeExecutor(legacy: legacy, persistent: persistent)
        let songs = [makeSong(id: "a"), makeSong(id: "b")]

        let outcome = await executor.execute(
            plan: .legacy(reason: .supportedLocalSource),
            request: request(songs, startIndex: 1), currentGeneration: 1)

        #expect(outcome == .started(.legacy))
        #expect(executor.stepCounts["startLegacy"] == 1,
                "legacy was started \(executor.stepCounts["startLegacy"] ?? 0) times, expected 1")
        #expect(executor.stepCounts["adoptLegacy"] == 1)
        #expect(executor.stepCounts["grantLegacy"] == 1)
        #expect(executor.ownership.authority == .legacy)
        #expect(executor.ownership.ownerCount == 1)
        // The session it started is the one that was requested, positionally.
        #expect(legacy.startedSnapshots.count == 1)
        #expect(legacy.startedSnapshots.first?.songs.map(\.id) == ["a", "b"])
        #expect(legacy.startedSnapshots.first?.currentIndex == 1)
    }

    /// A legacy plan must never quiesce legacy, and must never touch persistent at all.
    @Test func aLegacyPlanNeitherQuiescesNorTouchesPersistent() async {
        let legacy = LegacyPortSpy()
        let persistent = PersistentPortSpy()
        let executor = makeExecutor(legacy: legacy, persistent: persistent)

        _ = await executor.execute(plan: .legacy(reason: .supportedLocalSource),
                                   request: request([makeSong(id: "a")]), currentGeneration: 1)

        #expect(legacy.calls.contains("quiesce") == false,
                "a legacy plan tore down the very transport it was about to start")
        #expect(executor.stepCounts["quiesce"] == nil)
        #expect(persistent.calls.isEmpty,
                "a legacy plan touched persistent: \(persistent.calls)")
        #expect(executor.preservedSnapshot == nil,
                "a legacy plan preserved a handoff snapshot, implying a handoff that never happened")
    }

    /// A failed selection is legacy-owned: the plan's own `plannedBackend` says so, and refusing to
    /// start would leave a Play press doing nothing.
    @Test func aFailedPlanIsExecutedAsLegacy() async {
        let legacy = LegacyPortSpy()
        let persistent = PersistentPortSpy()
        let executor = makeExecutor(legacy: legacy, persistent: persistent)

        let outcome = await executor.execute(plan: .failed(reason: .sourcePreparationFailed),
                                             request: request([makeSong(id: "a")]),
                                             currentGeneration: 1)

        #expect(outcome == .started(.legacy))
        #expect(executor.stepCounts["startLegacy"] == 1)
        #expect(persistent.calls.isEmpty)
    }

    /// A plan naming no playable occurrence starts nothing and claims nothing.
    @Test func anEmptySessionIsRefusedAndStartsNothing() async {
        let legacy = LegacyPortSpy()
        let persistent = PersistentPortSpy()
        let executor = makeExecutor(legacy: legacy, persistent: persistent)

        let outcome = await executor.execute(plan: .legacy(reason: .supportedLocalSource),
                                             request: request([]), currentGeneration: 1)

        #expect(outcome == .refused(.emptySession))
        #expect(executor.stepCounts["startLegacy"] == nil, "an empty session started transport")
        #expect(executor.ownership.authority == .none,
                "an unexecutable plan was granted playback authority")
    }

    // MARK: - Generation

    /// A superseded plan starts nothing and tears nothing down.
    @Test func aSupersededLegacyPlanStartsNothing() async {
        let legacy = LegacyPortSpy()
        let persistent = PersistentPortSpy()
        let executor = makeExecutor(legacy: legacy, persistent: persistent)

        let outcome = await executor.execute(plan: .legacy(reason: .supportedLocalSource),
                                             request: request([makeSong(id: "a")], generation: 1),
                                             currentGeneration: 7)

        #expect(outcome == .superseded)
        #expect(legacy.calls.isEmpty, "a superseded plan drove legacy: \(legacy.calls)")
        #expect(persistent.calls.isEmpty)
        #expect(executor.ownership.authority == .none)
    }

    /// A superseded persistent plan releases its prepared source, so it can never be adopted after
    /// the queue has moved on.
    @Test func aSupersededPersistentPlanReleasesItsSource() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["s0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            let (plan, source) = try await persistentPlan(for: makeSong(id: "s0"),
                                                          assembly: assembly)
            let legacy = LegacyPortSpy()
            let persistent = PersistentPortSpy()
            let executor = makeExecutor(legacy: legacy, persistent: persistent)

            let outcome = await executor.execute(
                plan: plan, request: request([makeSong(id: "s0")], generation: 1),
                currentGeneration: 2)

            #expect(outcome == .superseded)
            #expect(source.consume() == nil, "a superseded plan was still adoptable")
            #expect(legacy.calls.contains("quiesce") == false,
                    "a superseded plan silenced legacy")
            #expect(executor.ownership.authority == .none)
        }
    }

    // MARK: - Persistent handoff, real engine

    /// The full sequence over a real assembly: capture, quiesce, verify, grant, adopt, observe,
    /// start — each exactly once.
    @Test func aPersistentPlanHandsOverInOrderAndStartsOnce() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            let song = makeSong(id: "p0")
            let (plan, source) = try await persistentPlan(for: song, assembly: assembly)

            let legacy = LegacyPortSpy()
            let port = PersistentAssemblySessionPort(assembly: assembly)
            let executor = PlaybackSessionPlanExecutor(legacy: legacy, persistent: port)
            legacy.ownership = executor.ownership

            let outcome = await executor.execute(plan: plan, request: request([song]),
                                                 currentGeneration: 1)

            #expect(outcome == .started(.persistent))
            #expect(executor.ownership.authority == .persistent)
            #expect(executor.ownership.ownerCount == 1)
            #expect(executor.stepCounts["quiesce"] == 1)
            #expect(executor.stepCounts["grantPersistent"] == 1)
            #expect(executor.stepCounts["startPersistent"] == 1,
                    "persistent was started more than once")
            #expect(executor.stepCounts["startLegacy"] == nil, "both backends were started")
            #expect(source.isConsumed, "the prepared source was not adopted")
            #expect(assembly.backend.engine.engine.isRunning,
                    "the persistent engine did not actually start")
            // Captured before teardown, and it is the queue authority during the handoff.
            let captureIndex = legacy.calls.firstIndex(of: "capture") ?? Int.max
            let quiesceIndex = legacy.calls.firstIndex(of: "quiesce") ?? -1
            #expect(captureIndex < quiesceIndex,
                    "the snapshot was captured after teardown destroyed it: \(legacy.calls)")
            #expect(executor.preservedSnapshot?.songs.map(\.id) == ["p0"])
        }
    }

    /// The delivered source selection already inspected is adopted, not fetched and described a
    /// second time — the track that was judged is the track that plays.
    @Test func theInspectedSourceIsAdoptedRatherThanPreparedAgain() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let provider = CountingFileProvider(filesByTrackID: files)
            let assembly = makeAssembly(provider: provider, directory: directory)
            defer { assembly.controller.stop() }
            let song = makeSong(id: "p0")
            let (plan, source) = try await persistentPlan(for: song, assembly: assembly)

            #expect(provider.count(for: "p0") == 1, "selection did not materialize the source once")
            let plannedTrack = source.track

            let legacy = LegacyPortSpy()
            let port = PersistentAssemblySessionPort(assembly: assembly)
            let executor = PlaybackSessionPlanExecutor(legacy: legacy, persistent: port)
            legacy.ownership = executor.ownership

            _ = await executor.execute(plan: plan, request: request([song]), currentGeneration: 1)

            #expect(provider.count(for: "p0") == 1,
                    "the executor re-fetched a delivered source: \(provider.count(for: "p0")) materializations")
            let adopted = await assembly.preparer.readyTrack("p0")
            #expect(adopted == plannedTrack,
                    "the engine scheduled a different reading of the file than the one judged")
        }
    }

    /// The latch closes on a **render-observed** first audible sample, not on the engine starting.
    @Test func theAudibleBoundaryLatchClosesOnlyOnRealAudio() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            let song = makeSong(id: "p0")
            let (plan, _) = try await persistentPlan(for: song, assembly: assembly)

            let legacy = LegacyPortSpy()
            let port = PersistentAssemblySessionPort(assembly: assembly)
            let executor = PlaybackSessionPlanExecutor(legacy: legacy, persistent: port)
            legacy.ownership = executor.ownership

            _ = await executor.execute(plan: plan, request: request([song]), currentGeneration: 1)

            // The engine is up and buffers are scheduled, but nothing has been heard yet, so a
            // fallback would still be legal.
            #expect(executor.ownership.audibleBoundaryReached == false,
                    "the latch closed on engine start rather than on rendered audio")
            #expect(executor.ownership.isFallbackPermitted)

            await drive(assembly.controller, seconds: 5) {
                executor.ownership.audibleBoundaryReached
            }

            #expect(executor.ownership.audibleBoundaryReached,
                    "persistent became audible but the latch never closed")
            #expect(executor.ownership.isFallbackPermitted == false,
                    "fallback stayed permitted after the listener had heard persistent")
            #expect(executor.ownership.authority == .persistent, "authority moved after the boundary")
        }
    }

    /// A plan is executable once. A second execution adopts nothing and starts nothing.
    @Test func aPlanCannotBeExecutedTwice() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            let song = makeSong(id: "p0")
            let (plan, _) = try await persistentPlan(for: song, assembly: assembly)

            let legacy = LegacyPortSpy()
            let persistent = PersistentPortSpy()
            let executor = makeExecutor(legacy: legacy, persistent: persistent)

            let first = await executor.execute(plan: plan, request: request([song]),
                                               currentGeneration: 1)
            let second = await executor.execute(plan: plan, request: request([song]),
                                                currentGeneration: 1)

            #expect(first == .started(.persistent))
            #expect(second == .refused(.representationUnconfirmed))
            #expect(executor.stepCounts["startPersistent"] == 1,
                    "the same plan started persistent twice")
            #expect(executor.stepCounts["quiesce"] == 1,
                    "a re-execution silenced legacy for a source it could not adopt")
        }
    }

    /// A mid-track legacy plan is refused too, and for the same reason: `AudioEngine.play` defers
    /// its item swap by 50 ms, so starting and then seeking would target the outgoing item.
    @Test func aMidTrackLegacyPlanIsRefusedAndStartsNothing() async {
        let legacy = LegacyPortSpy()
        let persistent = PersistentPortSpy()
        let executor = makeExecutor(legacy: legacy, persistent: persistent)

        let outcome = await executor.execute(
            plan: .legacy(reason: .supportedLocalSource),
            request: request([makeSong(id: "a")], startOffsetSeconds: 42), currentGeneration: 1)

        #expect(outcome == .refused(.midTrackResumeUnsupported))
        #expect(executor.stepCounts["startLegacy"] == nil,
                "a mid-track plan started legacy, which would play from the wrong position")
        #expect(executor.ownership.authority == .none)
        #expect(legacy.calls.isEmpty, "a refused plan drove legacy: \(legacy.calls)")
    }

    /// A persistent plan naming no playable occurrence is refused, and releases its source.
    @Test func anEmptyPersistentSessionIsRefusedAndReleasesItsSource() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            let (plan, source) = try await persistentPlan(for: makeSong(id: "p0"),
                                                          assembly: assembly)
            let legacy = LegacyPortSpy()
            let persistent = PersistentPortSpy()
            let executor = makeExecutor(legacy: legacy, persistent: persistent)

            let outcome = await executor.execute(plan: plan, request: request([]),
                                                 currentGeneration: 1)

            #expect(outcome == .refused(.emptySession))
            #expect(source.consume() == nil, "an unexecutable plan stayed adoptable")
            #expect(legacy.calls.contains("quiesce") == false,
                    "legacy was silenced for a session with nothing to play")
            #expect(persistent.calls.isEmpty)
            #expect(executor.ownership.authority == .none)
        }
    }

    /// Starting the persistent engine mid-track is refused **before** anything is torn down —
    /// starting at zero instead would play the wrong audio.
    @Test func aMidTrackPersistentPlanIsRefusedWithoutQuiescing() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            let song = makeSong(id: "p0")
            let (plan, source) = try await persistentPlan(for: song, assembly: assembly)

            let legacy = LegacyPortSpy()
            let persistent = PersistentPortSpy()
            let executor = makeExecutor(legacy: legacy, persistent: persistent)

            let outcome = await executor.execute(
                plan: plan, request: request([song], startOffsetSeconds: 42), currentGeneration: 1)

            #expect(outcome == .refused(.midTrackResumeUnsupported))
            #expect(legacy.calls.contains("quiesce") == false,
                    "legacy was silenced for a plan that was then refused")
            #expect(persistent.calls.isEmpty)
            #expect(executor.ownership.authority == .none)
            #expect(source.consume() == nil, "a refused plan stayed adoptable")
        }
    }

    // MARK: - Quiescence verification

    /// Persistent is never granted while legacy still holds items: `isPlaying == false` is not
    /// evidence, and the item counts are.
    @Test func persistentIsRefusedWhileLegacyStillHoldsTransport() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            let song = makeSong(id: "p0")
            let (plan, source) = try await persistentPlan(for: song, assembly: assembly)

            let legacy = LegacyPortSpy()
            // Paused, but still holding its current item — the case that matters.
            legacy.stateAfterQuiescence = LegacyTransportState(
                rate: 0, hasCurrentItem: true, queuedItemCount: 0, isPlaying: false)
            let persistent = PersistentPortSpy()
            let executor = makeExecutor(legacy: legacy, persistent: persistent)

            let outcome = await executor.execute(plan: plan, request: request([song]),
                                                 currentGeneration: 1)

            #expect(outcome == .fellBackToLegacy(.legacyTransportNotReleased))
            #expect(executor.stepCounts["grantPersistent"] == nil,
                    "persistent was granted authority while legacy still held transport")
            #expect(persistent.calls.contains("start") == false)
            #expect(persistent.calls.contains("adopt") == false)
            #expect(source.consume() == nil, "the source stayed adoptable after a refused handoff")
            #expect(executor.ownership.authority == .legacy)
            #expect(executor.stepCounts["startLegacy"] == 1)
        }
    }

    /// The production legacy port over the real engine: it reads the live session, and quiescence
    /// leaves transport released while preserving the logical session.
    ///
    /// **Deliberately asserts no entry state.** `AudioEngine.shared` is process-wide and whatever
    /// ran before this test may have left it playing — observed in the serialized gate, where this
    /// test entered with `isTransportActive == true` and quiescence released it. Every assertion
    /// below is a post-condition that holds either way; asserting the entry state instead would
    /// make the test a report on suite ordering.
    @Test func theProductionLegacyPortReadsTheLiveSessionAndQuiescesWithoutDestroyingIt() {
        let engine = AudioEngine.shared
        let queueBefore = engine.queue
        let indexBefore = engine.currentIndex
        let contextBefore = engine.playingFromContext
        defer {
            engine.queue = queueBefore
            engine.currentIndex = indexBefore
            engine.playingFromContext = contextBefore
        }

        engine.queue = [makeSong(id: "e0"), makeSong(id: "e1")]
        engine.currentIndex = 1
        engine.playingFromContext = "Album: Port"

        let spy = PlaybackSpy()
        let port = AudioEngineLegacySessionPort(engine: engine, transport: spy)

        let snapshot = port.captureSnapshot(startOffsetSeconds: 0)
        port.quiesceForPersistentSession()

        #expect(port.transportState.isTransportActive == false,
                "the real engine still held transport after quiescence")
        #expect(snapshot.songs.map(\.id) == ["e0", "e1"],
                "capture did not read the live queue")
        #expect(snapshot.currentIndex == 1)
        #expect(snapshot.repeatMode == engine.repeatMode)
        #expect(snapshot.shuffleEnabled == engine.shuffleEnabled)
        #expect(engine.queue.map(\.id) == ["e0", "e1"],
                "quiescence destroyed the queue persistent was about to adopt")
        #expect(engine.currentIndex == 1, "quiescence lost the current position")
        #expect(engine.playingFromContext == "Album: Port")
        #expect(spy.playCalls.isEmpty, "capturing and quiescing started transport")
    }

    /// The production legacy port rebuilds from the snapshot rather than from the quiesced player,
    /// and issues exactly one transport start.
    ///
    /// Every mode in the snapshot differs from the live engine's, so each restore actually fires
    /// rather than being skipped by the "write only when it differs" guard.
    @Test func theProductionLegacyPortRebuildsFromTheSnapshot() {
        let engine = AudioEngine.shared
        let contextBefore = engine.playingFromContext
        let repeatBefore = engine.repeatMode
        let shuffleBefore = engine.shuffleEnabled
        let volumeBefore = engine.userVolume
        defer {
            engine.playingFromContext = contextBefore
            engine.repeatMode = repeatBefore
            engine.shuffleEnabled = shuffleBefore
            engine.userVolume = volumeBefore
        }

        let spy = PlaybackSpy()
        let port = AudioEngineLegacySessionPort(engine: engine, transport: spy)
        let snapshot = PlaybackSessionSnapshot(
            songs: [makeSong(id: "r0"), makeSong(id: "r1"), makeSong(id: "r0")],
            currentIndex: 2, startOffsetSeconds: 0,
            repeatMode: repeatBefore == .all ? .one : .all,
            shuffleEnabled: !shuffleBefore,
            playingFromContext: "Album: Rebuild",
            userVolume: volumeBefore == 0.5 ? 0.25 : 0.5,
            eqEnabled: !engine.eqEnabled)

        port.adopt(snapshot)

        #expect(spy.playCalls.isEmpty, "adoption started transport")
        #expect(engine.playingFromContext == "Album: Rebuild")
        #expect(engine.repeatMode == snapshot.repeatMode, "repeat mode was not restored")
        #expect(engine.shuffleEnabled == snapshot.shuffleEnabled, "shuffle was not restored")
        #expect(engine.userVolume == snapshot.userVolume, "volume was not restored")
        #expect(spy.calls.filter { $0 == "applyEQToggle" }.count == 1,
                "EQ state was not restored through the application contract")

        port.start(snapshot)

        #expect(spy.playCalls.count == 1, "legacy was started \(spy.playCalls.count) times")
        // Duplicate ids stay distinct occurrences: position 2 is the second "r0".
        #expect(spy.playCalls.first?.songId == "r0")
        #expect(spy.playCalls.first?.index == 2)
        #expect(spy.playCalls.first?.queueCount == 3)
        // No seek: `AudioEngine.play` defers its item swap by 50 ms, so a seek issued here would
        // target the outgoing item. Mid-track plans are refused instead.
        #expect(spy.seekTargets.isEmpty, "the port issued a seek that would hit the outgoing item")
    }

    // MARK: - Pre-audible fallback

    /// A start failure before anything is heard tears persistent down, revokes it, rebuilds legacy
    /// from the snapshot and starts legacy exactly once — in that order.
    @Test func aPreAudibleStartFailureFallsBackToLegacyOnce() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            let song = makeSong(id: "p0")
            let (plan, _) = try await persistentPlan(for: song, assembly: assembly)

            let legacy = LegacyPortSpy()
            let persistent = PersistentPortSpy()
            persistent.startFailure = GaplessEngineFailure.engineStartFailed("test")
            let executor = makeExecutor(legacy: legacy, persistent: persistent)

            let outcome = await executor.execute(plan: plan, request: request([song]),
                                                 currentGeneration: 1)

            #expect(outcome == .fellBackToLegacy(.persistentStartFailed))
            #expect(persistent.calls == ["adopt", "adoptPreparedSource", "installObserver",
                                         "start", "tearDown", "clearObserver"],
                    "the fallback sequence was \(persistent.calls)")
            #expect(executor.stepCounts["startLegacy"] == 1,
                    "legacy was started \(executor.stepCounts["startLegacy"] ?? 0) times")
            #expect(executor.stepCounts["startPersistent"] == nil)
            #expect(executor.ownership.authority == .legacy)
            #expect(executor.ownership.ownerCount == 1)
            // Rebuilt from the preserved snapshot, not from the quiesced player.
            #expect(legacy.startedSnapshots.first?.songs.map(\.id) == ["p0"])
        }
    }

    /// Persistent authority is revoked before legacy is rebuilt, so nothing ever observes two
    /// owners — not even transiently.
    @Test func fallbackNeverLetsTheOwnerCountReachTwo() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            let song = makeSong(id: "p0")
            let (plan, _) = try await persistentPlan(for: song, assembly: assembly)

            let legacy = LegacyPortSpy()
            let persistent = PersistentPortSpy()
            persistent.startFailure = GaplessEngineFailure.engineStartFailed("test")
            let executor = makeExecutor(legacy: legacy, persistent: persistent)

            _ = await executor.execute(plan: plan, request: request([song]), currentGeneration: 1)

            // Authority is a single value, so a count of two is unrepresentable; what has to be
            // proven is that legacy is rebuilt only after persistent has let go.
            #expect(legacy.authorityAtCall.isEmpty == false,
                    "nothing observed the authority during the handoff")
            let adoptAuthority = legacy.authorityAtCall.last { $0.0 == "adopt" }?.1
            #expect(adoptAuthority == PlaybackAuthority.none,
                    "legacy was rebuilt while persistent still held authority (\(String(describing: adoptAuthority)))")
            let tearDownAuthority = persistent.authorityAtCall.first { $0.0 == "tearDown" }?.1
            #expect(tearDownAuthority == .persistent,
                    "persistent was torn down without ever having held authority")
        }
    }

    /// After the latch closes, automatic fallback is prohibited: a cutover mid-track is worse than
    /// an error, so persistent keeps the session.
    @Test func fallbackIsProhibitedAfterTheAudibleBoundary() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            let song = makeSong(id: "p0")
            let (plan, _) = try await persistentPlan(for: song, assembly: assembly)

            let legacy = LegacyPortSpy()
            let persistent = PersistentPortSpy()
            // Audio is heard, and only then does the backend fail.
            persistent.becomesAudibleBeforeFailing = true
            persistent.startFailure = GaplessEngineFailure.engineStartFailed("after audio")
            let executor = makeExecutor(legacy: legacy, persistent: persistent)

            let outcome = await executor.execute(plan: plan, request: request([song]),
                                                 currentGeneration: 1)

            #expect(outcome == .persistentRetained(.persistentStartFailed))
            #expect(executor.ownership.audibleBoundaryReached)
            #expect(executor.ownership.authority == .persistent,
                    "the session was cut over to legacy after the listener had heard persistent")
            #expect(executor.stepCounts["startLegacy"] == nil,
                    "legacy was started under audible persistent audio")
            #expect(persistent.calls.contains("tearDown") == false,
                    "audible persistent transport was torn down")
        }
    }

    /// Repeated firings of the audible callback are harmless: a repeat replays an occurrence and a
    /// seek legitimately produces new ones, and neither means a new session.
    @Test func repeatedAudibleFiringsChangeNothing() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            let song = makeSong(id: "p0")
            let (plan, _) = try await persistentPlan(for: song, assembly: assembly)

            let legacy = LegacyPortSpy()
            let persistent = PersistentPortSpy()
            let executor = makeExecutor(legacy: legacy, persistent: persistent)

            _ = await executor.execute(plan: plan, request: request([song]), currentGeneration: 1)

            persistent.fireAudibleObserver()
            let authorityAfterFirst = executor.ownership.authority
            let latchedAfterFirst = executor.ownership.audibleBoundaryReached
            let fallbackAfterFirst = executor.ownership.isFallbackPermitted

            for _ in 0..<4 { persistent.fireAudibleObserver() }

            #expect(latchedAfterFirst, "the first audible occurrence did not close the latch")
            // Nothing moved on the later firings: a repeat and the extra occurrences a seek
            // produces are not new sessions.
            #expect(executor.ownership.audibleBoundaryReached == latchedAfterFirst)
            #expect(executor.ownership.authority == authorityAfterFirst)
            #expect(executor.ownership.isFallbackPermitted == fallbackAfterFirst)
            #expect(executor.ownership.authority == .persistent)
            #expect(executor.ownership.ownerCount == 1)
        }
    }

    /// The real fallback over a real assembly: a refused audio session leaves nothing running, the
    /// callback cleared, and legacy owning the session.
    @Test func aRealPersistentStartFailureTearsDownAndRebuildsLegacy() async throws {
        try await withTemporaryDirectory { directory in
            let files = try makeParts(["p0"], in: directory)
            let assembly = makeAssembly(
                provider: GaplessLocalFileProvider(filesByTrackID: files), directory: directory)
            defer { assembly.controller.stop() }
            // The one failure a start can actually suffer on device.
            assembly.backend.activateAudioSession = { throw CocoaError(.fileNoSuchFile) }
            let song = makeSong(id: "p0")
            let (plan, _) = try await persistentPlan(for: song, assembly: assembly)

            let legacy = LegacyPortSpy()
            let port = PersistentAssemblySessionPort(assembly: assembly)
            let executor = PlaybackSessionPlanExecutor(legacy: legacy, persistent: port)
            legacy.ownership = executor.ownership

            let outcome = await executor.execute(plan: plan, request: request([song]),
                                                 currentGeneration: 1)

            #expect(outcome == .fellBackToLegacy(.persistentStartFailed))
            #expect(assembly.backend.engine.engine.isRunning == false,
                    "the persistent engine kept running after fallback")
            #expect(assembly.backend.engine.player.isPlaying == false)
            #expect(assembly.controller.onFirstAudibleSample == nil,
                    "the audible callback outlived the torn-down persistent session")
            let domainSnapshot = await assembly.backend.domainSnapshotForTesting
            #expect(domainSnapshot.scheduledSegments == 0,
                    "the failed start left \(domainSnapshot.scheduledSegments) segments on the node")
            #expect(executor.ownership.authority == .legacy)
            #expect(executor.stepCounts["startLegacy"] == 1)
        }
    }

    // MARK: - Isolation

    /// Executing a legacy plan constructs no persistent stack.
    ///
    /// Measured on `PersistentPlaybackAssembly.constructionCount`, which every assembly increments,
    /// rather than on the diagnostics registry — that holds a *weak* reference, so it reads nil for
    /// an assembly that was built and released, which would make this pass while an engine, graph
    /// and pool had been allocated and thrown away.
    @Test func executingALegacyPlanConstructsNoPersistentStack() async {
        let legacy = LegacyPortSpy()
        let persistent = PersistentPortSpy()
        let executor = makeExecutor(legacy: legacy, persistent: persistent)
        let constructedBefore = PersistentPlaybackAssembly.constructionCount

        let outcome = await executor.execute(plan: .legacy(reason: .supportedLocalSource),
                                             request: request([makeSong(id: "a")]),
                                             currentGeneration: 1)

        #expect(outcome == .started(.legacy), "the fixture did not reach the legacy path")
        #expect(PersistentPlaybackAssembly.constructionCount == constructedBefore,
                "a legacy execution built \(PersistentPlaybackAssembly.constructionCount - constructedBefore) persistent assemblies")
    }

    /// The executor is reachable only from tests: application routing is still legacy, and the
    /// router's own ownership coordinator has never been granted anything.
    @Test func applicationRoutingIsUnaffected() async {
        let legacy = LegacyPortSpy()
        let persistent = PersistentPortSpy()
        let executor = makeExecutor(legacy: legacy, persistent: persistent)
        _ = await executor.execute(plan: .legacy(reason: .supportedLocalSource),
                                   request: request([makeSong(id: "a")]), currentGeneration: 1)

        guard let router = ApplicationPlayback.router else {
            Issue.record("no router")
            return
        }
        #expect(router.selectedBackend == .legacy)
        #expect(router.isPersistentSessionActive == false)
        // "Not persistent" rather than "no authority": the shared router is process-wide, and
        // another suite may legitimately have started a legacy session on it.
        #expect(router.ownership.authority != .persistent,
                "executing a plan moved the application router to persistent")
        #expect(executor.ownership !== router.ownership,
                "the test executor shares the router's ownership coordinator")
    }

    /// Outcome descriptions are safe — no path, URL, credential or token.
    @Test func outcomeDiagnosticsCarryNoSensitiveDetail() {
        var outcomes: [PlaybackSessionExecutionOutcome] = [.started(.legacy), .started(.persistent),
                                                           .superseded]
        for failure in SafePlaybackRoutingFailure.allCases {
            outcomes.append(.fellBackToLegacy(failure))
            outcomes.append(.persistentRetained(failure))
            outcomes.append(.refused(failure))
        }
        for outcome in outcomes {
            let described = outcome.describedForDiagnostics
            #expect(described.contains("/") == false, "diagnostics leaked a path: \(described)")
            #expect(described.lowercased().contains("http") == false)
            #expect(described.lowercased().contains("token") == false)
            #expect(described.isEmpty == false)
        }
        #expect(PlaybackSessionExecutionOutcome.fellBackToLegacy(.persistentStartFailed).backend
                == .legacy)
        #expect(PlaybackSessionExecutionOutcome.persistentRetained(.persistentStartFailed).backend
                == .persistent)
        #expect(PlaybackSessionExecutionOutcome.superseded.backend == nil)
        #expect(PlaybackSessionExecutionOutcome.refused(.emptySession).backend == nil)
    }
}

// MARK: - Doubles

/// A legacy port that records the sequence without opening an `AVQueuePlayer`.
///
/// Transport state is answered from a configurable pair — what legacy held before quiescence and
/// what it holds after — because "did quiescence actually release transport?" is the branch under
/// test, and a real engine cannot be made to fail it on demand.
@MainActor
final class LegacyPortSpy: LegacyPlaybackSessionPort {
    private(set) var calls: [String] = []
    private(set) var startedSnapshots: [PlaybackSessionSnapshot] = []
    private(set) var adoptedSnapshots: [PlaybackSessionSnapshot] = []
    private(set) var capturedOffsets: [TimeInterval] = []
    /// Authority observed at each call, so the order of revoke and rebuild is checkable.
    private(set) var authorityAtCall: [(String, PlaybackAuthority)] = []
    weak var ownership: PlaybackOwnershipCoordinator?

    var stateBeforeQuiescence = LegacyTransportState(rate: 1, hasCurrentItem: true,
                                                     queuedItemCount: 3, isPlaying: true)
    var stateAfterQuiescence = LegacyTransportState(rate: 0, hasCurrentItem: false,
                                                    queuedItemCount: 0, isPlaying: false)
    var snapshotToCapture = PlaybackSessionSnapshot(
        songs: [], currentIndex: 0, startOffsetSeconds: 0, repeatMode: .off,
        shuffleEnabled: false, playingFromContext: "Album: Spy", userVolume: 1, eqEnabled: false)

    private var hasQuiesced = false

    private func record(_ name: String) {
        calls.append(name)
        authorityAtCall.append((name, ownership?.authority ?? .none))
    }

    var transportState: LegacyTransportState {
        hasQuiesced ? stateAfterQuiescence : stateBeforeQuiescence
    }

    func captureSnapshot(startOffsetSeconds: TimeInterval) -> PlaybackSessionSnapshot {
        record("capture")
        capturedOffsets.append(startOffsetSeconds)
        var snapshot = snapshotToCapture
        snapshot.startOffsetSeconds = startOffsetSeconds
        return snapshot
    }

    func quiesceForPersistentSession() {
        record("quiesce")
        hasQuiesced = true
    }

    func adopt(_ snapshot: PlaybackSessionSnapshot) {
        record("adopt")
        adoptedSnapshots.append(snapshot)
    }

    func start(_ snapshot: PlaybackSessionSnapshot) {
        record("start")
        startedSnapshots.append(snapshot)
    }
}

/// A persistent port that records the sequence without building an audio graph.
@MainActor
final class PersistentPortSpy: PersistentPlaybackSessionPort {
    private(set) var calls: [String] = []
    private(set) var adoptedSnapshots: [PlaybackSessionSnapshot] = []
    private(set) var adoptedSources: [GaplessPreparedTrack] = []
    private(set) var authorityAtCall: [(String, PlaybackAuthority)] = []
    weak var ownership: PlaybackOwnershipCoordinator?

    /// The transport surface. Unused by the executor, which only moves ownership — the router is
    /// what routes commands, and that is covered by `PlaybackAuthorityRoutingTests`.
    let transportDouble = PersistentTransportSpy()
    var transport: any PersistentTransportRouting { transportDouble }

    var isTransportActive = false
    /// When set, `start()` throws it.
    var startFailure: Error?
    /// When true, `start()` fires the audible observer before failing — the post-latch case, where
    /// automatic fallback is prohibited.
    var becomesAudibleBeforeFailing = false

    private var observer: (@MainActor () -> Void)?

    private func record(_ name: String) {
        calls.append(name)
        authorityAtCall.append((name, ownership?.authority ?? .none))
    }

    func adopt(_ snapshot: PlaybackSessionSnapshot) {
        record("adopt")
        adoptedSnapshots.append(snapshot)
    }

    func adopt(preparedSource: GaplessPreparedTrack) async {
        record("adoptPreparedSource")
        adoptedSources.append(preparedSource)
    }

    func installAudibleObserver(_ observer: @escaping @MainActor () -> Void) {
        record("installObserver")
        self.observer = observer
    }

    func clearAudibleObserver() {
        record("clearObserver")
        observer = nil
    }

    private(set) var startedGenerations: [UInt64] = []

    func start(sessionGeneration: UInt64) async throws {
        record("start")
        startedGenerations.append(sessionGeneration)
        if becomesAudibleBeforeFailing { observer?() }
        if let startFailure { throw startFailure }
        isTransportActive = true
    }

    func tearDown() async {
        record("tearDown")
        isTransportActive = false
    }

    /// Simulate the render clock reporting another audible occurrence.
    func fireAudibleObserver() { observer?() }
}

/// Counts materializations, so "the executor never re-fetched what selection already delivered" is
/// a measurement rather than an assumption.
final class CountingFileProvider: GaplessFileProviding, @unchecked Sendable {
    private let inner: GaplessLocalFileProvider
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    init(filesByTrackID: [String: URL]) {
        inner = GaplessLocalFileProvider(filesByTrackID: filesByTrackID)
    }

    func localFile(forTrack trackID: String) async throws -> URL {
        // Taken in a synchronous helper: `NSLock` is unavailable from an async context, and holding
        // it across the await would be wrong anyway.
        bump(trackID)
        return try await inner.localFile(forTrack: trackID)
    }

    private func bump(_ trackID: String) {
        lock.lock()
        defer { lock.unlock() }
        counts[trackID, default: 0] += 1
    }

    func count(for trackID: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[trackID] ?? 0
    }
}
