import Foundation
import Testing
@testable import Vibrdrome

/// Tests for the rolling prefetch window: current + next fully ready + one preparing.
struct GaplessPrefetchWindowTests {
    private let queue = ["t1", "t2", "t3", "t4", "t5"]

    @Test func windowCoversCurrentPlusTwo() {
        let window = GaplessPrefetchWindow()

        #expect(window.size == 3)
        #expect(window.trackIDs(queue: queue, currentIndex: 0) == ["t1", "t2", "t3"])
        #expect(window.trackIDs(queue: queue, currentIndex: 2) == ["t3", "t4", "t5"])
    }

    /// Only current + next are boundary-critical; the third slot is allowed to still be fetching.
    @Test func boundaryCriticalSetIsCurrentAndNext() {
        let window = GaplessPrefetchWindow()

        #expect(window.mustBeReadyTrackIDs(queue: queue, currentIndex: 1) == ["t2", "t3"])
    }

    @Test func windowClampsAtTheEndOfTheQueue() {
        let window = GaplessPrefetchWindow()

        #expect(window.trackIDs(queue: queue, currentIndex: 4) == ["t5"])
        #expect(window.mustBeReadyTrackIDs(queue: queue, currentIndex: 4) == ["t5"])
    }

    /// A stale current index must not schedule audio.
    @Test func outOfRangeIndexYieldsNothing() {
        let window = GaplessPrefetchWindow()

        #expect(window.trackIDs(queue: queue, currentIndex: 9).isEmpty)
        #expect(window.trackIDs(queue: [], currentIndex: 0).isEmpty)
        #expect(!window.isBoundarySafe(queue: [], currentIndex: 0, prepared: []))
    }

    @Test func prepareListSkipsReadyAndInFlightTracks() {
        let window = GaplessPrefetchWindow()

        let toPrepare = window.trackIDsToPrepare(queue: queue, currentIndex: 0,
                                                 prepared: ["t1"], inFlight: ["t2"])

        #expect(toPrepare == ["t3"])
    }

    /// Order matters: the most imminent boundary has to be fetched first.
    @Test func prepareListIsInPlayOrder() {
        let window = GaplessPrefetchWindow()

        let toPrepare = window.trackIDsToPrepare(queue: queue, currentIndex: 1,
                                                 prepared: [], inFlight: [])

        #expect(toPrepare == ["t2", "t3", "t4"])
    }

    /// Played tracks are dead weight and pin cache files the rolling cache wants to reap.
    @Test func releasesTracksBehindAndAheadOfTheWindow() {
        let window = GaplessPrefetchWindow()

        let toRelease = window.trackIDsToRelease(queue: queue, currentIndex: 2,
                                                 prepared: ["t1", "t2", "t3", "t4", "t5"])

        #expect(toRelease == ["t1", "t2"])
    }

    @Test func boundaryIsSafeOnlyWhenCurrentAndNextAreBothReady() {
        let window = GaplessPrefetchWindow()

        #expect(window.isBoundarySafe(queue: queue, currentIndex: 0, prepared: ["t1", "t2"]))
        // Next track missing → the upcoming transition will not be gapless.
        #expect(!window.isBoundarySafe(queue: queue, currentIndex: 0, prepared: ["t1", "t3"]))
    }

    /// The last track has no successor, so "current is ready" is the whole requirement.
    @Test func lastTrackIsBoundarySafeWithOnlyItself() {
        let window = GaplessPrefetchWindow()

        #expect(window.isBoundarySafe(queue: queue, currentIndex: 4, prepared: ["t5"]))
    }

    @Test func deeperWindowPreparesFurtherAhead() {
        let window = GaplessPrefetchWindow(readyAhead: 2, preparingAhead: 1)

        #expect(window.size == 4)
        #expect(window.mustBeReadyTrackIDs(queue: queue, currentIndex: 0) == ["t1", "t2", "t3"])
    }

    @Test func negativeDepthsAreClampedRatherThanTrusted() {
        let window = GaplessPrefetchWindow(readyAhead: -5, preparingAhead: -5)

        #expect(window.size == 1)
        #expect(window.trackIDs(queue: queue, currentIndex: 0) == ["t1"])
    }
}
