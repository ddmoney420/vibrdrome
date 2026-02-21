import Foundation
import Observation
import KeychainAccess

@Observable
@MainActor
final class AppState {
    static let shared = AppState()

    var subsonicClient: SubsonicClient
    var isConfigured: Bool = false
    var serverURL: String = ""
    var username: String = ""
    var errorMessage: String?

    private let keychain = Keychain(service: "com.veydrune")

    private init() {
        // Register defaults for settings that should start as true
        UserDefaults.standard.register(defaults: ["scrobblingEnabled": true])

        // Initialize with a placeholder; reconfigure once server config is loaded
        subsonicClient = SubsonicClient(
            baseURL: URL(string: "https://localhost")!,
            username: "",
            password: ""
        )
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
        guard let url = UserDefaults.standard.string(forKey: "serverURL"),
              let username = UserDefaults.standard.string(forKey: "username"),
              let password = keychain["serverPassword"] else {
            return
        }
        configure(url: url, username: username, password: password)
    }

    func saveCredentials(url: String, username: String, password: String) {
        configure(url: url, username: username, password: password)
        guard isConfigured else { return }
        // Save the normalized URL, not the raw input
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
}
