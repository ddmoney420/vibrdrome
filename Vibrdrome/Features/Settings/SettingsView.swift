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

// MARK: - Bitrate Options

private let bitrateOptions: [(String, Int)] = [
    ("Original", 0),
    ("320 kbps", 320),
    ("256 kbps", 256),
    ("192 kbps", 192),
    ("128 kbps", 128),
]

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showServerConfig = false
    @State private var showServerManager = false
    @State private var showDeleteConfirmation = false
    @State private var showLogoutConfirmation = false

    @AppStorage(UserDefaultsKeys.wifiMaxBitRate) private var wifiMaxBitRate: Int = 0
    @AppStorage(UserDefaultsKeys.cellularMaxBitRate) private var cellularMaxBitRate: Int = 0
    @AppStorage(UserDefaultsKeys.scrobblingEnabled) private var scrobblingEnabled: Bool = true
    @AppStorage(UserDefaultsKeys.listenBrainzEnabled) private var listenBrainzEnabled: Bool = false
    #if os(macOS)
    @AppStorage(UserDefaultsKeys.discordRPCEnabled) private var discordRPCEnabled: Bool = false
    #endif
    @AppStorage(UserDefaultsKeys.listenBrainzToken) private var listenBrainzToken: String = ""
    @AppStorage(UserDefaultsKeys.appColorScheme) private var appColorScheme: String = "system"
    @AppStorage(UserDefaultsKeys.accentColorTheme) private var accentColorTheme: String = "blue"
    @AppStorage(UserDefaultsKeys.gaplessPlayback) private var gaplessPlayback: Bool = true
    @AppStorage(UserDefaultsKeys.replayGainMode) private var replayGainMode: String = "off"
    @AppStorage(UserDefaultsKeys.crossfadeDuration) private var crossfadeDuration: Int = 0
    @AppStorage(UserDefaultsKeys.eqEnabled) private var eqEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.autoDownloadFavorites) private var autoDownloadFavorites: Bool = false
    @AppStorage(UserDefaultsKeys.autoSyncPlaylists) private var autoSyncPlaylists: Bool = false
    @AppStorage(UserDefaultsKeys.downloadOverCellular) private var downloadOverCellular: Bool = false
    @AppStorage(UserDefaultsKeys.textSize) private var textSizePref: String = "default"
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion: Bool = false
    @AppStorage(UserDefaultsKeys.boldText) private var boldText: Bool = false
    @AppStorage(UserDefaultsKeys.disableVisualizer) private var disableVisualizer: Bool = false
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private var showAlbumArtInLists: Bool = true
    @AppStorage(UserDefaultsKeys.showVisualizerInToolbar) private var showVisualizerInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showEQInToolbar) private var showEQInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showAirPlayInToolbar) private var showAirPlayInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showLyricsInToolbar) private var showLyricsInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showSettingsInToolbar) private var showSettingsInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showSearchTab) private var showSearchTab: Bool = true
    @AppStorage(UserDefaultsKeys.showPlaylistsTab) private var showPlaylistsTab: Bool = true
    @AppStorage(UserDefaultsKeys.showRadioTab) private var showRadioTab: Bool = true
    @AppStorage(UserDefaultsKeys.carPlayRecentCount) private var carPlayRecentCount: Int = 25
    @AppStorage(UserDefaultsKeys.carPlayShowGenres) private var carPlayShowGenres: Bool = true
    @AppStorage(UserDefaultsKeys.carPlayShowRadio) private var carPlayShowRadio: Bool = true
    @AppStorage(UserDefaultsKeys.cacheLimitBytes) private var cacheLimitBytes: Int = 0

    @Query private var downloadedSongs: [DownloadedSong]

    var body: some View {
        List {
            serverSection
            playbackSection
            downloadsSection
            appearanceSection
            tabBarSection
            #if os(iOS)
            nowPlayingToolbarSection
            carPlaySection
            #endif
            accessibilitySection
            aboutSection
        }
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

    // MARK: - Playback Section

    private var playbackSection: some View {
        Section {
            Picker(selection: $wifiMaxBitRate) {
                ForEach(bitrateOptions, id: \.1) { name, value in
                    Text(name).tag(value)
                }
            } label: {
                Label("WiFi Quality", systemImage: "wifi")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("wifiQualityPicker")

            #if os(iOS)
            Picker(selection: $cellularMaxBitRate) {
                ForEach(bitrateOptions, id: \.1) { name, value in
                    Text(name).tag(value)
                }
            } label: {
                Label("Cellular Quality", systemImage: "cellularbars")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("cellularQualityPicker")
            #endif

            Toggle(isOn: $scrobblingEnabled) {
                Label("Scrobbling", systemImage: "music.note.tv")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("scrobblingToggle")

            Toggle(isOn: $listenBrainzEnabled) {
                Label("ListenBrainz", systemImage: "dot.radiowaves.right")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("listenBrainzToggle")

            #if os(macOS)
            Toggle(isOn: $discordRPCEnabled) {
                Label("Discord Rich Presence", systemImage: "gamecontroller.fill")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("discordRPCToggle")
            .onChange(of: discordRPCEnabled) { _, newValue in
                Task {
                    if !newValue {
                        await DiscordRPCClient.shared.clearPresence()
                        await DiscordRPCClient.shared.disconnect()
                    }
                }
            }
            #endif

            if listenBrainzEnabled {
                SecureField("User Token", text: $listenBrainzToken)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityIdentifier("listenBrainzTokenField")
            }

            Toggle(isOn: $gaplessPlayback) {
                Label("Gapless Playback", systemImage: "waveform.path")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("gaplessPlaybackToggle")

            Picker(selection: $crossfadeDuration) {
                Text("Off").tag(0)
                Text("2s").tag(2)
                Text("5s").tag(5)
                Text("8s").tag(8)
                Text("12s").tag(12)
            } label: {
                Label("Crossfade", systemImage: "waveform.path.ecg")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("crossfadePicker")

            Picker(selection: $replayGainMode) {
                Text("Off").tag("off")
                Text("Track").tag("track")
                Text("Album").tag("album")
            } label: {
                Label("ReplayGain", systemImage: "speaker.wave.2")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("replayGainPicker")

            Toggle(isOn: $eqEnabled) {
                Label("Equalizer", systemImage: "slider.vertical.3")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("equalizerToggle")
            .onChange(of: eqEnabled) { _, newValue in
                AudioEngine.shared.applyEQToggle(enabled: newValue)
            }

            NavigationLink {
                EQView()
            } label: {
                Label("EQ Settings", systemImage: "slider.horizontal.3")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("eqSettingsLink")
        } header: {
            settingSectionHeader("Playback", icon: "play.circle.fill", color: .purple)
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

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            Picker(selection: $appColorScheme) {
                Text("System").tag("system")
                Text("Dark").tag("dark")
                Text("Light").tag("light")
            } label: {
                Label("Theme", systemImage: "circle.lefthalf.filled")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("themePicker")

            // Accent color picker
            VStack(alignment: .leading, spacing: 10) {
                Label("Accent Color", systemImage: "paintpalette.fill")

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 36), spacing: 10)
                ], spacing: 10) {
                    ForEach(AccentColorTheme.allCases) { theme in
                        Button {
                            accentColorTheme = theme.rawValue
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(theme.color.gradient)
                                    .frame(width: 32, height: 32)
                                if accentColorTheme == theme.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(theme.rawValue)
                        .accessibilityValue(accentColorTheme == theme.rawValue ? "Selected" : "")
                    }
                }
                .padding(.vertical, 4)
            }

            Toggle(isOn: $showAlbumArtInLists) {
                Label("Album Art in Lists", systemImage: "photo")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("albumArtInListsToggle")
        } header: {
            settingSectionHeader("Appearance", icon: "paintbrush.fill", color: .orange)
        }
    }

    // MARK: - Now Playing Toolbar Section

    @AppStorage(UserDefaultsKeys.nowPlayingToolbarOrder) private var toolbarOrderJSON: String = "[]"

    private var nowPlayingToolbarSection: some View {
        let order = NowPlayingToolbarItem.decodeOrder(from: toolbarOrderJSON)
        return Section {
            ForEach(order) { item in
                Toggle(isOn: toolbarBinding(for: item)) {
                    Label(toolbarItemLabel(for: item), systemImage: toolbarItemIcon(for: item))
                        .foregroundColor(.primary)
                }
                .accessibilityIdentifier("showToolbar_\(item.rawValue)")
            }
            .onMove { source, destination in
                var mutable = order
                mutable.move(fromOffsets: source, toOffset: destination)
                toolbarOrderJSON = NowPlayingToolbarItem.encodeOrder(mutable)
            }
        } header: {
            settingSectionHeader("Now Playing Toolbar", icon: "rectangle.dock.bottom", color: .purple)
        } footer: {
            Text("Toggle visibility and drag to reorder toolbar icons.")
        }
    }

    private func toolbarBinding(for item: NowPlayingToolbarItem) -> Binding<Bool> {
        switch item {
        case .visualizer: return $showVisualizerInToolbar
        case .eq: return $showEQInToolbar
        case .airplay: return $showAirPlayInToolbar
        case .lyrics: return $showLyricsInToolbar
        case .settings: return $showSettingsInToolbar
        }
    }

    private func toolbarItemLabel(for item: NowPlayingToolbarItem) -> String {
        switch item {
        case .visualizer: return "Visualizer"
        case .eq: return "Equalizer"
        case .airplay: return "AirPlay"
        case .lyrics: return "Lyrics"
        case .settings: return "Quick Settings"
        }
    }

    private func toolbarItemIcon(for item: NowPlayingToolbarItem) -> String {
        switch item {
        case .visualizer: return "waveform.path"
        case .eq: return "slider.vertical.3"
        case .airplay: return "airplayaudio"
        case .lyrics: return "quote.bubble"
        case .settings: return "gearshape"
        }
    }

    // MARK: - Tab Bar Section

    private var tabBarSection: some View {
        Section {
            Toggle(isOn: $showSearchTab) {
                Label("Search", systemImage: "magnifyingglass")
                    .foregroundColor(.primary)
            }
            Toggle(isOn: $showPlaylistsTab) {
                Label("Playlists", systemImage: "music.note.list")
                    .foregroundColor(.primary)
            }
            Toggle(isOn: $showRadioTab) {
                Label("Radio", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.primary)
            }
        } header: {
            settingSectionHeader("Tab Bar", icon: "dock.rectangle", color: .teal)
        } footer: {
            Text("Library and Settings tabs are always shown.")
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
            Picker(selection: $textSizePref) {
                Text("Small").tag("small")
                Text("Default").tag("default")
                Text("Large").tag("large")
                Text("Extra Large").tag("xlarge")
            } label: {
                Label("Text Size", systemImage: "textformat.size")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("textSizePicker")

            Toggle(isOn: $boldText) {
                Label("Bold Text", systemImage: "bold")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("boldTextToggle")

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
