import SwiftUI
import OSLog
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct DiagnosticsView: View {
    @State private var logEntries: [String] = []
    @State private var crashReports: [DiagnosticRecord] = []
    @State private var isLoading = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        List {
            crashReportsSection
            logsSection
        }
        .navigationTitle("Diagnostics")
        .task {
            await loadLogs()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    copyLogs()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }

    @ViewBuilder
    private var crashReportsSection: some View {
        Section {
            if crashReports.isEmpty {
                Text("No crashes or hangs recorded.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(crashReports) { report in
                    DisclosureGroup {
                        Text(report.detail)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.kind.displayName)
                                .font(.callout.weight(.semibold))
                            Text(Self.dateFormatter.string(from: report.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Crash & Hang Reports")
        } footer: {
            Text("Captured automatically by the system. Reports appear after the next launch following a crash or hang. Tap Copy to share them.")
        }
    }

    @ViewBuilder
    private var logsSection: some View {
        Section {
            if isLoading {
                ProgressView("Loading logs…")
            } else if logEntries.isEmpty {
                Text("No recent logs")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(logEntries, id: \.self) { entry in
                    Text(entry)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Recent Logs (\(logEntries.count))")
        } footer: {
            Text("Logs from the current session. Tap Copy to share with support.")
        }
    }

    @MainActor
    private func loadLogs() async {
        isLoading = true
        defer { isLoading = false }
        crashReports = CrashDiagnostics.shared.records()
        logEntries = []
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date(timeIntervalSinceNow: -3600))
            let predicate = NSPredicate(format: "subsystem == %@", "com.vibrdrome.app")
            let entries = try store.getEntries(at: position, matching: predicate)
            for entry in entries {
                if let logEntry = entry as? OSLogEntryLog {
                    logEntries.append("[\(logEntry.category)] \(logEntry.composedMessage)")
                }
            }
        } catch {
            logEntries.append("Error loading logs: \(error.localizedDescription)")
        }
    }

    private func copyLogs() {
        var lines: [String] = []
        if !crashReports.isEmpty {
            lines.append("=== Crash & Hang Reports ===")
            for report in crashReports {
                lines.append("[\(report.kind.displayName)] \(Self.dateFormatter.string(from: report.date))")
                lines.append(report.summary)
                lines.append(report.detail)
                lines.append("")
            }
        }
        lines.append("=== Recent Logs ===")
        lines.append(contentsOf: logEntries)
        let text = lines.joined(separator: "\n")

        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

#Preview {
    DiagnosticsView()
}
