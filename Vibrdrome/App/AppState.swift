import Foundation
import KeychainAccess
import Observation
import os.log

// MARK: - Saved Server Model

struct SavedServer: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var url: String
    var username: String

    init(name: String, url: String, username: String) {
        self.id = UUID().uuidString
        self.name = name
        self.url = url
        self.username = username
    }
}

@Observable
@MainActor
final class AppState {
    static let shared = AppState()

    var subsonicClient: SubsonicClient
    /// Non-nil when the active server is Navidrome and native API auth succeeded.
    var navidromeClient: NavidromeNativeClient?
    var isConfigured: Bool = false
    var requiresReAuth: Bool = false

    // Player presentation state — stored here so it survives
    // view hierarchy recreation during device rotation (sizeClass change).
    var showNowPlaying: Bool = false
    var showVisualizer: Bool = false
    var showLyrics: Bool = false

    // Navigation from Now Playing — set destination, dismiss, then navigate
    enum PendingNavigation: Equatable {
        case artist(id: String)
        case album(id: String)
        case song(id: String)
        case genre(name: String)
        case playlist(id: String)
    }
    var pendingNavigation: PendingNavigation?

    /// Single-shot trigger consumed by NowPlayingView when it appears or this changes.
    /// Used by sidebar actions (e.g., Random Mix) to surface the queue panel.
    enum NowPlayingAction: Equatable {
        case showQueue
        case showLyrics
    }
    var pendingNowPlayingAction: NowPlayingAction?

    /// Active side panel in the macOS main window (Queue / Lyrics / Artist Info / Album Filters).
    /// Mutually exclusive: setting one closes the others.
    enum SidePanel: String, Equatable {
        case queue, lyrics, artistInfo, albumFilters, artistFilters, songFilters
    }
    var activeSidePanel: SidePanel?

    /// Context currently shown in the popped-out filter window. Stays up-to-date
    /// as the user navigates between Albums / Songs / Artists in the main window.
    var activeFilterWindowContext: FilterContext?

    /// Filter state for the macOS filter sidebars.
    var albumFilter = LibraryFilter()
    var artistFilter = LibraryFilter()
    var songFilter = LibraryFilter()

    private func configureFilterPersistence() {
        albumFilter.loadRuleSet(from: UserDefaultsKeys.albumFilterRuleSet)
        artistFilter.loadRuleSet(from: UserDefaultsKeys.artistFilterRuleSet)
        songFilter.loadRuleSet(from: UserDefaultsKeys.songFilterRuleSet)
    }

    /// Cached albums state for back-navigation, keyed by view configuration.
    struct AlbumsViewSnapshot {
        var albums: [Album]
        var hasMore: Bool
        var scrollIndex: Int?
    }
    var albumsViewSnapshots: [String: AlbumsViewSnapshot] = [:]

    /// Library sync manager.
    let librarySyncManager = LibrarySyncManager.shared

    /// Pre-computed model arrays so library tabs are instant on first tap.
    let libraryCache = LibraryDataCache()
    var serverURL: String = ""
    var username: String = ""
    var errorMessage: String?

    // Multi-server
    var servers: [SavedServer] = []
    var activeServerId: String?

    private let keychain = Keychain(service: "com.vibrdrome")
        .accessibility(.afterFirstUnlockThisDeviceOnly)
    private static let serversKey = UserDefaultsKeys.savedServers
    private static let activeServerKey = UserDefaultsKeys.activeServerId

