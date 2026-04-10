import SwiftUI

// MARK: - Last.fm Auth Status

private enum LastFmAuthStatus {
    case idle, authenticating, success, failed
}

// MARK: - Bitrate Options (Player)

private let bitrateOptions: [(String, Int)] = [
    ("Original", 0),
    ("320 kbps", 320),
    ("256 kbps", 256),
    ("192 kbps", 192),
    ("128 kbps", 128),
]

// MARK: - Player Settings View

struct PlayerSettingsView: View {
    @AppStorage(UserDefaultsKeys.disableSpinningArt) private var disableSpinningArt: Bool = false
    @AppStorage(UserDefaultsKeys.enableMiniPlayerSwipe) private var enableMiniPlayerSwipe: Bool = true

    // Playback
    @AppStorage(UserDefaultsKeys.wifiMaxBitRate) private var wifiMaxBitRate: Int = 0
    @AppStorage(UserDefaultsKeys.cellularMaxBitRate) private var cellularMaxBitRate: Int = 0
    @AppStorage(UserDefaultsKeys.gaplessPlayback) private var gaplessPlayback: Bool = true
    @AppStorage(UserDefaultsKeys.crossfadeDuration) private var crossfadeDuration: Int = 0
    @AppStorage(UserDefaultsKeys.crossfadeCurve) private var crossfadeCurve: String = "linear"
    @AppStorage(UserDefaultsKeys.replayGainMode) private var replayGainMode: String = "off"
    @AppStorage(UserDefaultsKeys.eqEnabled) private var eqEnabled: Bool = false

