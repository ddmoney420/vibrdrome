import SwiftUI
import SwiftData
import Nuke

// D1: AppDelegate for background URLSession reconnection
#if os(iOS)
class VeydruneAppDelegate: NSObject, UIApplicationDelegate {
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
#endif

@main
struct VeydruneApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(VeydruneAppDelegate.self) var appDelegate
    #endif
    @State private var appState = AppState.shared
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"
    @AppStorage("accentColorTheme") private var accentColorTheme: String = "blue"
    @AppStorage("largerText") private var largerText: Bool = false
    @AppStorage("boldText") private var boldText: Bool = false
    @AppStorage("reduceMotion") private var reduceMotion: Bool = false
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
                .environment(appState)
                .modelContainer(persistenceController.container)
                .preferredColorScheme(colorScheme)
                .tint(accentColor)
                .dynamicTypeSize(largerText ? .xxxLarge : .large)
                .environment(\.legibilityWeight, boldText ? .bold : .regular)
                .onAppear {
                    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(name: "com.veydrune.images"))
                    RemoteCommandManager.shared.setup()
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
                    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(name: "com.veydrune.images"))
                    RemoteCommandManager.shared.setup()
                }
            #endif
        }
        #if os(macOS)
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
            }
        }
        #endif
    }
}
