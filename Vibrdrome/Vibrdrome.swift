import KeychainAccess
import SwiftUI
import SwiftData
import Nuke
import os.log

// D1: AppDelegate for background URLSession reconnection
#if os(iOS)
class VibrdromeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Force lazy session init so delegate callbacks are delivered
        _ = DownloadManager.shared
        DownloadManager.shared.completionHandler = completionHandler
    }
}
#elseif os(macOS)
class VibrdromeMacDelegate: NSObject, NSApplicationDelegate {
    private var eventMonitor: Any?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent multiple instances
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if runningApps.count > 1 {
            // Another instance is already running — activate it and quit this one
            for app in runningApps where app != NSRunningApplication.current {
                app.activate()
            }
            NSApp.terminate(nil)
        }

        // Intercept CMD+F before AppKit's responder chain (performFindPanelAction:) claims it
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  event.modifierFlags.isDisjoint(with: [.shift, .option, .control]),
                  event.charactersIgnoringModifiers == "f" else {
                return event
            }
            NotificationCenter.default.post(name: .focusSearchBar, object: nil)
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
#endif

@main
struct VibrdromeApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(VibrdromeAppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(VibrdromeMacDelegate.self) var appDelegate
    #endif
    @State private var appState = AppState.shared
    @AppStorage(UserDefaultsKeys.appColorScheme) private var appColorScheme: String = "system"
    @AppStorage(UserDefaultsKeys.accentColorTheme) private var accentColorTheme: String = "blue"
    @AppStorage(UserDefaultsKeys.textSize) private var textSizePref: String = "default"
    @AppStorage(UserDefaultsKeys.boldText) private var boldText: Bool = false
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion: Bool = false
    private let persistenceController = PersistenceController.shared

    init() {
        Self.migrateCredentialsToKeychain()
    }

    /// One-time migration: move Last.fm/ListenBrainz credentials from UserDefaults to Keychain.
    /// Safe to call multiple times. Only migrates if UserDefaults has a value and Keychain does not.
    private static func migrateCredentialsToKeychain() {
        let defaults = UserDefaults.standard
        let lastFmKC = Keychain(service: "com.vibrdrome.lastfm")
        let lbKC = Keychain(service: "com.vibrdrome.listenbrainz")

        let migrations: [(key: String, keychain: Keychain, keychainKey: String)] = [
            (UserDefaultsKeys.lastFmApiKey, lastFmKC, "apiKey"),
            (UserDefaultsKeys.lastFmSecret, lastFmKC, "secret"),
            (UserDefaultsKeys.lastFmSessionKey, lastFmKC, "sessionKey"),
            (UserDefaultsKeys.listenBrainzToken, lbKC, "token"),
        ]

        for m in migrations {
            if let value = defaults.string(forKey: m.key), !value.isEmpty, m.keychain[m.keychainKey] == nil {
                m.keychain[m.keychainKey] = value
                defaults.removeObject(forKey: m.key)
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch appColorScheme {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    private var accentColor: Color {
        (AccentColorTheme(rawValue: accentColorTheme) ?? .blue).color
    }

    private var textSize: DynamicTypeSize {
        switch textSizePref {
        case "small": .medium
        case "large": .xLarge
        case "xlarge": .xxxLarge
        default: .large
        }
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            MacContentView()
                .frame(minWidth: 1000, minHeight: 560)
                .environment(appState)
                .modelContainer(persistenceController.container)
                .preferredColorScheme(colorScheme)
                .tint(accentColor)
                .dynamicTypeSize(textSize)
                .environment(\.legibilityWeight, boldText ? .bold : .regular)
                .onAppear {
                    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(name: "com.vibrdrome.images"))
                    RemoteCommandManager.shared.setup()
                    DownloadManager.shared.resumeIncompleteDownloads()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
            #else
            ContentView()
                .environment(appState)
                .modelContainer(persistenceController.container)
                .preferredColorScheme(colorScheme)
                .tint(accentColor)
                .dynamicTypeSize(textSize)
                .environment(\.legibilityWeight, boldText ? .bold : .regular)
                .onAppear {
                    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(name: "com.vibrdrome.images"))
                    RemoteCommandManager.shared.setup()
                    DownloadManager.shared.resumeIncompleteDownloads()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Playback") {
                PlaybackCommands()
            }
            CommandMenu("Navigate") {
                Button("Go to Search") {
                    NotificationCenter.default.post(name: .navigateToSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Focus Search") {
                    NotificationCenter.default.post(name: .focusSearchBar, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Window("Now Playing", id: "now-playing") {
            NowPlayingView()
                .environment(appState)
                .modelContainer(persistenceController.container)
                .preferredColorScheme(colorScheme)
                .tint(accentColor)
        }
        .defaultSize(width: 500, height: 700)

        Window("Visualizer", id: "visualizer") {
            VisualizerView()
                .environment(appState)
                .modelContainer(persistenceController.container)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 700, height: 500)

        Window("Mini Player", id: "mini-player") {
            PopOutPlayerView()
                .environment(appState)
                .modelContainer(persistenceController.container)
                .preferredColorScheme(colorScheme)
                .tint(accentColor)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 320, height: 88)
        .windowResizability(.contentSize)

        Settings {
            NavigationStack {
                SettingsView()
            }
            .environment(appState)
            .modelContainer(persistenceController.container)
            .preferredColorScheme(colorScheme)
            .tint(accentColor)
            .frame(width: 500, height: 600)
        }
        #endif
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "vibrdrome" else { return }
        let logger = Logger(subsystem: "com.vibrdrome.app", category: "DeepLink")
        let host = url.host ?? ""
        let path = url.pathComponents.dropFirst() // Remove leading "/"

        logger.info("Deep link received: \(url.absoluteString)")

        switch host {
        case "album":
            if let albumId = path.first {
                appState.pendingNavigation = .album(id: String(albumId))
            }
        case "artist":
            if let artistId = path.first {
                appState.pendingNavigation = .artist(id: String(artistId))
            }
        case "playlist":
            if let playlistId = path.first {
                appState.pendingNavigation = .playlist(id: String(playlistId))
            }
        case "song":
            if let songId = path.first {
                Task {
                    do {
                        let song = try await appState.subsonicClient.getSong(id: String(songId))
                        AudioEngine.shared.play(song: song)
                    } catch {
                        logger.error("Failed to play song from deep link: \(error)")
                    }
                }
            }
        default:
            logger.warning("Unknown deep link host: \(host)")
        }
    }
}

#if os(macOS)
private struct PlaybackCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("Play/Pause") {
                AudioEngine.shared.togglePlayPause()
            }
            .keyboardShortcut("p", modifiers: .command)

            Button("Play/Pause") {
                AudioEngine.shared.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button("Next Track") {
                AudioEngine.shared.next()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Button("Previous Track") {
                AudioEngine.shared.previous()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Seek Forward 10s") {
                let engine = AudioEngine.shared
                engine.seek(to: min(engine.duration, engine.currentTime + 10))
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])

            Button("Seek Backward 10s") {
                let engine = AudioEngine.shared
                engine.seek(to: max(0, engine.currentTime - 10))
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

            Divider()

            Button("Shuffle") {
                AudioEngine.shared.toggleShuffle()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Repeat") {
                AudioEngine.shared.cycleRepeatMode()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Volume Up") {
                AudioEngine.shared.volume = min(1, AudioEngine.shared.volume + 0.1)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Volume Down") {
                AudioEngine.shared.volume = max(0, AudioEngine.shared.volume - 0.1)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
        }
        Group {
            Divider()

            Button("Toggle Favorite") {
                Self.toggleFavorite()
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Show Visualizer") {
                openWindow(id: "visualizer")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Divider()

            Button("Rate ★") { Self.setRating(1) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Rate ★★") { Self.setRating(2) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Rate ★★★") { Self.setRating(3) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Rate ★★★★") { Self.setRating(4) }
                .keyboardShortcut("4", modifiers: .command)
            Button("Rate ★★★★★") { Self.setRating(5) }
                .keyboardShortcut("5", modifiers: .command)
            Button("Clear Rating") { Self.setRating(0) }
                .keyboardShortcut("0", modifiers: .command)
        }
    }

    private static func toggleFavorite() {
        guard let song = AudioEngine.shared.currentSong else { return }
        let songId = song.id
        let wasStarred = song.starred != nil
        Task {
            do {
                if wasStarred {
                    try await OfflineActionQueue.shared.unstar(id: songId)
                } else {
                    try await OfflineActionQueue.shared.star(id: songId)
                    if UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoDownloadFavorites) {
                        DownloadManager.shared.download(song: song, client: AppState.shared.subsonicClient)
                    }
                }
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "Commands")
                    .error("Toggle favorite failed: \(error)")
            }
        }
    }

    private static func setRating(_ rating: Int) {
        guard let song = AudioEngine.shared.currentSong else { return }
        let songId = song.id
        Task {
            do {
                try await AppState.shared.subsonicClient.setRating(id: songId, rating: rating)
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "Commands")
                    .error("Set rating failed: \(error)")
            }
        }
    }
}
#endif