    private init() {
        // Register defaults for settings that should start as true
        UserDefaults.standard.register(defaults: [
            UserDefaultsKeys.scrobblingEnabled: true,
            UserDefaultsKeys.enableLiquidGlass: true
        ])

        // Initialize with a placeholder; reconfigure once server config is loaded
        subsonicClient = SubsonicClient(
            baseURL: URL(string: "https://localhost")!,
            username: "",
            password: ""
        )
        loadServers()
        loadSavedCredentials()
        configureFilterPersistence()

        // UI testing: auto-login with credentials from environment variables
        // so XCUITest doesn't have to type them (avoids idle-wait SIGKILL).
        if ProcessInfo.processInfo.arguments.contains("--uitesting"),
           !isConfigured,
           let url = ProcessInfo.processInfo.environment["TEST_SERVER_URL"],
           let user = ProcessInfo.processInfo.environment["TEST_SERVER_USER"],
           let pass = ProcessInfo.processInfo.environment["TEST_SERVER_PASS"],
           !url.isEmpty {
            saveCredentials(url: url, username: user, password: pass)
        }
    }

    func configure(url: String, username: String, password: String) {
        // Normalize URL - strip trailing slash to prevent double-slash in API paths
        let normalizedURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        guard let serverURL = URL(string: normalizedURL) else {
            errorMessage = "Invalid server URL"
            isConfigured = false
            return
        }
        self.serverURL = normalizedURL
        self.username = username
        subsonicClient.updateCredentials(baseURL: serverURL, username: username, password: password)
        isConfigured = true
        errorMessage = nil
        #if os(iOS)
        SubsonicClientProvider.shared.client = subsonicClient
        #endif
        LibrarySyncManager.shared.client = subsonicClient
        LibrarySyncManager.shared.container = PersistenceController.shared.container

        // Probe Navidrome native API in the background — sets navidromeClient if available.
        let ndClient = NavidromeNativeClient(baseURL: serverURL, username: username, password: password)
        navidromeClient = ndClient
        Task { await ndClient.probe() }
    }

    func loadSavedCredentials() {
        // Don't reset if already configured (prevents CarPlay reconnect issues)
        guard !isConfigured else { return }

        if attemptLoadCredentials() { return }

        // Keychain might be temporarily unavailable (device locked, CarPlay connect).
        // Retry with increasing delays.
        if activeServerId != nil || UserDefaults.standard.string(forKey: UserDefaultsKeys.serverURL) != nil {
            Task { @MainActor in
                for delay in [1.0, 2.0, 5.0] {
                    try? await Task.sleep(for: .seconds(delay))
                    if self.isConfigured { break }
                    if self.attemptLoadCredentials() { break }
                }
            }
        }
    }

    private func attemptLoadCredentials() -> Bool {
        // Try active server first
        if let activeId = activeServerId,
           let server = servers.first(where: { $0.id == activeId }),
           let password = keychain["server_\(activeId)"] {
            configure(url: server.url, username: server.username, password: password)
            return true
        }

        // Fall back to legacy single-server credentials
        guard let url = UserDefaults.standard.string(forKey: UserDefaultsKeys.serverURL),
              let username = UserDefaults.standard.string(forKey: UserDefaultsKeys.username),
              let password = keychain["serverPassword"] else {
            return false
        }
        configure(url: url, username: username, password: password)

        // Migrate legacy credentials to multi-server format
        if servers.isEmpty {
            let config = SavedServer(name: extractServerName(from: url), url: url, username: username)
            servers.append(config)
            activeServerId = config.id
            keychain["server_\(config.id)"] = password
            saveServers()
        }
        return true
    }

    func saveCredentials(url: String, username: String, password: String, name: String? = nil) {
        configure(url: url, username: username, password: password)
        guard isConfigured else { return }

        let trimmedName = name?.trimmingCharacters(in: .whitespaces)
        let resolvedName: String = {
            if let trimmedName, !trimmedName.isEmpty { return trimmedName }
            return extractServerName(from: serverURL)
        }()

        // Update or create server config
        if let activeId = activeServerId,
           let index = servers.firstIndex(where: { $0.id == activeId }) {
            servers[index].url = serverURL
            servers[index].username = username
            if let trimmedName, !trimmedName.isEmpty {
                servers[index].name = trimmedName
            }
            keychain["server_\(activeId)"] = password
        } else {
            let config = SavedServer(name: resolvedName, url: serverURL, username: username)
            servers.append(config)
            activeServerId = config.id
            keychain["server_\(config.id)"] = password
        }
        saveServers()

        // Keep legacy keys in sync for backwards compatibility
        UserDefaults.standard.set(serverURL, forKey: UserDefaultsKeys.serverURL)
        UserDefaults.standard.set(username, forKey: UserDefaultsKeys.username)
        keychain["serverPassword"] = password
    }

