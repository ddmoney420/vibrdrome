#if os(macOS)
import SwiftUI

struct PlaylistExportSettingsView: View {
    @AppStorage(UserDefaultsKeys.exportDefaultSyncMode) private var defaultPlaylistExportSyncModeRaw = PlaylistExportSyncMode.addOnly.rawValue
    @AppStorage(UserDefaultsKeys.exportDefaultTranscodeFormat) private var defaultTranscodeFormat = ""
    @AppStorage(UserDefaultsKeys.exportDefaultTranscodeBitrate) private var defaultTranscodeBitrate = 192
    @AppStorage(UserDefaultsKeys.exportFfmpegPath) private var ffmpegPath = ""
    @AppStorage(UserDefaultsKeys.exportAutoSyncOnForeground) private var autoSyncOnForeground = true

    @State private var defaultFolderURL: URL?
    @State private var ffmpegTestResult: Bool?
    @State private var isTestingFfmpeg = false

    private var defaultPlaylistExportSyncMode: PlaylistExportSyncMode {
        get { PlaylistExportSyncMode(rawValue: defaultPlaylistExportSyncModeRaw) ?? .addOnly }
        nonmutating set { defaultPlaylistExportSyncModeRaw = newValue.rawValue }
    }

    var body: some View {
        Form {
            Section("Default Export Folder") {
                HStack {
                    if let url = defaultFolderURL {
                        Text(url.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No default folder")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Choose…") {
                        Task { await pickDefaultFolder() }
                    }
                }
            }

            Section("Sync") {
                Picker("Default Mode", selection: Binding(
                    get: { defaultPlaylistExportSyncMode },
                    set: { defaultPlaylistExportSyncModeRaw = $0.rawValue }
                )) {
                    ForEach(PlaylistExportSyncMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle("Auto-sync exported playlists on launch", isOn: $autoSyncOnForeground)
            }

            Section("Transcode Defaults") {
                Picker("Default Format", selection: $defaultTranscodeFormat) {
                    Text("Original (no transcode)").tag("")
                    Text("MP3").tag("mp3")
                    Text("AAC").tag("aac")
                    Text("Opus").tag("opus")
                    Text("FLAC").tag("flac")
                }
                .pickerStyle(.menu)
                if !defaultTranscodeFormat.isEmpty {
                    HStack {
                        Text("Default Bitrate (kbps)")
                        TextField("192", value: $defaultTranscodeBitrate, format: .number)
                            .frame(width: 80)
                    }
                }
            }

            Section("ffmpeg") {
                HStack {
                    TextField("/usr/local/bin/ffmpeg", text: $ffmpegPath)
                    Button("Locate…") {
                        Task { await locateFfmpeg() }
                    }
                    Button("Test") {
                        Task { await testFfmpeg() }
                    }
                    .disabled(isTestingFfmpeg)
                }
                if isTestingFfmpeg {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Testing…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let result = ffmpegTestResult {
                    Label(
                        result ? "ffmpeg found and working." : "ffmpeg not found or failed.",
                        systemImage: result ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(result ? .green : .red)
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Playlist Export")
        .onAppear { loadDefaultFolder() }
    }

    private func pickDefaultFolder() async {
        guard let url = await PlaylistExportManager.shared.pickFolder() else { return }
        guard let data = try? PlaylistExportManager.shared.bookmarkData(for: url) else { return }
        UserDefaults.standard.set(data, forKey: UserDefaultsKeys.exportDefaultFolderBookmark)
        defaultFolderURL = url
    }

    private func loadDefaultFolder() {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.exportDefaultFolderBookmark),
              let (url, _) = try? PlaylistExportManager.shared.resolveBookmark(data) else { return }
        defaultFolderURL = url
    }

    private func locateFfmpeg() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.prompt = "Select ffmpeg"
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    DispatchQueue.main.async { self.ffmpegPath = url.path }
                }
                continuation.resume()
            }
        }
    }

    private func testFfmpeg() async {
        let path = ffmpegPath.isEmpty ? "/usr/local/bin/ffmpeg" : ffmpegPath
        isTestingFfmpeg = true
        ffmpegTestResult = nil
        let result = await PlaylistExportManager.shared.testFfmpeg(path: path)
        ffmpegTestResult = result
        isTestingFfmpeg = false
    }
}
#endif
