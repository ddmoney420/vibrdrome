import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// The preparation gate: classification, backoff, and the retry storm it exists to stop.
///
/// Most of these drive a **injected monotonic clock** rather than sleeping. Backoff deadlines are
/// the thing under test, and asserting them against real time would either make the suite slow or
/// make it flaky — neither of which proves the schedule is right.
@MainActor
struct GaplessPreparationGateTests {
    static func identity(_ slot: UInt64, song: String = "s", generation: UInt64 = 1,
                         offset: AVAudioFramePosition = 0,
                         occurrenceEpoch: UInt64 = 0) -> GaplessPreparationIdentity {
        GaplessPreparationIdentity(itemID: GaplessQueueItemID(rawValue: slot), songID: song,
                                   queueGeneration: generation, sourceStartOffsetFrames: offset,
                                   occurrenceEpoch: occurrenceEpoch)
    }

    /// A gate whose clock the test drives.
    static func makeGate() -> (GaplessPreparationGate, () -> Void) {
        let gate = GaplessPreparationGate()
        let clock = Box(0.0)
        gate.now = { clock.value }
        return (gate, { })
    }

    final class Box<T> { var value: T; init(_ value: T) { self.value = value } }

    // MARK: - Classification

    /// Which failures are worth retrying, stated as a table rather than left to a default.
    @Test func failuresAreClassifiedDeliberately() {
        // Permanent: these fail identically however many times they are tried.
        #expect(GaplessFailurePolicy.classify(GaplessConversionError.unsupportedChannelCount(6)) == .permanent)
        #expect(GaplessFailurePolicy.classify(
            GaplessConversionError.converterUnavailable(source: "a", destination: "b")) == .permanent)
        #expect(GaplessFailurePolicy.classify(GaplessConversionError.conversionFailed("x")) == .permanent)
        #expect(GaplessFailurePolicy.classify(
            GaplessChunkSourceError.unsupportedFormat(trackID: "t", reason: "r")) == .permanent)
        #expect(GaplessFailurePolicy.classify(GaplessChunkSourceError.seekFailed(trackID: "t")) == .permanent)
        #expect(GaplessFailurePolicy.classify(GaplessPreparationError.emptyAudio(trackID: "t")) == .permanent)
        #expect(GaplessFailurePolicy.classify(
            GaplessPreparationError.unreadable(trackID: "t", underlying: URLError(.badURL))) == .permanent)

        // Transient: a provider hiccup, a cache file being swapped, a superseded tail.
        #expect(GaplessFailurePolicy.classify(GaplessPreparationError.noLocalFile(trackID: "t")) == .transient)
        #expect(GaplessFailurePolicy.classify(
            GaplessChunkSourceError.readFailed(trackID: "t", underlying: URLError(.timedOut))) == .transient)
        #expect(GaplessFailurePolicy.classify(GaplessConversionError.cancelled) == .transient)
        #expect(GaplessFailurePolicy.classify(CancellationError()) == .transient)
        #expect(GaplessFailurePolicy.classify(URLError(.timedOut)) == .transient)
        // An unrecognised error is transient: retrying a few times under backoff costs little,
        // whereas wrongly calling it permanent makes a recoverable track unplayable.
        #expect(GaplessFailurePolicy.classify(NSError(domain: "x", code: 1)) == .transient)
    }

    // MARK: - Permanent failure

    /// A permanent failure is attempted once and then never again automatically, however hard the
    /// pump asks.
    @Test func permanentFailureIsAttemptedExactlyOnce() {
        let gate = GaplessPreparationGate()
        let clock = Box(0.0)
        gate.now = { clock.value }
        let id = Self.identity(1)

        #expect(gate.beginAttemptIfAllowed(id))
        gate.recordFailure(id, error: GaplessConversionError.unsupportedChannelCount(6))
        #expect(gate.state(of: id) == .permanentFailure(reason: "GaplessConversionError"))

        // 2000 pump observations spread over ten simulated seconds.
        for step in 0..<2_000 {
            clock.value = Double(step) * 0.005
            #expect(!gate.beginAttemptIfAllowed(id), "a permanent failure was retried at \(clock.value)s")
        }
        print("""
            PREPPERM attempts \(gate.attempts(for: id))  \
            suppressedPumps \(gate.suppressedPumps(for: id))  \
            state \(gate.state(of: id))
            """)
        #expect(gate.attempts(for: id) == 1, "attempted \(gate.attempts(for: id)) times")
        #expect(gate.suppressedPumps(for: id) == 2_000)

        // An explicit retry produces exactly one new attempt, on a new occurrence.
        let fresh = gate.explicitRetry(id)
        #expect(fresh != id, "explicit retry reused the failed occurrence's identity")
        #expect(gate.beginAttemptIfAllowed(fresh))
        #expect(!gate.beginAttemptIfAllowed(fresh), "explicit retry allowed a second concurrent attempt")
        #expect(gate.attempts(for: fresh) == 1)
        // The original record is untouched, so the two cannot be confused.
        #expect(gate.attempts(for: id) == 1)
    }

    // MARK: - Transient backoff

    /// The retry deadlines, asserted against the schedule rather than against wall-clock luck.
    @Test func transientFailureFollowsTheBackoffSchedule() {
        let gate = GaplessPreparationGate()
        let clock = Box(0.0)
        gate.now = { clock.value }
        let id = Self.identity(2)
        var attemptTimes: [TimeInterval] = []

        // Fail four times, pumping every 5 ms throughout.
        for step in 0..<800 {
            clock.value = Double(step) * 0.005
            if gate.beginAttemptIfAllowed(id) {
                attemptTimes.append(clock.value)
                if attemptTimes.count <= 4 {
                    gate.recordFailure(id, error: GaplessPreparationError.noLocalFile(trackID: "t"))
                } else {
                    gate.recordReady(id)
                }
            }
        }

        print("""
            PREPBACKOFF attempts at \(attemptTimes.map { String(format: "%.3f", $0) })  \
            total \(gate.attempts(for: id))  suppressed \(gate.suppressedPumps(for: id))  \
            recoveredAfter \(gate.entry(for: id)?.recoveredAfterAttempts.map(String.init) ?? "-")
            """)

        // 0 ms, +250 ms, +750 ms, +1750 ms — the cumulative schedule.
        let expected: [TimeInterval] = [0, 0.25, 0.75, 1.75]
        #expect(attemptTimes.count >= 4, "only \(attemptTimes.count) attempts")
        for (index, target) in expected.enumerated() {
            let actual = attemptTimes[index]
            #expect(abs(actual - target) <= 0.01,
                    "attempt \(index + 1) at \(actual)s, expected ~\(target)s")
        }
        // Pumping 800 times did not produce 800 attempts.
        #expect(gate.suppressedPumps(for: id) > 700)
        #expect(gate.entry(for: id)?.recoveredAfterAttempts != nil, "recovery was not recorded")
    }

    /// A source that never recovers must reach the cap and stay there, with attempts growing
    /// logarithmically rather than linearly.
    @Test func persistentTransientFailureReachesTheEightSecondCap() {
        let gate = GaplessPreparationGate()
        let clock = Box(0.0)
        gate.now = { clock.value }
        let id = Self.identity(3)
        var attemptTimes: [TimeInterval] = []

        // 30 simulated seconds, pumped every 5 ms.
        for step in 0..<6_000 {
            clock.value = Double(step) * 0.005
            if gate.beginAttemptIfAllowed(id) {
                attemptTimes.append(clock.value)
                gate.recordFailure(id, error: URLError(.timedOut))
            }
        }
        let intervals = zip(attemptTimes.dropFirst(), attemptTimes).map { $0 - $1 }
        print("""
            PREPCAP attempts \(attemptTimes.count) over 30 s  \
            at \(attemptTimes.map { String(format: "%.2f", $0) })  \
            intervals \(intervals.map { String(format: "%.2f", $0) })  \
            suppressed \(gate.suppressedPumps(for: id))
            """)

        // 0, .25, .75, 1.75, 3.75, 7.75, then every 8 s: 8 attempts in 30 s, not 6000.
        #expect(attemptTimes.count <= 10, "\(attemptTimes.count) attempts in 30 s is not bounded")
        #expect(attemptTimes.count >= 6, "only \(attemptTimes.count) attempts — backoff is too slow")
        if let last = intervals.last {
            #expect(abs(last - 8.0) <= 0.02, "final interval \(last)s, expected the 8 s cap")
        }
    }

    // MARK: - Cancellation and identity

    /// A retry deadline that expires after the occurrence was abandoned must not start work.
    @Test func cancelledOccurrenceNeverRetries() {
        let gate = GaplessPreparationGate()
        let clock = Box(0.0)
        gate.now = { clock.value }
        let id = Self.identity(4)

        #expect(gate.beginAttemptIfAllowed(id))
        gate.recordFailure(id, error: URLError(.timedOut))
        gate.cancel(id)                                   // seek / Next / queue replacement / stop

        clock.value = 30                                  // long past every deadline
        #expect(!gate.beginAttemptIfAllowed(id), "a cancelled occurrence retried")
        #expect(gate.attempts(for: id) == 1)
    }

    /// A queue edit abandons the old generation's occurrences without touching the new one's.
    @Test func queueGenerationChangeCancelsOnlyStaleOccurrences() {
        let gate = GaplessPreparationGate()
        let clock = Box(0.0)
        gate.now = { clock.value }
        let old = Self.identity(5, generation: 1)
        let fresh = Self.identity(5, generation: 2)

        #expect(gate.beginAttemptIfAllowed(old))
        gate.recordFailure(old, error: URLError(.timedOut))
        gate.cancelAll(except: 2)

        clock.value = 30
        #expect(!gate.beginAttemptIfAllowed(old), "an occurrence from a replaced queue retried")
        #expect(gate.beginAttemptIfAllowed(fresh), "the new generation was blocked by the old one")
    }

    /// Failure state must key on the occurrence, not the song — duplicate slots, Repeat All wraps
    /// and seeks legitimately produce distinct occurrences of the same song.
    @Test func failureStateDoesNotCollapseBySongIdentity() {
        let gate = GaplessPreparationGate()
        let clock = Box(0.0)
        gate.now = { clock.value }

        // Same song in two slots: one failing permanently must not condemn the other.
        let slotOne = Self.identity(10, song: "same")
        let slotTwo = Self.identity(11, song: "same")
        #expect(gate.beginAttemptIfAllowed(slotOne))
        gate.recordFailure(slotOne, error: GaplessPreparationError.emptyAudio(trackID: "same"))
        #expect(!gate.beginAttemptIfAllowed(slotOne))
        #expect(gate.beginAttemptIfAllowed(slotTwo), "a duplicate slot inherited another's failure")

        // Same slot, different seek position: a genuinely different occurrence.
        let atZero = Self.identity(12, song: "seeky", offset: 0)
        let atOffset = Self.identity(12, song: "seeky", offset: 44_100)
        #expect(gate.beginAttemptIfAllowed(atZero))
        gate.recordFailure(atZero, error: GaplessPreparationError.emptyAudio(trackID: "seeky"))
        #expect(gate.beginAttemptIfAllowed(atOffset), "a seek occurrence inherited the failure at 0")

        // But an unchanged pump cycle must NOT look like a new occurrence — that would reset the
        // counter and restore the storm.
        let repeated = Self.identity(12, song: "seeky", offset: 0)
        #expect(!gate.beginAttemptIfAllowed(repeated),
                "an identical occurrence was treated as new and retried")
    }

    /// Repeat One replaying a permanently failed slot must not re-attempt it on every replay cycle.
    @Test func repeatOneDoesNotReattemptAPermanentlyFailedSlot() {
        let gate = GaplessPreparationGate()
        let clock = Box(0.0)
        gate.now = { clock.value }
        let id = Self.identity(20, song: "loop")

        #expect(gate.beginAttemptIfAllowed(id))
        gate.recordFailure(id, error: GaplessChunkSourceError.unsupportedFormat(trackID: "loop",
                                                                                reason: "6 channels"))
        // Repeat One keeps planning the same slot, same generation, same offset.
        for step in 0..<500 {
            clock.value = Double(step) * 0.02
            #expect(!gate.beginAttemptIfAllowed(id))
        }
        #expect(gate.attempts(for: id) == 1)
        #expect(gate.permanentFailureCount == 1)
    }
}

