import SwiftData
import SwiftUI

// MARK: - Accent Color Theme

enum AccentColorTheme: String, CaseIterable, Identifiable {
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case teal = "Teal"
    case indigo = "Indigo"
    case mint = "Mint"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .indigo: .indigo
        case .mint: .mint
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showServerConfig = false
    @State private var showServerManager = false
    @State private var showDeleteConfirmation = false
    @State private var showLogoutConfirmation = false

    @AppStorage(UserDefaultsKeys.autoDownloadFavorites) private var autoDownloadFavorites: Bool = false
    @AppStorage(UserDefaultsKeys.autoSyncPlaylists) private var autoSyncPlaylists: Bool = false
    @AppStorage(UserDefaultsKeys.downloadOverCellular) private var downloadOverCellular: Bool = false
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion: Bool = false
    @AppStorage(UserDefaultsKeys.disableVisualizer) private var disableVisualizer: Bool = false
    @AppStorage(UserDefaultsKeys.carPlayRecentCount) private var carPlayRecentCount: Int = 25
    @AppStorage(UserDefaultsKeys.carPlayShowGenres) private var carPlayShowGenres: Bool = true
    @AppStorage(UserDefaultsKeys.carPlayShowRadio) private var carPlayShowRadio: Bool = true
    @AppStorage(UserDefaultsKeys.cacheLimitBytes) private var cacheLimitBytes: Int = 0

    @Query private var downloadedSongs: [DownloadedSong]