    // Scrobbling
    @AppStorage(UserDefaultsKeys.scrobblingEnabled) private var scrobblingEnabled: Bool = true
    @AppStorage(UserDefaultsKeys.listenBrainzEnabled) private var listenBrainzEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.listenBrainzToken) private var listenBrainzToken: String = ""
    @AppStorage(UserDefaultsKeys.lastFmEnabled) private var lastFmEnabled: Bool = false
    @AppStorage(UserDefaultsKeys.lastFmApiKey) private var lastFmApiKey: String = ""
    @AppStorage(UserDefaultsKeys.lastFmSecret) private var lastFmSecret: String = ""
    @AppStorage(UserDefaultsKeys.lastFmSessionKey) private var lastFmSessionKey: String = ""
    @AppStorage(UserDefaultsKeys.lastFmUsername) private var lastFmUsername: String = ""
    @State private var lastFmPassword: String = ""
    @State private var lastFmAuthStatus: LastFmAuthStatus = .idle
    #if os(macOS)
    @AppStorage(UserDefaultsKeys.discordRPCEnabled) private var discordRPCEnabled: Bool = false
    #endif

    // Adaptive Bitrate
    @AppStorage(UserDefaultsKeys.adaptiveBitrateEnabled) private var adaptiveBitrateEnabled: Bool = false

    // Controls / Now Playing Toolbar
    @AppStorage(UserDefaultsKeys.showVolumeSlider) private var showVolumeSlider: Bool = true
    @AppStorage(UserDefaultsKeys.showAudioQualityInfo) private var showAudioQualityInfo: Bool = true
    @AppStorage(UserDefaultsKeys.showVisualizerInToolbar) private var showVisualizerInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showEQInToolbar) private var showEQInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showAirPlayInToolbar) private var showAirPlayInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showLyricsInToolbar) private var showLyricsInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.showSettingsInToolbar) private var showSettingsInToolbar: Bool = true
    @AppStorage(UserDefaultsKeys.nowPlayingToolbarOrder) private var toolbarOrderJSON: String = "[]"

    // Song Display
    @AppStorage(UserDefaultsKeys.showHeartInPlayer) private var showHeartInPlayer: Bool = true
    @AppStorage(UserDefaultsKeys.showRatingInPlayer) private var showRatingInPlayer: Bool = true
    @AppStorage(UserDefaultsKeys.showQueueInPlayer) private var showQueueInPlayer: Bool = true

    var body: some View {
        List {
            behaviorSection
            playbackSection
            scrobblingSection
            controlsSection
            songDisplaySection
        }
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle("Player")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Behavior Section

    private var behaviorSection: some View {
        Section {
            Toggle(isOn: $disableSpinningArt) {
                Label("Disable Spinning Art", systemImage: "circle.dashed")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("disableSpinningArtToggle")

            Toggle(isOn: $enableMiniPlayerSwipe) {
                Label("Swipe Gestures on Mini Player", systemImage: "hand.draw")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("enableMiniPlayerSwipeToggle")
        } header: {
            settingSectionHeader("Behavior", icon: "gearshape.fill", color: .gray)
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

            Toggle(isOn: $adaptiveBitrateEnabled) {
                Label("Adaptive Bitrate", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("adaptiveBitrateToggle")
            #endif

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

            if crossfadeDuration > 0 {
                Picker(selection: $crossfadeCurve) {
                    ForEach(CrossfadeCurve.allCases, id: \.rawValue) { curve in
                        Text(curve.label).tag(curve.rawValue)
                    }
                } label: {
                    Label("Crossfade Curve", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundColor(.primary)
                }
                .accessibilityIdentifier("crossfadeCurvePicker")
            }

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

    // MARK: - Scrobbling Section

    private var scrobblingSection: some View {
        Section {
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

            if listenBrainzEnabled {
                SecureField("User Token", text: $listenBrainzToken)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityIdentifier("listenBrainzTokenField")
            }

            Toggle(isOn: $lastFmEnabled) {
                Label("Last.fm", systemImage: "dot.radiowaves.forward")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("lastFmToggle")

            if lastFmEnabled {
                SecureField("API Key", text: $lastFmApiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityIdentifier("lastFmApiKeyField")

                SecureField("Shared Secret", text: $lastFmSecret)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityIdentifier("lastFmSecretField")

                if lastFmSessionKey.isEmpty {
                    TextField("Last.fm Username", text: $lastFmUsername)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .accessibilityIdentifier("lastFmUsernameField")

                    SecureField("Last.fm Password", text: $lastFmPassword)
                        .textContentType(.password)
                        .accessibilityIdentifier("lastFmPasswordField")

                    Button {
                        lastFmAuthStatus = .authenticating
                        Task {
                            let success = await LastFmClient.shared.authenticate(
                                username: lastFmUsername,
                                password: lastFmPassword
                            )
                            lastFmPassword = ""
                            lastFmAuthStatus = success ? .success : .failed
                            if success {
                                // Re-read the session key that was stored by LastFmClient
                                lastFmSessionKey = UserDefaults.standard.string(
                                    forKey: UserDefaultsKeys.lastFmSessionKey
                                ) ?? ""
                            }
                        }
                    } label: {
                        HStack {
                            if lastFmAuthStatus == .authenticating {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Authenticating...")
                            } else {
                                Label("Sign In", systemImage: "person.badge.key")
                            }
                        }
                    }
                    .disabled(
                        lastFmApiKey.isEmpty || lastFmSecret.isEmpty
                            || lastFmUsername.isEmpty || lastFmPassword.isEmpty
                            || lastFmAuthStatus == .authenticating
                    )
                    .accessibilityIdentifier("lastFmAuthButton")

                    if lastFmAuthStatus == .failed {
                        Text("Authentication failed. Check your credentials.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    HStack {
                        Label("Signed in as \(lastFmUsername.isEmpty ? "Last.fm user" : lastFmUsername)",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                        Spacer()
                        Button("Sign Out") {
                            lastFmSessionKey = ""
                            lastFmPassword = ""
                            lastFmAuthStatus = .idle
                        }
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    }
                    .accessibilityIdentifier("lastFmSignedInRow")
                }
            }

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
        } header: {
            settingSectionHeader("Scrobbling", icon: "music.note.tv", color: .green)
        }
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        Section {
            Toggle(isOn: $showVolumeSlider) {
                Label("Volume Slider", systemImage: "speaker.wave.2")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("showVolumeSliderToggle")

            Toggle(isOn: $showAudioQualityInfo) {
                Label("Audio Quality Info", systemImage: "waveform")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("showAudioQualityInfoToggle")

            nowPlayingToolbarSubsection
        } header: {
            settingSectionHeader("Controls", icon: "slider.horizontal.3", color: .blue)
        }
    }

    // MARK: - Now Playing Toolbar Subsection

    private var nowPlayingToolbarSubsection: some View {
        let order = NowPlayingToolbarItem.decodeOrder(from: toolbarOrderJSON)
        return Group {
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

    // MARK: - Song Display Section

    private var songDisplaySection: some View {
        Section {
            Toggle(isOn: $showHeartInPlayer) {
                Label("Show Heart/Favorite", systemImage: "heart.fill")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("showHeartInPlayerToggle")

            Toggle(isOn: $showRatingInPlayer) {
                Label("Show Star Rating", systemImage: "star.fill")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("showRatingInPlayerToggle")

            Toggle(isOn: $showQueueInPlayer) {
                Label("Show Queue Button", systemImage: "list.bullet")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("showQueueInPlayerToggle")
        } header: {
            settingSectionHeader("Song Display", icon: "music.note", color: .pink)
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
}
