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
    @State private var recentErrors: [DebugErrorEntry] = []
    @State private var showExportSheet = false
    @State private var exportText = ""

    var body: some View {
        List {
            serverSection
            audioSection
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
            row("Duration", value: formatDuration(engine.duration))
            row("Position", value: formatDuration(engine.currentTime))

            #if os(iOS)
            let route = AVAudioSession.sharedInstance().currentRoute
            if let output = route.outputs.first {
                row("Audio Route", value: "\(output.portName) (\(output.portType.rawValue))")
            }
            row("Sample Rate", value: "\(Int(AVAudioSession.sharedInstance().sampleRate)) Hz")
            #endif
        }
    }

    // MARK: - Cache

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
            lines.append("Current: \(song.title) by \(song.artist ?? "Unknown")")
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
