import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// Remote commands and engine selection, driven through the engine-neutral controller with captured
/// audio for anything that changes what is heard.
@MainActor
struct GaplessRemoteCommandTests {
    static let sampleRate = 44_100.0
    static let trackFrames = 8_820
    static let tones: [Double] = [233, 379, 611, 977]

    @MainActor
    struct Rig {
        let app: GaplessApplicationPlaybackController
        let controller: GaplessPlaybackController
        let remote: GaplessRemoteCommandCoordinator
        let audio: GaplessAudioSessionCoordinator
        let selector: GaplessEngineSelector
        let capture: GaplessRealTimeCapture
        let songIDs: [String]
        let directory: URL
        let activations: () -> Int

        func cleanUp() {
            capture.stop()
            app.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        func heard() -> [Double] {
            capture.heardSequence(frequencies: GaplessRemoteCommandTests.tones,
                                  sampleRate: GaplessRemoteCommandTests.sampleRate)
        }
    }

    static func makeRig(count: Int, repeatMode: RepeatMode = .off) throws -> Rig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [String: URL] = [:]
        var songIDs: [String] = []
        for index in 0..<count {
            let tone = tones[index % tones.count]
            let songID = "song\(index + 1)"
            let url = directory.appendingPathComponent("\(songID).wav")
            var samples = [Int16](repeating: 0, count: trackFrames)
            for i in 0..<trackFrames {
                samples[i] = Int16((max(-1, min(1, 0.5 * sin(2.0 * .pi * tone * Double(i) / sampleRate))) * 32767).rounded())
            }
            try GaplessPipelineOfflineTests.writeWav(url: url, samples: samples, sampleRate: sampleRate)
            files[songID] = url
            songIDs.append(songID)
        }

        let session = GaplessPlaybackSession(sampleRate: sampleRate)
        session.replaceQueue(songIDs: songIDs)
        for id in songIDs { session.songDurations[id] = Double(trackFrames) / sampleRate }
        session.setRepeatMode(repeatMode)

        let backend = GaplessRealTimeBackend()
        let audio = GaplessAudioSessionCoordinator()
        var activationCount = 0
        audio.activateSession = {
            activationCount += 1
            #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try audioSession.setActive(true)
            #endif
        }
        backend.activateAudioSession = { try audio.activateForPlayback() }

        let preparer = GaplessTrackPreparer(provider: GaplessLocalFileProvider(filesByTrackID: files),
                                            renderSampleRate: sampleRate)
        let controller = GaplessPlaybackController(session: session, backend: backend,
                                                   preparer: preparer)
        let selector = GaplessEngineSelector()
        let app = GaplessApplicationPlaybackController(controller: controller, selector: selector,
                                                       audioSession: audio)
        let remote = GaplessRemoteCommandCoordinator(controller: app)
        return Rig(app: app, controller: controller, remote: remote, audio: audio,
                   selector: selector, capture: GaplessRealTimeCapture(engine: backend.engine),
                   songIDs: songIDs, directory: directory, activations: { activationCount })
    }

