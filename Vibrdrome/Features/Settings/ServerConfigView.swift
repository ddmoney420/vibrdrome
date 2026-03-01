import SwiftUI

struct ServerConfigView: View {
    @Environment(AppState.self) private var appState
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @Environment(\.dismiss) private var dismiss

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
                    TextField("Server URL", text: $url, prompt: Text("https://music.example.com"))
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .autocorrectionDisabled()

                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                // Buttons
                VStack(spacing: 10) {
                    Button {
                        appState.saveCredentials(url: url, username: username, password: password)
                        if !appState.isConfigured {
                            testResult = "Invalid server URL. Please enter a valid https:// URL."
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

                Section("Server Details") {
                    TextField("URL", text: $url, prompt: Text("https://..."))
                        .textContentType(.URL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Username", text: $username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }

                Section {
                    Button {
                        appState.saveCredentials(url: url, username: username, password: password)
                        if appState.isConfigured {
                            dismiss()
                        } else {
                            testResult = "Invalid server URL. Please enter a valid https:// URL."
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
