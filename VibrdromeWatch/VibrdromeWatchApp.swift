import SwiftUI

@main
struct VibrdromeWatchApp: App {
    @StateObject private var session = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            TabView {
                WatchNowPlayingView(session: session)
                WatchQueueView(session: session)
                WatchLibraryView(session: session)
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