    @discardableResult
    static func run(_ rig: Rig, until what: String, timeout: TimeInterval = 30,
                    _ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await rig.controller.tick()
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(4))
        }
        Issue.record("timed out waiting for \(what)")
        return false
    }

    // MARK: - Registration

    /// Production registers once for the app lifetime; this preserves that and makes it provable.
    @Test func registrationHappensOnceAndIsIdempotent() {
        let coordinator = GaplessRemoteCommandCoordinator()
        var enablement: [(GaplessRemoteCommand, Bool)] = []
        coordinator.applyEnablement = { enablement.append(($0, $1)) }

        let first = coordinator.registerIfNeeded()
        let second = coordinator.registerIfNeeded()
        let third = coordinator.registerIfNeeded()

        #expect(first == second)
        #expect(second == third)
        #expect(coordinator.registrationCount == 1)
        // Exactly one active handler per enabled command.
        for command in GaplessRemoteCommandCoordinator.enabledCommands {
            #expect(coordinator.activeHandlerCount(for: command) == 1, "\(command)")
        }
        // Skip commands stay disabled, so the lock screen shows track navigation.
        for command in GaplessRemoteCommandCoordinator.disabledCommands {
            #expect(coordinator.activeHandlerCount(for: command) == 0, "\(command)")
        }
        #expect(enablement.filter { $0.1 }.count == GaplessRemoteCommandCoordinator.enabledCommands.count)
    }

    /// Engine rebuilds must not duplicate handlers — registration lives above the engine precisely
    /// so a reconstruction cannot touch it.
    @Test func engineReconstructionDoesNotDuplicateHandlers() throws {
        let coordinator = GaplessRemoteCommandCoordinator()
        let token = coordinator.registerIfNeeded()
        let backend = GaplessRealTimeBackend()

        for _ in 0..<5 {
            try backend.prepareGraph()
            backend.stop()
            coordinator.registerIfNeeded()          // as app code would call on each lifecycle event
        }

        #expect(coordinator.registrationCount == 1)
        #expect(coordinator.isCurrent(token))
        for command in GaplessRemoteCommandCoordinator.enabledCommands {
            #expect(coordinator.activeHandlerCount(for: command) == 1)
        }
    }

    /// A command arriving under a superseded registration must not drive the current engine.
    @Test func staleRegistrationCommandsAreRejected() async {
        let coordinator = GaplessRemoteCommandCoordinator()
        let old = coordinator.registerIfNeeded()
        let new = coordinator.reregister()

        #expect(old != new)
        #expect(!coordinator.isCurrent(old))
        let status = await coordinator.handle(.play, token: old)
        #expect(status == .commandFailed)
        #expect(coordinator.rejectedStaleCommands == 1)
    }

    // MARK: - Status mapping

    /// A command must not report success merely because it was accepted.
    @Test(arguments: [
        (GaplessCommandFailure.noActionableItem, GaplessRemoteCommandStatus.noActionableNowPlayingItem),
        (.invalidPosition, .commandFailed),
        (.audioSessionUnavailable, .commandFailed),
        (.engineUnavailable, .commandFailed),
        (.unsupported, .noSuchContent)
    ])
    func failuresMapToTruthfulStatuses(scenario: (GaplessCommandFailure, GaplessRemoteCommandStatus)) {
        #expect(GaplessRemoteCommandStatus.mapping(for: scenario.0) == scenario.1)
    }

    @Test func commandsOnAnEmptyQueueReportNoActionableItem() async throws {
        let rig = try Self.makeRig(count: 0)
        defer { rig.cleanUp() }
        let token = rig.remote.registerIfNeeded()

        #expect(await rig.remote.handle(.play, token: token) == .noActionableNowPlayingItem)
        #expect(await rig.remote.handle(.nextTrack, token: token) == .noActionableNowPlayingItem)
        #expect(await rig.remote.handle(.previousTrack, token: token) == .noActionableNowPlayingItem)
        // Nothing was activated for a command that could not act.
        #expect(rig.activations() == 0)
    }

    @Test func seekWithNoPositionOrAnInvalidOneFails() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        let token = rig.remote.registerIfNeeded()
        try await rig.app.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }

        #expect(await rig.remote.handle(.changePlaybackPosition, token: token) == .commandFailed)
        // Past the end of the item.
        #expect(await rig.remote.handle(.changePlaybackPosition, token: token,
                                        positionSeconds: 9_999) == .commandFailed)
        #expect(await rig.remote.handle(.changePlaybackPosition, token: token,
                                        positionSeconds: -1) == .commandFailed)
    }

    @Test func disabledSkipCommandsReportNoSuchContent() async {
        let coordinator = GaplessRemoteCommandCoordinator()
        let token = coordinator.registerIfNeeded()

        #expect(await coordinator.handle(.skipForward, token: token) == .noSuchContent)
        #expect(await coordinator.handle(.skipBackward, token: token) == .noSuchContent)
    }

    // MARK: - Remote Play / Pause / Toggle

    @Test func remotePlayActivatesOnceAndRepeatedPlayDoesNot() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        let token = rig.remote.registerIfNeeded()

        #expect(await rig.remote.handle(.play, token: token) == .success)
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }
        #expect(rig.activations() == 1)

        // Repeated Play while already playing: no second activation, no second play instance.
        let boundariesBefore = rig.controller.observedBoundaries.count
        #expect(await rig.remote.handle(.play, token: token) == .success)
        #expect(await rig.remote.handle(.play, token: token) == .success)
        #expect(rig.activations() == 1)
        #expect(rig.controller.observedBoundaries.count == boundariesBefore)
    }

    @Test func remotePausePreservesQueueAndDoesNotDeactivate() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        let token = rig.remote.registerIfNeeded()
        try await rig.app.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }
        let audibleBefore = rig.controller.session.audibleItemID
        let tailBefore = rig.controller.backend.scheduledSegments.count

        #expect(await rig.remote.handle(.pause, token: token) == .success)

        #expect(!rig.app.isPlaying)
        #expect(rig.controller.session.audibleItemID == audibleBefore)   // play instance preserved
        #expect(rig.controller.backend.scheduledSegments.count == tailBefore)
        #expect(rig.controller.session.queue.count == 3)
        // Activate-only policy: pause does not deactivate.
        #expect(rig.audio.isActive)
    }

    /// Toggle decides from authoritative application state, not from the node or the session.
    @Test func toggleUsesApplicationStateNotNodeState() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        let token = rig.remote.registerIfNeeded()

        // Stopped → plays.
        #expect(await rig.remote.handle(.togglePlayPause, token: token) == .success)
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }
        #expect(rig.app.isPlaying)

        // Playing → pauses.
        #expect(await rig.remote.handle(.togglePlayPause, token: token) == .success)
        #expect(!rig.app.isPlaying)
        #expect(rig.app.playbackState == .paused)

        // Paused → resumes, without a second activation.
        #expect(await rig.remote.handle(.togglePlayPause, token: token) == .success)
        #expect(rig.app.isPlaying)
        #expect(rig.activations() == 1)
    }

    // MARK: - Remote Next / Previous / seek

    @Test func remoteNextIsHeardAndUsesTheRealTransportPath() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        let token = rig.remote.registerIfNeeded()
        rig.capture.start()
        try await rig.app.play()
        await Self.run(rig, until: "first tone heard", timeout: 20) { !rig.heard().isEmpty }

        #expect(await rig.remote.handle(.nextTrack, token: token) == .success)
        await Self.run(rig, until: "second tone heard", timeout: 20) { rig.heard().count >= 2 }
        try await Task.sleep(for: .milliseconds(120))

        let heard = rig.heard()
        #expect(heard.first == Self.tones[0])
        #expect(heard.contains(Self.tones[1]), "heard \(heard)")
        #expect(rig.controller.session.queue.currentItem?.songID == rig.songIDs[1])
    }

    /// Only the final command of a rapid burst may determine what is audible.
    @Test func fiveRapidRemoteNextCommandsLeaveOnlyTheFinalDestination() async throws {
        let rig = try Self.makeRig(count: 5)
        defer { rig.cleanUp() }
        let token = rig.remote.registerIfNeeded()
        rig.capture.start()
        try await rig.app.play()
        await Self.run(rig, until: "first tone", timeout: 20) { !rig.heard().isEmpty }

        for _ in 0..<4 { _ = await rig.remote.handle(.nextTrack, token: token) }
        await Self.run(rig, until: "final destination", timeout: 25) {
            rig.controller.observedBoundaries.contains { $0.songID == rig.songIDs[4] }
        }
        try await Task.sleep(for: .milliseconds(150))

        #expect(rig.controller.session.queue.currentItem?.songID == rig.songIDs[4])
        #expect(rig.heard().last == Self.tones[4 % Self.tones.count], "heard \(rig.heard())")
    }

    @Test(arguments: [2.9, 3.0, 3.1])
    func remotePreviousHonoursTheProductionThreshold(elapsed: TimeInterval) async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        let token = rig.remote.registerIfNeeded()
        rig.controller.session.setCurrentIndex(1)
        try await rig.app.play()

        #expect(await rig.remote.handle(.previousTrack, token: token,
                                        elapsedSeconds: elapsed) == .success)

        if elapsed > 3.0 {
            #expect(rig.controller.session.queue.currentItem?.songID == rig.songIDs[1])
        } else {
            #expect(rig.controller.session.queue.currentItem?.songID == rig.songIDs[0])
        }
    }

    @Test func remoteSeekUsesTheSamePathAsTheUI() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        let token = rig.remote.registerIfNeeded()
        try await rig.app.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }

        #expect(await rig.remote.handle(.changePlaybackPosition, token: token,
                                        positionSeconds: 0.05) == .success)

        #expect(rig.controller.session.queue.currentIndex == 0)
        #expect(rig.app.playbackState == .playing)
    }

    // MARK: - Command races

    @Test func mixedRapidCommandsLeaveACoherentFinalState() async throws {
        let rig = try Self.makeRig(count: 4)
        defer { rig.cleanUp() }
        let token = rig.remote.registerIfNeeded()
        try await rig.app.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }

        // Next → Next → Previous → Seek → Pause → Play
        _ = await rig.remote.handle(.nextTrack, token: token)
        _ = await rig.remote.handle(.nextTrack, token: token)
        _ = await rig.remote.handle(.previousTrack, token: token, elapsedSeconds: 1)
        _ = await rig.remote.handle(.changePlaybackPosition, token: token, positionSeconds: 0.05)
        _ = await rig.remote.handle(.pause, token: token)
        _ = await rig.remote.handle(.play, token: token)

        #expect(rig.app.isPlaying)
        #expect(rig.controller.backend.engine.engine.isRunning)
        #expect(rig.controller.session.queue.count == 4)
        // One activation for the whole burst: pause never deactivated, so Play did not re-activate.
        #expect(rig.activations() == 1)
    }

    // MARK: - Engine selection

    /// Capability and gapless guarantee are deliberately separate results.
    @Test(arguments: [
        (GaplessTrim.Reason.wholeFile, true),
        (.lameGaplessHeader, true),
        (.mp3WithoutGaplessMetadata, false)
    ])
    func capabilityMatrixSeparatesPlayableFromGaplessCapable(
        scenario: (reason: GaplessTrim.Reason, gapless: Bool)) throws {
        let rig = try Self.makeRig(count: 1)
        defer { rig.cleanUp() }
        let capability = GaplessCapability.evaluate(trimReason: scenario.reason)

        #expect(rig.app.selectEngine(for: capability, sourceDescription: "src",
                                     trimReason: scenario.reason))

        let diagnostics = rig.app.lastSelectionDiagnostics
        #expect(diagnostics?.gaplessCapable == scenario.gapless)
        // Playable regardless — a source may be playable without being guaranteed gapless.
        #expect(diagnostics?.playableByPersistentEngine == true)
        #expect(diagnostics?.decidedBeforePlayback == true)
        #expect(diagnostics?.trimClassification == scenario.reason.rawValue)
        if !scenario.gapless { #expect(diagnostics?.fallbackReason != nil) }
    }

    /// The rule that protects the output stream: never swap engines under playing audio.
    @Test func engineSelectionIsRefusedWhileATrackIsAudible() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        try await rig.app.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }
        #expect(rig.app.isTrackAudible)
        let generationBefore = rig.app.selectionGeneration

        let changed = rig.app.selectEngine(for: .capable, sourceDescription: "other",
                                           trimReason: .wholeFile)

        #expect(!changed, "engine selection changed while a track was audible")
        #expect(rig.app.selectionGeneration == generationBefore)
        #expect(rig.app.selectedEngine == .persistentGapless)
    }

    @Test func engineSelectionIsAllowedWhileStopped() async throws {
        let rig = try Self.makeRig(count: 2)
        defer { rig.cleanUp() }
        try await rig.app.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }
        rig.app.stop()

        #expect(!rig.app.isTrackAudible)
        #expect(rig.app.selectEngine(for: .capable, sourceDescription: "s", trimReason: .wholeFile))
        #expect(rig.app.selectionGeneration == 1)
    }

    /// A deadline miss after playback is audible must NOT cause a fallback — controlled wait handles
    /// it, because switching engines mid-track is the thing being avoided.
    @Test func aDeadlineMissWhileAudibleDoesNotSwitchEngines() async throws {
        let rig = try Self.makeRig(count: 3)
        defer { rig.cleanUp() }
        try await rig.app.play()
        await Self.run(rig, until: "audio") { rig.controller.backend.renderFrame > 2_000 }

        // A fallback request arriving mid-track is recorded but refused.
        let switched = rig.selector.requestFallback(itemID: "late", reason: .preparationDeadlineMissed)

        #expect(!switched)
        #expect(rig.selector.selection == .persistentGapless)
        #expect(rig.selector.reasons(forItemID: "late") == [.preparationDeadlineMissed])
        #expect(rig.controller.deadlinePolicy == .controlledWait)
    }

    /// Diagnostics carry the decision without leaking anything sensitive.
    @Test func selectionDiagnosticsCarryNoSensitiveData() throws {
        let rig = try Self.makeRig(count: 1)
        defer { rig.cleanUp() }
        rig.app.selectEngine(for: GaplessCapability.evaluate(trimReason: .mp3WithoutGaplessMetadata),
                             sourceDescription: "song-id-only", trimReason: .mp3WithoutGaplessMetadata)

        let diagnostics = try #require(rig.app.lastSelectionDiagnostics)
        let text = "\(diagnostics)"
        #expect(!text.contains("http"))
        #expect(!text.contains("token"))
        #expect(!text.contains("password"))
        #expect(diagnostics.selectionGeneration == 1)
    }
}