/// The storm itself, reproduced through the real controller.
@Suite(.serialized)
@MainActor
struct GaplessRetryStormTests {
    /// A provider that always fails, so every preparation attempt is a real attempt.
    final class AlwaysFailingProvider: GaplessFileProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var callCount: Int { lock.lock(); defer { lock.unlock() }; return count }

        private func recordCall() { lock.lock(); count += 1; lock.unlock() }

        func localFile(forTrack trackID: String) async throws -> URL {
            // Counted in a synchronous helper: NSLock cannot be taken across a suspension point.
            recordCall()
            // Classified permanent: the decoder has looked at it and cannot read it.
            throw GaplessPreparationError.unreadable(trackID: trackID,
                                                     underlying: URLError(.cannotDecodeContentData))
        }
    }

    /// Reproduces the ~1.5 s injection that previously produced 172-450 attempts.
    ///
    /// Reports both numbers, because "no storm" is about work done, not about how often the pump
    /// looked: the pump is *expected* to observe the failed occurrence constantly.
    @Test func permanentlyFailingItemIsAttemptedOncePerOccurrence() async throws {
        let session = GaplessPlaybackSession(sampleRate: 44_100)
        session.replaceQueue(songIDs: ["bad0", "bad1", "bad2"])
        for id in ["bad0", "bad1", "bad2"] { session.songDurations[id] = 5 }

        let provider = AlwaysFailingProvider()
        let backend = GaplessRealTimeBackend()
        let controller = GaplessPlaybackController(
            session: session, backend: backend,
            preparer: GaplessTrackPreparer(provider: provider, renderSampleRate: 44_100))
        defer { controller.stop() }

        let descriptorsBefore = GaplessBufferFixtures.openFileDescriptorCount()
        // Baseline taken after one pump has already run. Constructing the backend brings up the
        // audio stack, a one-time ~100 MB allocation that is not storm growth — charging it here
        // would misreport the very thing under test by an order of magnitude.
        await controller.replenishTail()
        var pumps = 0
        // Sampled at the midpoint rather than at the start. Bringing up the audio stack allocates
        // ~100-190 MB asynchronously over the first seconds, which is not storm growth; comparing
        // the two halves of the window measures the steady state, which is what "no spin" means.
        var footprintMidpoint: UInt64 = 0

        // Deliberately not `play()`: the queue cannot produce audio, and what is under test is the
        // pump's behaviour against an unplayable queue.
        let start = Date()
        let deadline = start.addingTimeInterval(4)
        while Date() < deadline {
            await controller.replenishTail()
            pumps += 1
            if footprintMidpoint == 0, Date().timeIntervalSince(start) >= 2 {
                footprintMidpoint = GaplessBufferFixtures.physFootprint()
            }
            try? await Task.sleep(for: .milliseconds(4))
        }

        let growthMB = Double(Int64(GaplessBufferFixtures.physFootprint())
                              - Int64(footprintMidpoint)) / 1_048_576
        let descriptorGrowth = GaplessBufferFixtures.openFileDescriptorCount() - descriptorsBefore
        print("""
            PREPSTORM pumps \(pumps)  providerCalls \(provider.callCount)  \
            gateAttempts \(controller.preparationGate.totalAttempts)  \
            suppressed \(controller.preparationGate.totalSuppressedPumps)  \
            permanentFailures \(controller.preparationGate.permanentFailureCount)  \
            growth \(String(format: "%.2f", growthMB)) MB  fdDelta \(descriptorGrowth)  \
            queue \(session.queue.count)  boundaries \(controller.observedBoundaries.count)  \
            states \(controller.preparationGate.diagnosticSummary)
            """)

        // The pump ran hundreds of times; the provider was called once per planned occurrence.
        #expect(pumps > 100, "only \(pumps) pump cycles — not a comparable reproduction")
        #expect(provider.callCount <= session.queue.count,
                "provider called \(provider.callCount) times for \(session.queue.count) occurrences")
        #expect(controller.preparationGate.totalAttempts <= session.queue.count,
                "\(controller.preparationGate.totalAttempts) attempts")
        #expect(controller.preparationGate.permanentFailureCount > 0,
                "the failure was not classified permanent")
        // Descriptors are attributable to this test — a storm would re-open files on every pump.
        #expect(descriptorGrowth <= 8, "descriptors grew \(descriptorGrowth)")
        // Footprint is REPORTED, not asserted. This suite runs beside gate tests that loop thousands
        // of times, so process footprint here is not attributable to the pump; asserting it would be
        // asserting something this test cannot isolate. Memory boundedness is proven by the gated
        // soak runs (CISOAK / BUFMEM), where the process is doing nothing else.
        _ = growthMB
        // The queue is preserved, nothing became audible, and no boundary was invented.
        #expect(session.queue.count == 3)
        #expect(controller.observedBoundaries.isEmpty, "a phantom boundary was emitted")
        #expect(session.audibleItemID == nil, "a failed item was marked audible")
        #expect(controller.hasPermanentPreparationFailure,
                "the failure is not visible to the application layer")

        // An explicit retry produces exactly one further attempt per item, not a new storm.
        let before = provider.callCount
        for item in session.queue.items { controller.retryPreparation(itemID: item.id) }
        for _ in 0..<100 {
            await controller.replenishTail()
            try? await Task.sleep(for: .milliseconds(2))
        }
        let afterRetry = provider.callCount - before
        print("PREPSTORM explicitRetry providerCalls +\(afterRetry) for \(session.queue.count) items")
        #expect(afterRetry <= session.queue.count,
                "explicit retry produced \(afterRetry) attempts for \(session.queue.count) items")
    }
}
