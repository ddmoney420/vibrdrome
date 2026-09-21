import AVFoundation
import Foundation
import Testing
@testable import Vibrdrome

/// The CarPlay-J diagnostics units: audio-session believed-state tracking, the bounded event log,
/// and router-instance identity. These are observational only — they must record accurately without
/// ever claiming a session is active when activation failed, and without leaking anything sensitive.
@Suite(.serialized)
@MainActor
struct PlaybackDiagnosticsTests {

    /// A successful activation advances the believed state to active.
    @Test func successfulActivationMarksActive() {
        AudioSessionDiagnostics.record(.activate, source: .legacyPlay, error: nil)
        #expect(AudioSessionDiagnostics.believedState == .active)
        #expect(AudioSessionDiagnostics.lastResult == "success")
        #expect(AudioSessionDiagnostics.lastSource == .legacyPlay)
    }

    /// A successful deactivation advances the believed state to inactive.
    @Test func successfulDeactivationMarksInactive() {
        AudioSessionDiagnostics.record(.activate, source: .persistentStart, error: nil)
        AudioSessionDiagnostics.record(.deactivate, source: .persistentTeardown, error: nil)
        #expect(AudioSessionDiagnostics.believedState == .inactive)
        #expect(AudioSessionDiagnostics.lastOperation == .deactivate)
    }

    /// A FAILED activation must not mark the session active — the believed state is preserved and the
    /// error is recorded. This is the property that stops "app thinks it's playing" from hiding a
    /// dead session.
    @Test func failedActivationDoesNotMarkActive() {
        AudioSessionDiagnostics.record(.deactivate, source: .persistentTeardown, error: nil)
        #expect(AudioSessionDiagnostics.believedState == .inactive)

        let failure = NSError(domain: "AVAudioSession", code: 561_017_449)
        AudioSessionDiagnostics.record(.activate, source: .legacyPlay, error: failure)

        #expect(AudioSessionDiagnostics.believedState == .inactive,
                "a failed activation falsely marked the session active")
        #expect(AudioSessionDiagnostics.lastResult.hasPrefix("error:"))
    }

    /// The event log is bounded and keeps insertion order (oldest first).
    @Test func eventLogIsBoundedAndOrdered() {
        for index in 0..<60 { PlaybackEventLog.record("event \(index)") }
        let snapshot = PlaybackEventLog.snapshot
        #expect(snapshot.count <= 40, "event log grew unbounded: \(snapshot.count)")
        // The last recorded event survives; the earliest were dropped.
        #expect(snapshot.last?.contains("event 59") == true)
        #expect(snapshot.contains { $0.contains("event 0 ") } == false,
                "the oldest events were not evicted")
    }

    /// Recorded events carry no credential-shaped content — callers pass only sanitized values.
    @Test func eventLogCarriesNoSensitiveContent() {
        PlaybackEventLog.record("play gen 3: beta=off plan=Legacy -> Started legacy authority=legacy")
        for line in PlaybackEventLog.snapshot {
            #expect(line.lowercased().contains("http") == false, "event leaked a URL: \(line)")
            #expect(line.lowercased().contains("token") == false)
            #expect(line.lowercased().contains("password") == false)
        }
    }

    /// The transport describers map the closed AVFoundation status sets to sanitized words, so the
    /// advance-path event log reads unambiguously and never carries a URL/token.
    @Test func transportDescribersMapKnownStates() {
        #expect(PlaybackStateDescribe.timeControl(.paused) == "paused")
        #expect(PlaybackStateDescribe.timeControl(.playing) == "playing")
        #expect(PlaybackStateDescribe.timeControl(.waitingToPlayAtSpecifiedRate) == "waiting")
        #expect(PlaybackStateDescribe.timeControl(nil) == "nil")
        #expect(PlaybackStateDescribe.itemStatus(.readyToPlay) == "ready")
        #expect(PlaybackStateDescribe.itemStatus(.failed) == "failed")
        #expect(PlaybackStateDescribe.itemStatus(.unknown) == "unknown")
        #expect(PlaybackStateDescribe.itemStatus(nil) == "nil")
    }

    /// A nil player snapshots without crashing and says so.
    @Test func transportSnapshotHandlesNilPlayer() {
        #expect(PlaybackStateDescribe.snapshot(nil) == "player=nil")
    }

    /// Router instance IDs are monotonic, so a capture can tell a reused router from a reconstructed
    /// one (the ambiguity the first J capture could not resolve).
    @Test func routerInstanceIDsAreMonotonic() {
        let first = ApplicationPlaybackRouter(
            legacy: LegacyAudioEngineAdapter(),
            persistentBuilder: ProductionPersistentPlaybackAssemblyBuilder())
        let second = ApplicationPlaybackRouter(
            legacy: LegacyAudioEngineAdapter(),
            persistentBuilder: ProductionPersistentPlaybackAssemblyBuilder())
        #expect(second.routerInstanceID > first.routerInstanceID,
                "router instance IDs are not monotonic (\(first.routerInstanceID), \(second.routerInstanceID))")
    }
}
