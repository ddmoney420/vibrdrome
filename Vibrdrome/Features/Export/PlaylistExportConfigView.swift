#if os(macOS)
import SwiftUI
import SwiftData

struct PlaylistExportConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    let playlistId: String
    let playlistName: String
    let existingExport: ExportedPlaylist?

    @State private var selectedFolderURL: URL?
    @State private var folderBookmarkData: Data?
    @State private var syncMode: PlaylistExportSyncMode = .addOnly
    @State private var isActive: Bool = true
    @State private var transcodeFormat: String = ""
    @State private var transcodeBitrate: Int = 192
    @State private var isPickingFolder = false

    private var isEditing: Bool { existingExport != nil }
    private var transcodeFormatBinding: String? { transcodeFormat.isEmpty ? nil : transcodeFormat }
    private var formatChanged: Bool {
        guard let existing = existingExport else { return false }
        let newFormat: String? = transcodeFormat.isEmpty ? nil : transcodeFormat
        return newFormat != existing.appliedTranscodeFormat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Export Settings" : "Export Playlist")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            Form {
                Section("Export Folder") {
                    HStack {
                        if let url = selectedFolderURL {
                            Text(url.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("No folder selected")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("Choose…") {
                            Task { await pickFolder() }
                        }
                    }
                }

                Section("Sync") {
                    Picker("Mode", selection: $syncMode) {
                        ForEach(PlaylistExportSyncMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    Toggle("Auto-sync on launch", isOn: $isActive)
                }

                Section("Transcode") {
                    Picker("Format", selection: $transcodeFormat) {
                        Text("Original (no transcode)").tag("")
                        Text("MP3").tag("mp3")
                        Text("AAC").tag("aac")
                        Text("Opus").tag("opus")
                        Text("FLAC").tag("flac")
                    }
                    .pickerStyle(.menu)
                    if !transcodeFormat.isEmpty {
                        HStack {
                            Text("Bitrate (kbps)")
                            TextField("192", value: $transcodeBitrate, format: .number)
                                .frame(width: 80)
                        }
                    }
                    if formatChanged {
                        Label(
                            "Changing format will re-download all songs on next sync.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Export") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folderBookmarkData == nil)
            }
            .padding()
        }
        .frame(width: 420)
        .onAppear { loadExisting() }
    }

    private func pickFolder() async {
        guard let url = await PlaylistExportManager.shared.pickFolder() else { return }
        guard let data = try? PlaylistExportManager.shared.bookmarkData(for: url) else { return }
        selectedFolderURL = url
        folderBookmarkData = data
    }

    private func loadExisting() {
        guard let export = existingExport else {
            // Pre-fill from global defaults
            if let defaultData = UserDefaults.standard.data(forKey: UserDefaultsKeys.exportDefaultFolderBookmark),
               let (url, _) = try? PlaylistExportManager.shared.resolveBookmark(defaultData) {
                selectedFolderURL = url
                folderBookmarkData = defaultData
            }
            if let defaultMode = UserDefaults.standard.string(forKey: UserDefaultsKeys.exportDefaultSyncMode),
               let mode = PlaylistExportSyncMode(rawValue: defaultMode) {
                syncMode = mode
            }
            if let defaultFormat = UserDefaults.standard.string(forKey: UserDefaultsKeys.exportDefaultTranscodeFormat) {
                transcodeFormat = defaultFormat
            }
            let defaultBitrate = UserDefaults.standard.integer(forKey: UserDefaultsKeys.exportDefaultTranscodeBitrate)
            if defaultBitrate > 0 { transcodeBitrate = defaultBitrate }
            return
        }
        if let data = export.folderBookmarkData,
           let (url, _) = try? PlaylistExportManager.shared.resolveBookmark(data) {
            selectedFolderURL = url
            folderBookmarkData = data
        }
        syncMode = export.syncModeEnum
        isActive = export.isActive
        transcodeFormat = export.transcodeFormat ?? ""
        transcodeBitrate = export.transcodeBitrate ?? 192
    }

    private func save() {
        guard let bookmarkData = folderBookmarkData else { return }
        let serverId = appState.activeServerId ?? ""
        let format: String? = transcodeFormat.isEmpty ? nil : transcodeFormat

        if let export = existingExport {
            export.folderBookmarkData = bookmarkData
            export.syncModeEnum = syncMode
            export.isActive = isActive
            export.transcodeFormat = format
            export.transcodeBitrate = format != nil ? transcodeBitrate : nil
        } else {
            let export = ExportedPlaylist(
                serverId: serverId,
                playlistId: playlistId,
                playlistName: playlistName,
                folderBookmarkData: bookmarkData,
                syncMode: syncMode,
                transcodeFormat: format,
                transcodeBitrate: format != nil ? transcodeBitrate : nil,
                isActive: isActive
            )
            modelContext.insert(export)
        }

        try? modelContext.save()
        dismiss()
    }
}
#endif
