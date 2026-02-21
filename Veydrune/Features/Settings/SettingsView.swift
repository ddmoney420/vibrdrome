import SwiftData
import SwiftUI

private let bitrateOptions: [(String, Int)] = [
    ("Original", 0),
    ("320 kbps", 320),
    ("256 kbps", 256),
    ("192 kbps", 192),
    ("128 kbps", 128),
]

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showServerConfig = false
    @State private var showDeleteConfirmation = false

    @AppStorage("wifiMaxBitRate") private var wifiMaxBitRate: Int = 0
    @AppStorage("cellularMaxBitRate") private var cellularMaxBitRate: Int = 0
    @AppStorage("scrobblingEnabled") private var scrobblingEnabled: Bool = true

    @Query private var downloadedSongs: [DownloadedSong]

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    if appState.isConfigured {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.serverURL)
                                .font(.body)
                            Text("User: \(appState.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Status")
                            Spacer()
                            if appState.subsonicClient.isConnected {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            } else {
                                Text("Not tested")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }

                        Button("Test Connection") {
                            Task {
                                _ = try? await appState.subsonicClient.ping()
                            }
                        }
                    }

                    Button("Configure Server") {
                        showServerConfig = true
                    }
                }

                Section("Playback Quality") {
                    Picker("WiFi", selection: $wifiMaxBitRate) {
                        ForEach(bitrateOptions, id: \.1) { name, value in
                            Text(name).tag(value)
                        }
                    }

                    #if os(iOS)
                    Picker("Cellular", selection: $cellularMaxBitRate) {
                        ForEach(bitrateOptions, id: \.1) { name, value in
                            Text(name).tag(value)
                        }
                    }
                    #endif

                    Toggle("Scrobbling", isOn: $scrobblingEnabled)
                }

                Section("Downloads") {
                    let completed = downloadedSongs.filter(\.isComplete)
                    HStack {
                        Text("Downloaded Songs")
                        Spacer()
                        Text(verbatim: "\(completed.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Storage Used")
                        Spacer()
                        Text(formatBytes(completed.reduce(0) { $0 + $1.fileSize }))
                            .foregroundStyle(.secondary)
                    }
                    if !completed.isEmpty {
                        Button("Delete All Downloads", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Client")
                        Spacer()
                        Text("veydrune")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("API Version")
                        Spacer()
                        Text("1.16.1")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showServerConfig) {
                ServerConfigView()
                    .environment(appState)
            }
            .alert("Delete All Downloads?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    DownloadManager.shared.deleteAllDownloads()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all downloaded songs from this device.")
            }
        }
    }
}
