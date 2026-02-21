import Foundation
import Observation
import KeychainAccess

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
    var isConfigured: Bool = false
    var serverURL: String = ""
    var username: String = ""
    var errorMessage: String?

    // Multi-server
    var servers: [SavedServer] = []
    var activeServerId: String?

    private let keychain = Keychain(service: "com.veydrune")
    private static let serversKey = "savedServers"
    private static let activeServerKey = "activeServerId"

    private init() {
        // Register defaults for settings that should start as true
        UserDefaults.standard.register(defaults: ["scrobblingEnabled": true])

        // Initialize with a placeholder; reconfigure once server config is loaded
        subsonicClient = SubsonicClient(
            baseURL: URL(string: "https://localhost")!,
            username: "",
            password: ""
        )
        loadServers()
        loadSavedCredentials()
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
    }

    func loadSavedCredentials() {
        // Try active server first
        if let activeId = activeServerId,
           let server = servers.first(where: { $0.id == activeId }),
           let password = keychain["server_\(activeId)"] {
            configure(url: server.url, username: server.username, password: password)
            return
        }

        // Fall back to legacy single-server credentials
        guard let url = UserDefaults.standard.string(forKey: "serverURL"),
              let username = UserDefaults.standard.string(forKey: "username"),
              let password = keychain["serverPassword"] else {
            return
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
    }

    func saveCredentials(url: String, username: String, password: String) {
        configure(url: url, username: username, password: password)
        guard isConfigured else { return }

        // Update or create server config
        if let activeId = activeServerId,
           let index = servers.firstIndex(where: { $0.id == activeId }) {
            servers[index].url = serverURL
            servers[index].username = username
            keychain["server_\(activeId)"] = password
        } else {
            let config = SavedServer(name: extractServerName(from: serverURL), url: serverURL, username: username)
            servers.append(config)
            activeServerId = config.id
            keychain["server_\(config.id)"] = password
        }
        saveServers()

        // Keep legacy keys in sync for backwards compatibility
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
        UserDefaults.standard.set(username, forKey: "username")
        keychain["serverPassword"] = password
    }

    func clearCredentials() {
        UserDefaults.standard.removeObject(forKey: "serverURL")
        UserDefaults.standard.removeObject(forKey: "username")
        try? keychain.remove("serverPassword")
        isConfigured = false
        serverURL = ""
        username = ""
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
        configure(url: server.url, username: server.username, password: password)

        // Update legacy keys
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
        UserDefaults.standard.set(server.username, forKey: "username")
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
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            UserDefaults.standard.set(username, forKey: "username")
            keychain["serverPassword"] = password
        }
    }

    private func loadServers() {
        if let data = UserDefaults.standard.data(forKey: Self.serversKey),
           let decoded = try? JSONDecoder().decode([SavedServer].self, from: data) {
            servers = decoded
        }
        activeServerId = UserDefaults.standard.string(forKey: Self.activeServerKey)
    }

    private func saveServers() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: Self.serversKey)
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
