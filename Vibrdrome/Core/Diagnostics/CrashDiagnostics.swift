import Foundation
import os.log
// MetricKit's diagnostic payloads (MXMetricPayload / MXDiagnosticPayload) are
// available on iOS and Mac Catalyst only — NOT native macOS (AppKit). The
// `VibrdromeMac` scheme builds native macOS, where `canImport(MetricKit)` is
// still true but the types are unavailable, so we gate on `os(iOS)` (true for
// iOS and Catalyst, false for native macOS) rather than canImport.
#if os(iOS)
import MetricKit
#endif

/// Subscribes to MetricKit and records crash / hang / exception diagnostics so
/// they survive the crash and can be viewed in Settings → Diagnostics.
///
/// MetricKit has no remote backend: payloads are delivered locally on the launch
/// following the event. We persist them via `DiagnosticsStore` and log a summary.
/// On native macOS this is a no-op (the MetricKit diagnostic API doesn't exist
/// there); the Diagnostics screen still shows recorded logs.
final class CrashDiagnostics: NSObject, @unchecked Sendable {
    static let shared = CrashDiagnostics()

    private static let logger = Logger(subsystem: "com.vibrdrome.app", category: "Diagnostics")

    // `store` is internally synchronized; `isStarted` is guarded by `startLock`.
    // That covers all mutable state, which is what `@unchecked Sendable` asserts.
    private let store: DiagnosticsStore
    private let startLock = NSLock()
    private var isStarted = false

    init(store: DiagnosticsStore = .makeDefault()) {
        self.store = store
        super.init()
    }

    /// All persisted diagnostics, newest first.
    func records() -> [DiagnosticRecord] { store.load() }

    func clear() { store.clear() }

    /// Register as a MetricKit subscriber. Idempotent; safe to call once at launch.
    func start() {
        startLock.lock()
        if isStarted {
            startLock.unlock()
            return
        }
        isStarted = true
        startLock.unlock()
        #if os(iOS)
        MXMetricManager.shared.add(self)
        Self.logger.info("MetricKit subscriber registered")
        #else
        Self.logger.info("MetricKit unavailable on this platform")
        #endif
    }
}

#if os(iOS)
extension CrashDiagnostics: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        // Metric payloads are large and not crash-relevant; just note arrival.
        Self.logger.debug("Received \(payloads.count) MetricKit metric payload(s)")
    }

    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var records: [DiagnosticRecord] = []
        for payload in payloads {
            let date = payload.timeStampEnd
            records += (payload.crashDiagnostics ?? []).map {
                Self.record(from: $0, kind: .crash, date: date)
            }
            records += (payload.hangDiagnostics ?? []).map {
                Self.record(from: $0, kind: .hang, date: date)
            }
            records += (payload.cpuExceptionDiagnostics ?? []).map {
                Self.record(from: $0, kind: .cpuException, date: date)
            }
            records += (payload.diskWriteExceptionDiagnostics ?? []).map {
                Self.record(from: $0, kind: .diskWriteException, date: date)
            }
        }
        guard !records.isEmpty else { return }
        store.append(records)
        for record in records {
            Self.logger.error("Captured \(record.kind.rawValue, privacy: .public): \(record.summary, privacy: .public)")
        }
    }

    @available(iOS 14.0, *)
    private static func record(from diagnostic: MXDiagnostic, kind: DiagnosticRecord.Kind, date: Date) -> DiagnosticRecord {
        let meta = diagnostic.metaData
        let summary = "\(kind.displayName) · app \(meta.applicationBuildVersion) · OS \(meta.osVersion) · \(meta.deviceType)"
        let detail = String(data: diagnostic.jsonRepresentation(), encoding: .utf8) ?? "<unavailable>"
        return DiagnosticRecord(date: date, kind: kind, summary: summary, detail: detail)
    }
}
#endif
