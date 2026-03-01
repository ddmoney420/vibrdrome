import SwiftUI

struct ReAuthView: View {
    @Environment(AppState.self) private var appState
    @State private var password = ""
    @State private var isTesting = false
    @State private var errorMessage: String?

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
                headerSection

                credentialsSection

                actionButtons

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            .frame(maxWidth: 380)

            Spacer()
        }
        .frame(minWidth: 420, minHeight: 380)
    }
    #endif

    // MARK: - iOS Layout

    private var iOSLayout: some View {
        NavigationStack {
            Form {
                Section {
                    headerSection
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                }

                Section("Server") {
                    LabeledContent("URL", value: appState.serverURL)
                        .foregroundStyle(.secondary)
                    LabeledContent("Username", value: appState.username)
                        .foregroundStyle(.secondary)
                }

                Section("Re-authenticate") {
                    SecureField("Password", text: $password)
                }

                Section {
                    signInButton

                    signOutButton

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Session Expired")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Shared Components

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image("AppIconImage")
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Text("Session Expired")
                .font(.title2)
                .bold()

            Text("Your session has expired. Please enter your password to continue.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    #if os(macOS)
    private var credentialsSection: some View {
        VStack(spacing: 12) {
            LabeledContent("Server") {
                Text(appState.serverURL)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Username") {
                Text(appState.username)
                    .foregroundStyle(.secondary)
            }

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
        }
    }
    #endif

    private var actionButtons: some View {
        VStack(spacing: 10) {
            signInButton

            signOutButton
        }
    }

    private var signInButton: some View {
        Button {
            signIn()
        } label: {
            HStack {
                Text("Sign In")
                    .font(.headline)
                    #if os(macOS)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    #else
                    .frame(maxWidth: .infinity)
                    #endif
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        #if os(macOS)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        #endif
        .disabled(password.isEmpty || isTesting)
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            appState.clearCredentials()
        } label: {
            Text("Sign Out")
                #if os(macOS)
                .frame(maxWidth: .infinity)
                #else
                .frame(maxWidth: .infinity)
                #endif
        }
        #if os(macOS)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        #endif
    }

    // MARK: - Actions

    private func signIn() {
        isTesting = true
        errorMessage = nil
        Task {
            defer { isTesting = false }
            // Verify the new password works before saving
            guard let serverURL = URL(string: appState.serverURL) else {
                errorMessage = "Invalid server URL"
                return
            }
            let testClient = SubsonicClient(
                baseURL: serverURL,
                username: appState.username,
                password: password
            )
            do {
                let ok = try await testClient.ping()
                if ok {
                    appState.reAuthenticate(password: password)
                } else {
                    errorMessage = "Server responded but authentication failed."
                }
            } catch {
                errorMessage = "Authentication failed: \(ErrorPresenter.userMessage(for: error))"
            }
        }
    }
}
