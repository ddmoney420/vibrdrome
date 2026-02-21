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
        // Pre-populate with existing credentials when editing
        let state = AppState.shared
        if state.isConfigured {
            _url = State(initialValue: state.serverURL)
            _username = State(initialValue: state.username)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
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
                    Button("Save & Connect") {
                        appState.saveCredentials(url: url, username: username, password: password)
                        if appState.isConfigured {
                            dismiss()
                        } else {
                            testResult = "Invalid server URL. Please enter a valid https:// URL."
                        }
                    }
                    .disabled(url.isEmpty || username.isEmpty || password.isEmpty)
                    .bold()

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
                testResult = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
