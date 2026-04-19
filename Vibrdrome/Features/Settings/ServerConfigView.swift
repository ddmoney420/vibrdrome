import SwiftUI

struct ServerConfigView: View {
    @Environment(AppState.self) private var appState
    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @Environment(\.dismiss) private var dismiss

    private var isHTTP: Bool {
        url.lowercased().hasPrefix("http://") && !isLocalAddress
    }

    private var isLocalAddress: Bool {
        guard let parsed = URL(string: url), let host = parsed.host else { return false }
        if host == "localhost" || host == "127.0.0.1" || host == "::1"
            || host.hasSuffix(".local") { return true }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.")
            || host.hasPrefix("169.254.") { return true }
        // RFC 1918: 172.16.0.0 - 172.31.255.255
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]),
               (16...31).contains(second) { return true }
        }
        return false
    }

    init() {
        let state = AppState.shared
        if state.isConfigured {
            _url = State(initialValue: state.serverURL)
            _username = State(initialValue: state.username)
        }
    }

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    appIconImage
                        .resizable()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                    Text("Vibrdrome")
                        .font(.largeTitle)
                        .bold()

                    Text("Connect to your Navidrome server")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Fields
                VStack(spacing: 12) {
                    TextField("Server Name", text: $name, prompt: Text("My Navidrome"))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    TextField("Server URL", text: $url, prompt: Text("https://music.example.com"))
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .autocorrectionDisabled()

                    if isHTTP {
                        Label {
                            Text("This connection is not encrypted. Consider using HTTPS with a reverse proxy for security.")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                        .foregroundColor(.orange)
                    }

                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                // Buttons
                VStack(spacing: 10) {
                    Button {
                        appState.saveCredentials(url: url, username: username, password: password, name: name)
                        if !appState.isConfigured {
                            testResult = "Invalid server URL. Please enter a valid URL."
                        }
                    } label: {
                        Text("Sign In")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(url.isEmpty || username.isEmpty || password.isEmpty)

                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Test Connection")
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(url.isEmpty || username.isEmpty || password.isEmpty || isTesting)
                }

                if let testResult {
                    Text(testResult)
                        .foregroundColor(testResult.contains("Success") ? .green : .red)
                        .font(.caption)
                }
            }
            .padding(40)
            .frame(maxWidth: 380)

            Spacer()
        }
        .frame(minWidth: 500, minHeight: 450)
    }
    #endif

    // MARK: - iOS Layout

    private var iOSLayout: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        appIconImage
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        Text("Vibrdrome")
                            .font(.title2)
                            .bold()

                        Text("Connect to your Navidrome server")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Label {
                        Text("""
                        Enter your Navidrome server URL and credentials. \
                        Works with any Subsonic-compatible server. \
                        Use "Test Connection" to verify before signing in.
                        """)
                        .font(.caption)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                    .foregroundStyle(.secondary)
                }

                Section("Server Details") {
                    TextField("Name", text: $name, prompt: Text("My Navidrome"))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverNameField")

                    TextField("URL", text: $url, prompt: Text("https://..."))
                        .textContentType(.URL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverURLField")

                    if isHTTP {
                        Label {
                            Text("This connection is not encrypted. Consider using HTTPS with a reverse proxy for security.")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                        .foregroundColor(.orange)
                    }

                    TextField("Username", text: $username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("usernameField")
                    SecureField("Password", text: $password)
                        .accessibilityIdentifier("passwordField")
                }

                Section {
                    Button {
                        appState.saveCredentials(url: url, username: username, password: password, name: name)
                        if appState.isConfigured {
                            dismiss()
                        } else {
                            testResult = "Invalid server URL. Please enter a valid URL."
                        }
                    } label: {
                        Text("Sign In")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(url.isEmpty || username.isEmpty || password.isEmpty)

                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Test Connection")
                            if isTesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(url.isEmpty || username.isEmpty || password.isEmpty || isTesting)

                    if let testResult {
                        Text(testResult)
                            .foregroundColor(testResult.contains("Success") ? .green : .red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Server Setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Test

    private var appIconImage: Image {
        Image("AppIconImage")
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            guard let serverURL = URL(string: url) else {
                testResult = "Invalid URL"
                return
            }
            let client = SubsonicClient(baseURL: serverURL, username: username, password: password)
            do {
                let ok = try await client.ping()
                testResult = ok ? "Success! Connected to server." : "Server responded but ping failed."
            } catch {
                testResult = "Failed: \(ErrorPresenter.userMessage(for: error))"
            }
        }
    }
}
