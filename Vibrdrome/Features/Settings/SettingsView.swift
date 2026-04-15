import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showDeleteConfirmation = false
    @State private var showLogoutConfirmation = false
    @State private var showBackupShare = false
    @State private var backupFileURL: URL?
    @State private var showRestoreImporter = false
    @State private var backupRestoreMessage: String?
    @State private var showBackupRestoreAlert = false

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

            #if os(macOS)
            NavigationLink {
                LayoutSettingsView()
            } label: {
                Label("Layout", systemImage: "rectangle.3.group")
            }
            .accessibilityIdentifier("layoutSettingsLink")
            #endif

            downloadsSection
            librarySyncSection

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
            backupRestoreSection
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
        #if os(iOS)
        .sheet(isPresented: $showBackupShare) {
            if let backupFileURL {
                SettingsShareSheet(activityItems: [backupFileURL])
            }
        }
        #endif
        .fileImporter(
            isPresented: $showRestoreImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    restoreSettings(from: data)
                    backupRestoreMessage = "Settings restored successfully. Some changes may require restarting the app."
                } else {
                    backupRestoreMessage = "Failed to read the backup file."
                }
                showBackupRestoreAlert = true
            case .failure(let error):
                backupRestoreMessage = "Import failed: \(error.localizedDescription)"
                showBackupRestoreAlert = true
            }
        }
        .alert("Backup & Restore", isPresented: $showBackupRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupRestoreMessage ?? "")
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

                NavigationLink {
                    ServerManagerView(embedded: true)
                        .environment(appState)
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

    // MARK: - Library Sync Section

    private var librarySyncSection: some View {
        Section {
            HStack {
                Label("Library Sync", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                Spacer()
                if appState.librarySyncManager.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else if let lastSync = appState.librarySyncManager.lastSyncDate {
                    Text(lastSync, style: .relative)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("ago")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Never")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            if let progress = appState.librarySyncManager.syncProgress {
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let syncError = appState.librarySyncManager.syncError {
                Text(syncError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Live sync stats during sync
            if let stats = appState.librarySyncManager.lastSyncStats,
               appState.librarySyncManager.isSyncing {
                HStack(spacing: 12) {
                    Label("+\(stats.albumsAdded + stats.artistsAdded + stats.songsAdded)", systemImage: "plus.circle")
                        .foregroundStyle(.green)
                    Label("~\(stats.albumsUpdated + stats.artistsUpdated + stats.songsUpdated)", systemImage: "pencil.circle")
                        .foregroundStyle(.orange)
                    Label("-\(stats.albumsRemoved + stats.artistsRemoved + stats.songsRemoved)", systemImage: "minus.circle")
                        .foregroundStyle(.red)
                }
                .font(.caption)
            }

            // Last sync result summary
            if let stats = appState.librarySyncManager.lastSyncStats,
               !appState.librarySyncManager.isSyncing,
               stats.totalChanges > 0 {
                HStack {
                    Text("Last sync: \(stats.totalChanges) changes in \(String(format: "%.1f", stats.duration))s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    Task {
                        await appState.librarySyncManager.sync(
                            client: appState.subsonicClient,
                            container: PersistenceController.shared.container
                        )
                    }
                } label: {
                    Label(
                        appState.librarySyncManager.isSyncing ? "Syncing…" : "Full Sync",
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(appState.librarySyncManager.isSyncing)
                .accessibilityIdentifier("librarySyncButton")

                Spacer()

                Button {
                    Task {
                        await appState.librarySyncManager.incrementalSync(
                            client: appState.subsonicClient,
                            container: PersistenceController.shared.container
                        )
                    }
                } label: {
                    Label("Quick Sync", systemImage: "bolt.circle")
                }
                .disabled(appState.librarySyncManager.isSyncing)
                .accessibilityIdentifier("incrementalSyncButton")
            }

            NavigationLink {
                SyncHistoryView()
            } label: {
                Label("Sync History", systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("syncHistoryLink")

            #if os(iOS)
            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: UserDefaultsKeys.backgroundSyncEnabled) },
                set: { newValue in
                    UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.backgroundSyncEnabled)
                    if newValue {
                        BackgroundSyncScheduler.shared.scheduleRefresh()
                        BackgroundSyncScheduler.shared.scheduleFullSync()
                    } else {
                        BackgroundSyncScheduler.shared.cancelAll()
                    }
                }
            )) {
                Label("Background Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            #endif

            Picker(selection: Binding(
                get: {
                    let val = UserDefaults.standard.integer(forKey: UserDefaultsKeys.syncPollingInterval)
                    return [5, 15, 30, 60].contains(val) ? val : 15
                },
                set: { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.syncPollingInterval) }
            )) {
                Text("5 min").tag(5)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("60 min").tag(60)
            } label: {
                Label("Check for Changes", systemImage: "timer")
            }
        } header: {
            settingSectionHeader("Library", icon: "books.vertical.fill", color: .purple)
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

    // MARK: - Backup & Restore Section

    private var backupRestoreSection: some View {
        Section {
            Button {
                guard let data = backupSettings() else { return }
                let dateStr = formattedDateForFilename()
                let fileName = "vibrdrome-backup-\(dateStr).json"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try? data.write(to: tempURL)
                backupFileURL = tempURL
                showBackupShare = true
            } label: {
                Label("Backup Settings", systemImage: "square.and.arrow.up")
                    .foregroundColor(.accentColor)
            }
            .accessibilityIdentifier("backupSettingsButton")

            Button {
                showRestoreImporter = true
            } label: {
                Label("Restore Settings", systemImage: "square.and.arrow.down")
                    .foregroundColor(.accentColor)
            }
            .accessibilityIdentifier("restoreSettingsButton")
        } header: {
            settingSectionHeader("Backup & Restore", icon: "externaldrive.fill.badge.timemachine", color: .orange)
        } footer: {
            Text("""
            Backup: tap to share your settings as a file. \
            Save it to Files or send to yourself.
            Restore: tap to import a previously saved backup.
            """)
        }
    }

    private static let backupKeys: [String] = [
        UserDefaultsKeys.gaplessPlayback,
        UserDefaultsKeys.crossfadeDuration,
        UserDefaultsKeys.crossfadeCurve,
        UserDefaultsKeys.replayGainMode,
        UserDefaultsKeys.scrobblingEnabled,
        UserDefaultsKeys.eqEnabled,
        UserDefaultsKeys.eqCurrentPresetId,
        UserDefaultsKeys.eqCurrentGains,
        UserDefaultsKeys.customEQPresets,
        UserDefaultsKeys.autoDownloadFavorites,
        UserDefaultsKeys.downloadOverCellular,
        UserDefaultsKeys.cacheLimitBytes,
        UserDefaultsKeys.wifiMaxBitRate,
        UserDefaultsKeys.cellularMaxBitRate,
        UserDefaultsKeys.carPlayShowRadio,
        UserDefaultsKeys.carPlayShowGenres,
        UserDefaultsKeys.carPlayRecentCount,
        UserDefaultsKeys.appColorScheme,
        UserDefaultsKeys.accentColorTheme,
        UserDefaultsKeys.largerText,
        UserDefaultsKeys.textSize,
        UserDefaultsKeys.autoSyncPlaylists,
        UserDefaultsKeys.showSearchTab,
        UserDefaultsKeys.showPlaylistsTab,
        UserDefaultsKeys.showRadioTab,
        UserDefaultsKeys.boldText,
        UserDefaultsKeys.reduceMotion,
        UserDefaultsKeys.disableVisualizer,
        UserDefaultsKeys.showAlbumArtInLists,
        UserDefaultsKeys.visualizerPreset,
        UserDefaultsKeys.showVisualizerInToolbar,
        UserDefaultsKeys.showEQInToolbar,
        UserDefaultsKeys.showAirPlayInToolbar,
        UserDefaultsKeys.showLyricsInToolbar,
        UserDefaultsKeys.showSettingsInToolbar,
        UserDefaultsKeys.nowPlayingToolbarOrder,
        UserDefaultsKeys.discordRPCEnabled,
        UserDefaultsKeys.listenBrainzEnabled,
        UserDefaultsKeys.disableSpinningArt,
        UserDefaultsKeys.rememberPlaybackPosition,
        UserDefaultsKeys.enableMiniPlayerSwipe,
        UserDefaultsKeys.showVolumeSlider,
        UserDefaultsKeys.showAudioQualityInfo,
        UserDefaultsKeys.showHeartInPlayer,
        UserDefaultsKeys.showRatingInPlayer,
        UserDefaultsKeys.showQueueInPlayer,
        UserDefaultsKeys.enableLiquidGlass,
        UserDefaultsKeys.enableMiniPlayerTint,
        UserDefaultsKeys.albumBackgroundStyle,
        UserDefaultsKeys.settingsInNavBar,
        UserDefaultsKeys.showDownloadsTab,
        UserDefaultsKeys.tabBarOrder,
        UserDefaultsKeys.libraryLayout,
    ]

    private func backupSettings() -> Data? {
        var backup: [String: Any] = [:]
        for key in Self.backupKeys {
            guard let value = UserDefaults.standard.object(forKey: key) else { continue }
            // Only include JSON-safe types
            switch value {
            case is String, is Int, is Double, is Float, is Bool:
                backup[key] = value
            case let array as [Any] where JSONSerialization.isValidJSONObject(array):
                backup[key] = array
            case let dict as [String: Any] where JSONSerialization.isValidJSONObject(dict):
                backup[key] = dict
            default:
                // Skip non-serializable values (Data, etc.)
                continue
            }
        }
        backup["_backupDate"] = ISO8601DateFormatter().string(from: Date())
        backup["_appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        return try? JSONSerialization.data(withJSONObject: backup, options: [.prettyPrinted, .sortedKeys])
    }

    private func performBackup() {
        guard let data = backupSettings() else {
            backupRestoreMessage = "Failed to create backup."
            showBackupRestoreAlert = true
            return
        }
        let fileName = "vibrdrome-settings-\(formattedDateForFilename()).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL)
            backupFileURL = tempURL
            backupRestoreMessage = "Backup created. Use the share button to export."
            showBackupRestoreAlert = true
        } catch {
            backupRestoreMessage = "Failed to write backup file: \(error.localizedDescription)"
            showBackupRestoreAlert = true
        }
    }

    private func restoreSettings(from data: Data) {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            backupRestoreMessage = "Invalid backup file format."
            showBackupRestoreAlert = true
            return
        }
        for (key, value) in dict where !key.hasPrefix("_") {
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    private func formattedDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
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

// MARK: - Share Sheet (iOS)

#if os(iOS)
import UIKit

private struct SettingsShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
