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
            gaplessSessionSection
            gaplessLeadTimeSection
            cacheSection
            errorsSection
            actionsSection
        }
        .navigationTitle("Debug")
        // The in-list Export button sits at the bottom of the List, where the mini-player and tab bar
        // overlay it — unreachable exactly when a capture must be grabbed while a failure is live.
        // This nav-bar copy is always tappable; both call the same exportLogs().
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportLogs()
                } label: {
                    Label("Export Debug Info", systemImage: "square.and.arrow.up")
                }
            }
        }
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
                #if os(iOS)
                row("CarPlay connected",
                    value: CarPlayConnectionState.shared.isConnected ? "Yes" : "No")
                row("CarPlay last event", value: CarPlayConnectionState.shared.lastEvent)
                #endif

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
                    // Before that it stays on the inert Lane 3C answer, because the audio domain —
                    // and the pool it owns — is built lazily on first use, and this screen exists
                    // to prove it does not exist yet. After a session these are the domain's own
                    // numbers, read from the backend's cached readout (SwiftUI cannot await the
                    // audio actor from a body): a resource-recovery check that reported hardcoded
                    // zeros would read as a pass whatever the engine was actually still holding.
                    if beat.startCount > 0 {
                        let readout = assembly.backend.cachedReadout.snapshot
                        row("Buffer pool",
                            value: "\(readout.poolAvailable)/\(readout.poolCapacity) available")
                        row("Pool in flight", value: "\(readout.poolInFlight)")
                        row("Live source files", value: "\(assembly.backend.openFileCount)")
                        row("Live converters", value: "\(readout.activeConverters)")
                        row("Scheduled segments", value: "\(assembly.backend.scheduledSegments.count)")
                        row("Chunk accounting",
                            value: readout.accountingBalances ? "Balanced" : "UNBALANCED")
                    } else {
                        row("Buffer pool", value: "Not allocated (lazy)")
                        row("Live source files", value: "0")
                        row("Live converters", value: "0")
                        row("Scheduled segments", value: "0")
                    }
                }

                // The same preference as Settings ▸ Gapless Engine (Beta); this mirror is a debug
                // convenience and writes the identical UserDefaults key.
                Toggle("Gapless Engine (Beta)", isOn: Binding(
                    get: { PersistentRoutingSetting.isEnabled },
                    set: { PersistentRoutingSetting.setEnabled($0) }
                ))

                row("Gapless beta opt-in",
                    value: PersistentRoutingSetting.isEnabled ? "On" : "Off")
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

                row("Now Playing", value: "Active (boundary-published)")
                row("Scrobble", value: "Active (completed-play events)")
                row("Visualizer owner",
                    value: VisualizerOwnershipGate.shared.persistentMayPublish
                        ? "Persistent" : "Legacy/none")
                if let adapter = router.persistentAdapterForDiagnostics,
                   let assembly = router.persistentAssembly {
                    let feedStats = assembly.backend.engine.visualizerFeed.stats
                    row("Persistent visualizer",
                        value: adapter.visualizerActive ? "Active" : "Idle")
                    row("Visualizer frames produced", value: "\(feedStats.framesDelivered)")
                    row("Visualizer frames published", value: "\(adapter.visualizerFramesPublished)")
                    row("Visualizer publish cycles", value: "\(adapter.visualizerPublishCycles)")
                    row("Visualizer ownership rejections",
                        value: "\(adapter.visualizerOwnershipRejections)")
                    row("Visualizer contended callbacks", value: "\(feedStats.contendedCallbacks)")
                    row("Last visualizer frame age",
                        value: adapter.lastVisualizerPublish.map {
                            String(format: "%.1f s", Date().timeIntervalSince($0))
                        } ?? "never")
                }

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

    /// The gapless session's own view of playback — queue position, boundary application, and the
    /// counters that distinguish "audio is advancing" from "the session is advancing".
    ///
    /// Added for the session-index-freeze investigation: on device the audio domain kept playing
    /// while the session stopped applying boundaries, and nothing on this screen could show which
    /// half was moving. These rows read the same session the UI mirror reads, so a frozen title
    /// with an advancing "observed boundaries" count (or vice versa) localises the break on sight.
    private var gaplessSessionSection: some View {
        Section {
            if let controller = GaplessDiagnosticsRegistry.current {
                let session = controller.session
                row("Queue index", value: "\(session.queue.currentIndex + 1)/\(session.queue.count)")
                row("Queue generation", value: "\(session.queue.generation)")
                row("Audible item", value: session.audibleItemID.map { "\($0)" } ?? "None")
                row("Audible play instance",
                    value: controller.audiblePlayInstance.map { "\($0)" } ?? "None")
                row("Session render frame",
                    value: String(format: "%.1f s",
                                  Double(session.renderFrame) / GaplessRenderFormat.sampleRate))
                row("Session playing", value: session.isPlaying ? "Yes" : "No")
                // The clock-epoch discriminators: raw player clock vs logical frame vs offset is
                // what distinguishes "audio stopped" from "the raw clock rebased and the logical
                // frame is pinned at its old high-water mark".
                row("Logical render frame", value: "\(controller.backend.renderFrame)")
                row("Raw player clock",
                    value: controller.backend.lastRawSampleTime.map {
                        "\($0) @ \(Int(controller.backend.lastRawSampleRate ?? 0)) Hz"
                    } ?? "no reading")
                row("Timeline offset", value: "\(controller.backend.timelineOffset)")
                row("Last clock rebase", value: controller.backend.lastClockRebaseDescription)
                row("Clock discontinuities",
                    value: "\(controller.backend.clockDiscontinuityCount)")
                row("Observed boundaries", value: "\(controller.observedBoundaries.count)")
                row("Stale results dropped", value: "\(controller.staleResultCount)")
                row("Deadline misses", value: "\(controller.deadlineMisses.count)")
                row("Permanent preparation failures",
                    value: "\(controller.preparationGate.permanentFailureCount)")
            } else {
                row("Persistent session", value: "Not active")
            }
        } header: {
            Text("Gapless Session")
        } footer: {
            Text("""
                Queue index and audible item come from the session; boundaries are render-observed. \
                Audio advancing while these freeze means boundary application has stalled.
                """)
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

        lines.append(contentsOf: persistentDiagnosticsLines())
        lines.append(contentsOf: legacyTransportAndSessionLines())

        exportText = lines.joined(separator: "\n")
        writeExportFile(exportText)
        showExportSheet = true
    }

    /// The CarPlay-J / beta-OFF silent-Legacy diagnostics: the application-vs-Legacy disagreement
    /// snapshot, audio-session believed state, router identity and the recent event log — all the
    /// fields the first inconclusive capture lacked. Sanitized: no URLs, tokens or credentials.
    private func legacyTransportAndSessionLines() -> [String] {
        var lines: [String] = []
        let engine = AudioEngine.shared
        let router = ApplicationPlayback.router

        lines.append("")
        lines.append("=== Router Identity ===")
        #if DEBUG
        lines.append("Router instance ID: \(router?.routerInstanceID ?? -1)")
        #endif
        lines.append("Planning generation: "
                     + "\(router?.lastCompletedPlanningGeneration ?? 0)"
                     + "/\(router?.pendingPlanningGeneration ?? 0)")
        let prep = (router?.persistentPreparationState).map { String(describing: $0) } ?? "unknown"
        lines.append("Persistent preparation: \(prep)")

        lines.append("")
        lines.append("=== Playback-State Disagreement ===")
        lines.append("Application isPlaying: \(ApplicationPlayback.shared.isPlaying)")
        lines.append("Application currentSong: \(ApplicationPlayback.shared.currentSong?.title ?? "none")")
        lines.append("Playback authority: \(router?.ownership.authority.rawValue ?? "?")")
        lines.append("Audio owner count: \(router?.ownership.ownerCount ?? 0)")
        lines.append("Active transport backend: \(router?.selectedBackend.rawValue ?? "?")")

        let player = engine.activePlayer
        let state = engine.legacyTransportState
        lines.append("")
        lines.append("=== Legacy Transport ===")
        lines.append("Legacy rate: \(player?.rate ?? 0)")
        lines.append("Legacy timeControlStatus: \(Self.describe(player?.timeControlStatus))")
        lines.append("Legacy reasonForWaitingToPlay: \(player?.reasonForWaitingToPlay?.rawValue ?? "none")")
        lines.append("Legacy current item present: \(state.hasCurrentItem)")
        lines.append("Legacy current-item status: \(Self.describe(player?.currentItem?.status))")
        lines.append("Legacy current-item error: "
                     + (player?.currentItem?.error.map { "\($0._domain) code \($0._code)" } ?? "none"))
        lines.append("Legacy current playback time: "
                     + (player?.currentItem != nil ? String(format: "%.1f s", player!.currentTime().seconds) : "n/a"))
        lines.append("Legacy queued items: \(state.queuedItemCount)")
        lines.append("Legacy transport active: \(state.isTransportActive)")
        lines.append("Legacy admits transport rebuild: \(engine.admitsTransportRebuild)")

        lines.append("")
        lines.append("=== Audio Session ===")
        lines.append("App-believed state: \(AudioSessionDiagnostics.believedState.rawValue)")
        lines.append("Last operation: \(AudioSessionDiagnostics.lastOperation?.rawValue ?? "none")")
        lines.append("Last operation source: \(AudioSessionDiagnostics.lastSource?.rawValue ?? "none")")
        lines.append("Last operation result: \(AudioSessionDiagnostics.lastResult)")
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        lines.append("Category: \(session.category.rawValue)")
        lines.append("Mode: \(session.mode.rawValue)")
        let route = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        lines.append("Output route: \(route.isEmpty ? "none" : route)")
        lines.append("Sample rate: \(Int(session.sampleRate)) Hz")
        #endif

        lines.append("")
        lines.append("=== Connection context ===")
        // `isConnected` is the last request's status, reset to false on server switch until the next
        // successful request — a stale last-result flag, NOT a live streamability check.
        lines.append("Server isConnected (last-result, not live): \(appState.subsonicClient.isConnected)")

        let events = PlaybackEventLog.snapshot
        lines.append("")
        lines.append("=== Recent playback events (oldest first) ===")
        lines.append(contentsOf: events.isEmpty ? ["none"] : events)
        return lines
    }

    private static func describe(_ status: AVPlayer.TimeControlStatus?) -> String {
        switch status {
        case .paused: "paused"
        case .waitingToPlayAtSpecifiedRate: "waitingToPlayAtSpecifiedRate"
        case .playing: "playing"
        case nil: "none"
        @unknown default: "unknown"
        }
    }

    private static func describe(_ status: AVPlayerItem.Status?) -> String {
        switch status {
        case .unknown: "unknown"
        case .readyToPlay: "readyToPlay"
        case .failed: "failed"
        case nil: "no item"
        @unknown default: "unknown"
        }
    }

    /// The persistent lane, which the original export predated entirely. Everything here is the
    /// closed diagnostics the Debug screen shows — reasons and counters, never a URL, token or
    /// path — so the export stays safe to hand over.
    private func persistentDiagnosticsLines() -> [String] {
        var lines: [String] = []
        if let router = ApplicationPlayback.router {
            lines.append("")
            lines.append("=== Playback Router ===")
            lines.append(router.diagnostics.summary)
        }
        guard let controller = GaplessDiagnosticsRegistry.current else { return lines }
        let session = controller.session
        let backend = controller.backend
        lines.append("")
        lines.append("=== Gapless Session ===")
        lines.append("Queue index: \(session.queue.currentIndex + 1)/\(session.queue.count)")
        lines.append("Queue generation: \(session.queue.generation)")
        lines.append("Audible item: \(session.audibleItemID.map { "\($0)" } ?? "None")")
        lines.append("Audible play instance: "
                     + (controller.audiblePlayInstance.map { "\($0)" } ?? "None"))
        lines.append(String(format: "Session render frame: %.1f s",
                            Double(session.renderFrame) / GaplessRenderFormat.sampleRate))
        lines.append("Session playing: \(session.isPlaying)")
        lines.append("Observed boundaries: \(controller.observedBoundaries.count)")
        lines.append("Stale results dropped: \(controller.staleResultCount)")
        lines.append("Deadline misses: \(controller.deadlineMisses.count)")
        lines.append("Permanent preparation failures: "
                     + "\(controller.preparationGate.permanentFailureCount)")
        let readout = backend.cachedReadout
        let snap = readout.snapshot
        lines.append("")
        lines.append("=== Persistent Engine ===")
        lines.append("Backend state: \(backend.state)")
        lines.append("Backend tail generation: \(backend.tailGeneration)")
        lines.append("Scheduler tail generation: \(readout.tailGeneration)")
        lines.append("Scheduled segments: \(readout.segments.count)")
        lines.append("Logical render frame: \(backend.renderFrame)")
        lines.append("Raw player clock: "
                     + (backend.lastRawSampleTime.map {
                         "\($0) @ \(Int(backend.lastRawSampleRate ?? 0)) Hz"
                     } ?? "no reading"))
        lines.append("Timeline offset: \(backend.timelineOffset)")
        lines.append("Last clock rebase: \(backend.lastClockRebaseDescription)")
        lines.append("Clock discontinuities: \(backend.clockDiscontinuityCount)")
        lines.append("Pool: \(snap.poolAvailable)/\(snap.poolCapacity) available, "
                     + "\(snap.poolInFlight) in flight")
        lines.append("Live sources: \(snap.liveSources), converters: \(snap.activeConverters), "
                     + "open files: \(snap.openFiles)")
        lines.append("Chunks: \(snap.chunksScheduled) scheduled / \(snap.chunksRecycled) recycled "
                     + "/ \(snap.chunksReclaimedAtStop) reclaimed")
        lines.append("Render deposits: \(snap.renderDeposits) "
                     + "(unreconciled \(snap.unreconciledDeposits))")
        lines.append("Accounting balanced: \(snap.accountingBalances), "
                     + "starvations: \(snap.poolStarvations), stale recycles: \(snap.staleRecycles)")
        return lines
    }

    /// The export is also written to Documents so it can be pulled from a Mac without touching the
    /// phone (`devicectl device copy files --domain-type appDataContainer`). Fixed name, overwritten
    /// each export — the timestamp lives inside the file.
    private func writeExportFile(_ text: String) {
        guard let documents = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else { return }
        try? text.write(to: documents.appendingPathComponent("debug-export.txt"),
                        atomically: true, encoding: .utf8)
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