    func reAuthenticate(password: String) {
        guard !serverURL.isEmpty, !username.isEmpty else { return }
        saveCredentials(url: serverURL, username: username, password: password)
        requiresReAuth = false
    }

    func resetLibraryFilterState() {
        albumFilter = LibraryFilter()
        artistFilter = LibraryFilter()
        songFilter = LibraryFilter()
        configureFilterPersistence()
        albumsViewSnapshots = [:]
    }

    func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.serverURL)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.username)
        try? keychain.remove("serverPassword")
        isConfigured = false
        requiresReAuth = false
        serverURL = ""
        username = ""
        navidromeClient = nil
        resetLibraryFilterState()
        // Reset the client so stale creds aren't used
        subsonicClient.updateCredentials(
            baseURL: URL(string: "https://localhost")!,
            username: "",
            password: ""
        )
    }

    // MARK: - Multi-Server Management

    func addServer(name: String, url: String, username: String, password: String) {
        let normalizedURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        let config = SavedServer(name: name, url: normalizedURL, username: username)
        servers.append(config)
        keychain["server_\(config.id)"] = password
        saveServers()
        switchToServer(id: config.id)
    }

    func switchToServer(id: String) {
        guard let server = servers.first(where: { $0.id == id }),
              let password = keychain["server_\(id)"] else { return }
        activeServerId = id
        UserDefaults.standard.set(id, forKey: Self.activeServerKey)
        resetLibraryFilterState()
        configure(url: server.url, username: server.username, password: password)

        // Update legacy keys
        UserDefaults.standard.set(serverURL, forKey: UserDefaultsKeys.serverURL)
        UserDefaults.standard.set(server.username, forKey: UserDefaultsKeys.username)
        keychain["serverPassword"] = password
    }

    func deleteServer(id: String) {
        servers.removeAll { $0.id == id }
        try? keychain.remove("server_\(id)")
        saveServers()

        if activeServerId == id {
            if let first = servers.first {
                switchToServer(id: first.id)
            } else {
                activeServerId = nil
                clearCredentials()
            }
        }
    }

    func updateServer(id: String, name: String, url: String, username: String, password: String) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        let normalizedURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        servers[index].name = name
        servers[index].url = normalizedURL
        servers[index].username = username
        keychain["server_\(id)"] = password
        saveServers()

        // If this is the active server, reconfigure
        if activeServerId == id {
            configure(url: normalizedURL, username: username, password: password)
            UserDefaults.standard.set(serverURL, forKey: UserDefaultsKeys.serverURL)
            UserDefaults.standard.set(username, forKey: UserDefaultsKeys.username)
            keychain["serverPassword"] = password
        }
    }

    private func loadServers() {
        if let data = UserDefaults.standard.data(forKey: Self.serversKey) {
            do {
                servers = try JSONDecoder().decode([SavedServer].self, from: data)
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "AppState")
                    .error("Failed to decode server list: \(error.localizedDescription)")
            }
        }
        activeServerId = UserDefaults.standard.string(forKey: Self.activeServerKey)
    }

    private func saveServers() {
        do {
            let data = try JSONEncoder().encode(servers)
            UserDefaults.standard.set(data, forKey: Self.serversKey)
        } catch {
            Logger(subsystem: "com.vibrdrome.app", category: "AppState")
                .error("Failed to encode server list: \(error.localizedDescription)")
        }
        if let activeId = activeServerId {
            UserDefaults.standard.set(activeId, forKey: Self.activeServerKey)
        }
    }

    private func extractServerName(from url: String) -> String {
        if let host = URL(string: url)?.host {
            return host
        }
        return "My Server"
    }
}
