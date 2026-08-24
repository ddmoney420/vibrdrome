#if DEBUG
import AVFoundation
import Nuke
import SwiftData
import SwiftUI

struct DebugView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var downloadedSongs: [DownloadedSong]
    @State private var imageCacheSize: String = "Calculating..."
    @State private var persistentPreparationMessage: String?
    @State private var recentErrors: [DebugErrorEntry] = []
    @State private var showExportSheet = false
    @State private var exportText = ""

    var body: some View {
        List {
            serverSection
            audioSection
            playbackRouterSection
            gaplessLeadTimeSection
            cacheSection
            errorsSection
            actionsSection
        }
        .navigationTitle("Debug")
        .onAppear { loadCacheSize() }
        .sheet(isPresented: $showExportSheet) {
            DebugShareSheetView(text: exportText)
        }
    }

    // MARK: - Server

    private var serverSection: some View {
        Section("Server") {
            row("URL", value: appState.serverURL)
            row("Username", value: appState.username)
            row("Connected", value: appState.subsonicClient.isConnected ? "Yes" : "No")
            row("Servers", value: "\(appState.servers.count)")
            if let activeId = appState.activeServerId {
                row("Active ID", value: String(activeId.prefix(8)) + "...")
            }
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        Section("Audio") {
            let engine = AudioEngine.shared
            row("Playing", value: engine.isPlaying ? "Yes" : "No")
            row("Buffering", value: engine.isBuffering ? "Yes" : "No")
            if let song = engine.currentSong {
                row("Current Song", value: song.title)
                row("Song ID", value: song.id)

            }
            row("Queue Size", value: "\(engine.queue.count)")
            row("Queue Index", value: "\(engine.currentIndex)")
            row("Shuffle", value: engine.shuffleEnabled ? "On" : "Off")
            row("Repeat", value: repeatLabel(engine.repeatMode))
            row("Recently Played Count", value: "\(engine.recentlyPlayed.count)")
            row("Pre-download Status", value: predownloadStatusLabel(engine.predownloadStatus))
            if engine.predownloadSpeed < 0.0001 {
                row("Pre-download Speed", value: "-")
            } else if engine.predownloadSpeed < 1024.0 {
                row("Pre-download Speed", value: String(format: "%.1f KBs", engine.predownloadSpeed))
            } else {
                row("Pre-download Speed", value: String(format: "%.1f Mbs", engine.predownloadSpeed/1024))
            }

            row("Pre-download Pending", value: "\(engine.predownloadsPending)")
            row("Duration", value: formatDuration(engine.duration))
            row("Position", value: formatDuration(engine.currentTime))

            #if os(iOS)
            let route = AVAudioSession.sharedInstance().currentRoute
            if let output = route.outputs.first {
                row("Audio Route", value: "\(output.portName) (\(output.portType.rawValue))")
            }
            row("Sample Rate", value: "\(Int(AVAudioSession.sharedInstance().sampleRate)) Hz")
            let player = AudioEngine.shared.activePlayer
            row("Ext. Playback Allowed",
                value: (player?.allowsExternalPlayback ?? false) ? "true" : "false")
            row("Ext. Playback Active",
                value: (player?.isExternalPlaybackActive ?? false) ? "YES" : "no")
            #endif
        }
    }

    // MARK: - Cache

    /// Router state and the explicit persistent-construction trigger.
    ///
    /// **The button builds the stack; it does not play anything.** Lane 3C exists to measure what
    /// construction costs and to prove the result is inert, so preparation has to be something a
    /// person asks for rather than a side effect of using the app. Selected backend stays Legacy
    /// afterwards — if this screen ever shows anything else before Lane 3D, that is the bug.
    @ViewBuilder
    private var playbackRouterSection: some View {
        if let router = ApplicationPlayback.router {
            let diagnostics = router.diagnostics
            Section {
                row("Persistent preparation", value: diagnostics.preparationDescription)
                row("Active transport backend",
                    value: diagnostics.selectedBackend == .legacy ? "Legacy" : "Persistent")
                row("Playback authority", value: diagnostics.authority.rawValue)
                row("Audio owner count", value: "\(router.ownership.ownerCount)")
                row("Legacy adapter", value: diagnostics.legacyAdapterActive ? "Active" : "Inactive")
                row("Persistent controller",
                    value: diagnostics.persistentControllerConstructed ? "Constructed" : "Not constructed")
                row("Persistent transport active",
                    value: router.isPersistentSessionActive ? "Yes" : "No")

                let beat = diagnostics.heartbeat
                row("Persistent heartbeat", value: beat.isRunning ? "Running" : "Stopped")
                row("Heartbeat session generation", value: "\(beat.sessionGeneration)")
                row("Heartbeat tick count", value: "\(beat.tickCount)")
                row("Last tick age",
                    value: beat.lastTickAge.map { String(format: "%.2f s", $0) } ?? "never")
                row("Heartbeat start count", value: "\(beat.startCount)")
                row("Heartbeat cancellation count", value: "\(beat.cancellationCount)")
                row("Concurrent heartbeat count", value: "\(beat.peakConcurrentCount)")
                row("Planning generation",
                    value: "\(diagnostics.lastCompletedPlanningGeneration)/\(diagnostics.pendingPlanningGeneration)")
                row("Session replacement in progress",
                    value: diagnostics.isReplacingSession ? "Yes" : "No")
                row("Audible boundary reached",
                    value: diagnostics.audibleBoundaryReached ? "Yes" : "No")
                row("Fallback permitted", value: diagnostics.isFallbackPermitted ? "Yes" : "No")

                if let assembly = router.persistentAssembly {
                    row("Assembly generation", value: "#\(assembly.generation)")
                    row("Graph format", value: assembly.diagnostics.graphFormat)
                    row("Engine running", value: assembly.backend.engine.engine.isRunning ? "Yes" : "No")
                    row("Player node playing",
                        value: assembly.backend.engine.player.isPlaying ? "Yes" : "No")
                    row("Engine state", value: "\(assembly.backend.state)")

                    // The **live** substrate readout, and only once a session has actually run.
                    //
                    // Before that it stays on the inert Lane 3C answer, because reaching through to
                    // the buffer scheduler would build the lazily-allocated pool this screen exists
                    // to prove does not exist yet. After a session it must be the real numbers: a
                    // resource-recovery check that reported hardcoded zeros would read as a pass
                    // whatever the engine was actually still holding, which is worse than no check.
                    if beat.startCount > 0 {
                        let scheduler = assembly.backend.bufferScheduler
                        row("Buffer pool",
                            value: "\(scheduler.pool.availableCount)/\(scheduler.pool.capacity) available")
                        row("Pool in flight", value: "\(scheduler.pool.inFlightCount)")
                        row("Live source files", value: "\(assembly.backend.openFileCount)")
                        row("Live converters", value: "\(scheduler.activeConverterCount)")
                        row("Scheduled segments", value: "\(assembly.backend.scheduledSegments.count)")
                        row("Chunk accounting",
                            value: scheduler.chunkAccountingBalances ? "Balanced" : "UNBALANCED")
                    } else {
                        row("Buffer pool", value: "Not allocated (lazy)")
                        row("Live source files", value: "0")
                        row("Live converters", value: "0")
                        row("Scheduled segments", value: "0")
                    }
                }

                Toggle("Use Persistent Playback Engine", isOn: Binding(
                    get: { PersistentRoutingSetting.isEnabled },
                    set: { PersistentRoutingSetting.setEnabled($0) }
                ))

                row("Persistent routing enabled",
                    value: PersistentRoutingSetting.isEnabled ? "Yes" : "No")
                row("Session selection state", value: router.sessionSelectionState.describedForDiagnostics)

                // The legacy side, read from the same `legacyTransportState` the ownership
                // assertions use. Items and observers are the evidence, not the playing flag: a
                // paused `AVQueuePlayer` still holds both, which is exactly how a resurrected
                // legacy transport would hide underneath an audible persistent session.
                let legacyState = AudioEngine.shared.legacyTransportState
                row("Legacy rate", value: String(format: "%.2f", legacyState.rate))
                row("Legacy current item", value: legacyState.hasCurrentItem ? "Present" : "None")
                row("Legacy queued items", value: "\(legacyState.queuedItemCount)")
                row("Legacy transport active",
                    value: legacyState.isTransportActive ? "YES" : "No")
                row("Legacy admits transport rebuild",
                    value: AudioEngine.shared.admitsTransportRebuild ? "Yes" : "No (quiesced)")

                row("Now Playing / scrobble / visualizer", value: "Pending")

                Button("Prepare Persistent Engine") {
                    do {
                        try router.preparePersistentBackend()
                        persistentPreparationMessage = "Prepared. Selected backend is still Legacy."
                    } catch let failure as PersistentPreparationFailure {
                        persistentPreparationMessage = "Preparation failed: \(failure.rawValue)"
                    } catch {
                        persistentPreparationMessage = "Preparation failed."
                    }
                }
                .disabled(diagnostics.persistentPreparationState == .ready)

                if let message = persistentPreparationMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Playback Router")
            } footer: {
                Text("""
                    The toggle applies to the next playback session — changing it never switches \
                    the backend under audible audio. Stop playback, change it, then start the same \
                    queue again. Prepare builds the engine without selecting or starting it.
                    """)
            }
        }
    }

    /// Lead-time diagnostics for the persistent gapless engine.
    ///
    /// The labels spell out each definition because they are not what the names suggest:
    /// "preparation lead" is *ready to audible*, not *requested to ready*. That is the existing
    /// production measurement, and renaming or recomputing it for a nicer label would make the
    /// number on screen disagree with the number the engine uses.
    private var gaplessLeadTimeSection: some View {
        Section {
            if let controller = GaplessDiagnosticsRegistry.current {
                let stats = controller.leadTimeStatistics
                leadRows(title: "Preparation lead", window: stats.preparation)
                leadRows(title: "Scheduling lead", window: stats.scheduling)
                row("Samples retained",
                    value: "\(stats.preparation.count)/\(GaplessLeadTimeWindow.capacity)")
            } else {
                row("Persistent engine", value: "Not active")
                row("Preparation lead", value: "Not measured")
                row("Scheduling lead", value: "Not measured")
            }
        } header: {
            Text("Gapless Lead Times")
        } footer: {
            Text("""
                Preparation lead = item ready → item audible. \
                Scheduling lead = item handed to the player node → item audible. \
                Rolling window of the last \(GaplessLeadTimeWindow.capacity) transitions, \
                cleared when playback is stopped.
                """)
        }
    }

    @ViewBuilder
    private func leadRows(title: String, window: GaplessLeadTimeWindow) -> some View {
        if window.hasMeasurement {
            row("\(title) latest", value: Self.milliseconds(window.latest))
            row("\(title) minimum", value: Self.milliseconds(window.minimum))
            row("\(title) average", value: Self.milliseconds(window.average))
        } else {
            row(title, value: "Not measured")
        }
    }

    private static func milliseconds(_ value: TimeInterval?) -> String {
        guard let value else { return "Not measured" }
        return String(format: "%.1f ms", value * 1_000)
    }

    private var cacheSection: some View {
        Section("Cache & Storage") {
            row("Image Cache", value: imageCacheSize)
            let completed = downloadedSongs.filter(\.isComplete)
            row("Downloaded Songs", value: "\(completed.count)")
            row("Download Storage", value: formatBytes(completed.reduce(0) { $0 + $1.fileSize }))
            row("Pending Downloads", value: "\(downloadedSongs.filter { !$0.isComplete }.count)")
        }
    }

    // MARK: - Errors

    private var errorsSection: some View {
        Section("Recent Errors") {
            if recentErrors.isEmpty {
                Text("No errors recorded")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentErrors) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.message)
                            .font(.caption)
                            .lineLimit(3)
                        Text(entry.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section("Actions") {
            Button {
                clearImageCache()
            } label: {
                Label("Clear Image Cache", systemImage: "photo.on.rectangle.angled")
            }

            Button(role: .destructive) {
                DownloadManager.shared.deleteAllDownloads()
            } label: {
                Label("Delete All Downloads", systemImage: "trash")
            }

            Button {
                exportLogs()
            } label: {
                Label("Export Debug Info", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontDesign(.monospaced)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }

    private func repeatLabel(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: "Off"
        case .all: "All"
        case .one: "One"
        }
    }

    private func predownloadStatusLabel(_ status: PredownloadStatus) -> String {
        switch status {
        case .idle: "Idle"
        case .active: "Active"
        case .stalled: "Stalled"
        case .waiting: "Waiting"
        }
    }

    private func loadCacheSize() {
        Task.detached {
            let cache = ImagePipeline.shared.cache
            let diskSize = cache.containsDiskData ? "Active" : "Empty"
            let totalSize = try? FileManager.default
                .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent("com.github.kean.Nuke.DataCache/com.vibrdrome.images")
                .resourceValues(forKeys: [.totalFileAllocatedSizeKey])
                .totalFileAllocatedSize
            let sizeStr: String
            if let totalSize {
                sizeStr = formatBytes(Int64(totalSize))
            } else {
                sizeStr = diskSize
            }
            await MainActor.run {
                imageCacheSize = sizeStr
            }
        }
    }

    private func clearImageCache() {
        ImagePipeline.shared.cache.removeAll()
        imageCacheSize = "Cleared"
    }

    private func exportLogs() {
        var lines: [String] = []
        lines.append("=== Vibrdrome Debug Export ===")
        lines.append("Date: \(Date())")
        lines.append("")
        lines.append("Server URL: \(appState.serverURL)")
        lines.append("Username: \(appState.username)")
        lines.append("Connected: \(appState.subsonicClient.isConnected)")
        lines.append("Servers: \(appState.servers.count)")
        lines.append("")
        let engine = AudioEngine.shared
        lines.append("Playing: \(engine.isPlaying)")
        lines.append("Queue: \(engine.queue.count) songs, index \(engine.currentIndex)")
        lines.append("Shuffle: \(engine.shuffleEnabled), Repeat: \(repeatLabel(engine.repeatMode))")
        if let song = engine.currentSong {
            lines.append("Current: \(song.title) by \(song.displayArtist ?? "Unknown")")
        }
        lines.append("")
        let completed = downloadedSongs.filter(\.isComplete)
        lines.append("Downloads: \(completed.count) songs, \(formatBytes(completed.reduce(0) { $0 + $1.fileSize }))")
        lines.append("Image Cache: \(imageCacheSize)")
        lines.append("")
        #if os(iOS)
        let route = AVAudioSession.sharedInstance().currentRoute
        if let output = route.outputs.first {
            lines.append("Audio Route: \(output.portName) (\(output.portType.rawValue))")
        }
        lines.append("Sample Rate: \(Int(AVAudioSession.sharedInstance().sampleRate)) Hz")
        #endif
        lines.append("")
        lines.append("App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
        lines.append("Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
        #if os(iOS)
        lines.append("iOS: \(UIDevice.current.systemVersion)")
        lines.append("Device: \(UIDevice.current.model)")
        #elseif os(macOS)
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #endif

        exportText = lines.joined(separator: "\n")
        showExportSheet = true
    }
}

// MARK: - Share Sheet

private struct DebugShareSheetView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Debug Export")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy") {
                        #if os(iOS)
                        UIPasteboard.general.string = text
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        #endif
                    }
                }
            }
        }
    }
}

struct DebugErrorEntry: Identifiable {
    let id = UUID()
    let message: String
    let timestamp: Date
}

// MARK: - Nuke Cache Extension

private extension ImagePipeline.Cache {
    var containsDiskData: Bool { true }
}
#endif
