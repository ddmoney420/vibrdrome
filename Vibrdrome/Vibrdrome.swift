import SwiftUI
import SwiftData
import Nuke

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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
    @AppStorage(UserDefaultsKeys.largerText) private var largerText: Bool = false
    @AppStorage(UserDefaultsKeys.boldText) private var boldText: Bool = false
    @AppStorage(UserDefaultsKeys.reduceMotion) private var reduceMotion: Bool = false
    private let persistenceController = PersistenceController.shared

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

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            MacContentView()
                .frame(minWidth: 800, minHeight: 500)
                .environment(appState)
                .modelContainer(persistenceController.container)
                .preferredColorScheme(colorScheme)
                .tint(accentColor)
                .dynamicTypeSize(largerText ? .xxxLarge : .large)
                .environment(\.legibilityWeight, boldText ? .bold : .regular)
                .onAppear {
                    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(name: "com.vibrdrome.images"))
                    RemoteCommandManager.shared.setup()
                    DownloadManager.shared.resumeIncompleteDownloads()
                }
            #else
            ContentView()
                .environment(appState)
                .modelContainer(persistenceController.container)
                .preferredColorScheme(colorScheme)
                .tint(accentColor)
                .dynamicTypeSize(largerText ? .xxxLarge : .large)
                .environment(\.legibilityWeight, boldText ? .bold : .regular)
                .onAppear {
                    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(name: "com.vibrdrome.images"))
                    RemoteCommandManager.shared.setup()
                    DownloadManager.shared.resumeIncompleteDownloads()
                }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandMenu("Playback") {
                Button("Play/Pause") {
                    AudioEngine.shared.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Next Track") {
                    AudioEngine.shared.next()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Previous Track") {
                    AudioEngine.shared.previous()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

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
}
