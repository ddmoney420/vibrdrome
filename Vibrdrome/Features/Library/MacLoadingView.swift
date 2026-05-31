#if os(macOS)
import SwiftUI

/// Shown on macOS while the library cache warms on first launch.
/// Transitions automatically to the main UI once the cache is ready.
struct MacLoadingView: View {
    @Environment(AppState.self) private var appState

    private var cache: LibraryDataCache { appState.libraryCache }
    private var sync: LibrarySyncManager { appState.librarySyncManager }

    private var statusText: String {
        if let progress = sync.syncProgress {
            return progress
        }
        if sync.isSyncing {
            return "Syncing library…"
        }
        if cache.isReady {
            return "Ready"
        }
        return "Loading library…"
    }

    private var albumCount: Int { cache.albums?.count ?? 0 }
    private var artistCount: Int { cache.artists?.count ?? 0 }
    private var songCount: Int { cache.songs?.count ?? 0 }
    private var hasData: Bool { albumCount > 0 || artistCount > 0 }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // App icon
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                }

                VStack(spacing: 8) {
                    Text("Vibrdrome")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut(duration: 0.3), value: statusText)
                }

                // Progress indicator
                if !cache.isReady || sync.isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(.circular)
                }

                // Live counts — fade in as data arrives
                if hasData {
                    HStack(spacing: 24) {
                        statPill(count: albumCount, label: "Albums")
                        statPill(count: artistCount, label: "Artists")
                        statPill(count: songCount, label: "Songs")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func statPill(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(count == 0 ? "—" : "\(count)")
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.4), value: count)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 70)
    }
}
#endif