    var body: some View {
        List {
            serverSection

            NavigationLink {
                PlayerSettingsView()
            } label: {
                Label("Player", systemImage: "play.circle.fill")
            }
            .accessibilityIdentifier("playerSettingsLink")

            NavigationLink {
                AppearanceSettingsView()
            } label: {
                Label("Appearance", systemImage: "paintbrush.fill")
            }
            .accessibilityIdentifier("appearanceSettingsLink")

            downloadsSection

            #if os(iOS)
            NavigationLink {
                TabBarSettingsView()
            } label: {
                Label("Tab Bar", systemImage: "dock.rectangle")
            }
            .accessibilityIdentifier("tabBarSettingsLink")

            carPlaySection
            #endif

            accessibilitySection
            aboutSection
        }
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle("Settings")
        .sheet(isPresented: $showServerConfig) {
            ServerConfigView()
                .environment(appState)
        }
        .sheet(isPresented: $showServerManager) {
            ServerManagerView()
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
        .alert("Sign Out?", isPresented: $showLogoutConfirmation) {
            Button("Sign Out", role: .destructive) {
                AudioEngine.shared.stop()
                appState.clearCredentials()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will disconnect from the server. You can reconnect anytime.")
        }
    }

    // MARK: - Server Section

    private var serverSection: some View {
        Section {
            if appState.isConfigured {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.green.gradient.opacity(0.8))
                            .frame(width: 44, height: 44)
                        Image(systemName: "server.rack")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        if let active = appState.servers.first(where: { $0.id == appState.activeServerId }) {
                            Text(active.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Text(appState.serverURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(appState.username)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if appState.subsonicClient.isConnected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .accessibilityLabel("Connected")
                            }
                        }
                    }

                    Spacer()

                    if appState.servers.count > 1 {
                        Text(verbatim: "\(appState.servers.count) servers")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                Button {
                    Task {
                        do {
                            _ = try await appState.subsonicClient.ping()
                        } catch {
                            // ping() already sets isConnected = false on failure
                        }
                    }
                } label: {
                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.accentColor)
                }

                Button {
                    showServerManager = true
                } label: {
                    Label("Manage Servers", systemImage: "server.rack")
                        .foregroundColor(.accentColor)
                }

                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    showServerConfig = true
                } label: {
                    Label("Add Server", systemImage: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                        .fontWeight(.medium)
                }
            }
        } header: {
            settingSectionHeader("Server", icon: "server.rack", color: .green)
        }
    }

    // MARK: - Downloads Section

    private var downloadsSection: some View {
        Section {
            let completed = downloadedSongs.filter(\.isComplete)

            HStack {
                Label("Downloaded Songs", systemImage: "arrow.down.circle.fill")
                Spacer()
                Text(verbatim: "\(completed.count)")
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
            }
            .accessibilityIdentifier("downloadedSongsRow")

            cacheStorageRow(completed: completed)

            Picker(selection: $cacheLimitBytes) {
                ForEach(CacheManager.limitOptions, id: \.1) { name, value in
                    Text(name).tag(Int(value))
                }
            } label: {
                Label("Cache Limit", systemImage: "internaldrive")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("cacheLimitPicker")

            Toggle(isOn: $autoDownloadFavorites) {
                Label("Auto-Download Favorites", systemImage: "heart.fill")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("autoDownloadFavoritesToggle")

            Toggle(isOn: $autoSyncPlaylists) {
                Label("Auto-Sync Playlists", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("autoSyncPlaylistsToggle")

            #if os(iOS)
            Toggle(isOn: $downloadOverCellular) {
                Label("Download Over Cellular", systemImage: "cellularbars")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("downloadOverCellularToggle")
            #endif

            if !completed.isEmpty {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete All Downloads", systemImage: "trash")
                }
            }
        } header: {
            settingSectionHeader("Downloads", icon: "arrow.down.circle.fill", color: .cyan)
        }
    }

    // MARK: - CarPlay Section

    #if os(iOS)
    private var carPlaySection: some View {
        Section {
            Picker(selection: $carPlayRecentCount) {
                Text("10").tag(10)
                Text("25").tag(25)
                Text("50").tag(50)
            } label: {
                Label("Recent Albums", systemImage: "clock.fill")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("carPlayRecentAlbumsPicker")

            Toggle(isOn: $carPlayShowGenres) {
                Label("Show Genres", systemImage: "guitars.fill")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("carPlayShowGenresToggle")

            Toggle(isOn: $carPlayShowRadio) {
                Label("Show Radio", systemImage: "radio.fill")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("carPlayShowRadioToggle")
        } header: {
            settingSectionHeader("CarPlay", icon: "car.fill", color: .blue)
        }
    }
    #endif

    // MARK: - Accessibility Section

    private var accessibilitySection: some View {
        Section {
            Toggle(isOn: $reduceMotion) {
                Label("Reduce Motion", systemImage: "figure.walk")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("reduceMotionToggle")

            Toggle(isOn: $disableVisualizer) {
                Label("Disable Visualizer", systemImage: "eye.slash")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("disableVisualizerToggle")

        } header: {
            settingSectionHeader("Accessibility", icon: "accessibility", color: .indigo)
        } footer: {
            if disableVisualizer {
                Text("The visualizer button is hidden from the player. Disable this to restore it.")
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack(spacing: 14) {
                appIconImage
                    .resizable()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Vibrdrome")
                        .font(.headline)
                    Text("Music player for Navidrome")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            infoRow(
                "Version",
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
                icon: "info.circle.fill",
                color: .gray
            )
            infoRow("API Version", value: "1.16.1", icon: "number.circle.fill", color: .gray)
            offlineQueueStatus

            #if DEBUG
            NavigationLink {
                DebugView()
                    .environment(appState)
            } label: {
                Label("Debug Tools", systemImage: "ladybug.fill")
                    .foregroundColor(.red)
            }
            #endif
        } header: {
            settingSectionHeader("About", icon: "info.circle.fill", color: .gray)
        }
    }

    // MARK: - Cache Storage Row

    private func cacheStorageRow(completed: [DownloadedSong]) -> some View {
        let used = completed.reduce(Int64(0)) { $0 + $1.fileSize }
        let limit = Int64(cacheLimitBytes)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Storage Used", systemImage: "externaldrive.fill")
                Spacer()
                if limit > 0 {
                    Text("\(formatBytes(used)) / \(formatBytes(limit))")
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                } else {
                    Text(formatBytes(used))
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                }
            }
            if limit > 0 {
                ProgressView(value: Double(used), total: Double(limit))
                    .tint(used > limit ? .red : .accentColor)
            }
        }
    }

    // MARK: - Offline Queue Status

    @ViewBuilder
    private var offlineQueueStatus: some View {
        let queue = OfflineActionQueue.shared
        let pending = queue.pendingCount
        let failed = queue.failedCount

        if pending > 0 || failed > 0 {
            if pending > 0 {
                Button {
                    Task { await queue.flushPending() }
                } label: {
                    HStack {
                        Label("Sync \(pending) Pending", systemImage: "arrow.clockwise")
                        Spacer()
                        Text(verbatim: "\(pending)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if failed > 0 {
                Button {
                    Task { await queue.retryFailed() }
                } label: {
                    HStack {
                        Label("Retry \(failed) Failed", systemImage: "arrow.counterclockwise")
                        Spacer()
                        Text(verbatim: "\(failed)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Button(role: .destructive) {
                    queue.clearFailed()
                } label: {
                    Label("Clear Failed", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Helpers

    private func settingSectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(title)
        }
        .accessibilityIdentifier("sectionHeader_\(title)")
    }

    private func infoRow(_ label: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
        }
    }

    private var appIconImage: Image {
        Image("AppIconImage")
    }
}
