import KeychainAccess
import SwiftUI

struct ServerManagerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddServer = false
    @State private var editingServer: SavedServer?
    @State private var deleteConfirmServer: SavedServer?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appState.servers) { server in
                        serverRow(server)
                    }
                } header: {
                    if !appState.servers.isEmpty {
                        Text("Servers")
                    }
                }

                Section {
                    Button {
                        showAddServer = true
                    } label: {
                        Label("Add Server", systemImage: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                            .fontWeight(.medium)
                    }
                }
            }
            .navigationTitle("Servers")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddServer) {
                ServerEditView(mode: .add) { name, url, username, password in
                    appState.addServer(name: name, url: url, username: username, password: password)
                }
                .environment(appState)
            }
            .sheet(item: $editingServer) { server in
                ServerEditView(mode: .edit(server)) { name, url, username, password in
                    appState.updateServer(id: server.id, name: name, url: url, username: username, password: password)
                }
                .environment(appState)
            }
            .alert("Delete Server?", isPresented: .init(
                get: { deleteConfirmServer != nil },
                set: { if !$0 { deleteConfirmServer = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let server = deleteConfirmServer {
                        appState.deleteServer(id: server.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let server = deleteConfirmServer {
                    Text("Remove \"\(server.name)\" and its saved credentials?")
                }
            }
        }
    }

    private func serverRow(_ server: SavedServer) -> some View {
        let isActive = appState.activeServerId == server.id

        return Button {
            if !isActive {
                AudioEngine.shared.stop()
                appState.switchToServer(id: server.id)
            }
        } label: {
            serverRowLabel(server, isActive: isActive)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            serverSwipeActions(server)
        }
        .contextMenu {
            serverContextMenuItems(server, isActive: isActive)
        }
    }

    @ViewBuilder
    private func serverRowLabel(_ server: SavedServer, isActive: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill((isActive ? Color.green : Color.gray).gradient.opacity(0.8))
                    .frame(width: 44, height: 44)
                Image(systemName: "server.rack")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.body)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundColor(.primary)
                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                    }
                }
                Text(server.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(server.username)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func serverSwipeActions(_ server: SavedServer) -> some View {
        Button(role: .destructive) {
            deleteConfirmServer = server
        } label: {
            Label("Delete", systemImage: "trash")
        }

        Button {
            editingServer = server
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .tint(.orange)
    }

    @ViewBuilder
    private func serverContextMenuItems(_ server: SavedServer, isActive: Bool) -> some View {
        if !isActive {
            Button {
                AudioEngine.shared.stop()
                appState.switchToServer(id: server.id)
            } label: {
                Label("Switch To", systemImage: "arrow.right.circle")
            }
        }
        Button {
            editingServer = server
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button(role: .destructive) {
            deleteConfirmServer = server
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Server Edit View

struct ServerEditView: View {
    enum Mode {
        case add
        case edit(SavedServer)
    }

    let mode: Mode
    let onSave: (String, String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var testResult: String?

    init(mode: Mode, onSave: @escaping (String, String, String, String) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            break
        case .edit(let server):
            _name = State(initialValue: server.name)
            _url = State(initialValue: server.url)
            _username = State(initialValue: server.username)
        }
    }

    private var isAdd: Bool {
        if case .add = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Details") {
                    TextField("Name", text: $name, prompt: Text("My Navidrome"))
                    TextField("URL", text: $url, prompt: Text("https://music.example.com"))
                        .textContentType(.URL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Username", text: $username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password, prompt: Text(isAdd ? "Required" : "Leave blank to keep current"))
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                            if isTesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(url.isEmpty || username.isEmpty || (isAdd && password.isEmpty) || isTesting)

                    if let testResult {
                        Text(testResult)
                            .foregroundColor(testResult.contains("Success") ? .green : .red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isAdd ? "Add Server" : "Edit Server")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let serverName = name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? extractName(from: url)
                            : name.trimmingCharacters(in: .whitespaces)
                        let finalPassword: String
                        if case .edit(let server) = mode, password.isEmpty {
                            // Keep existing password
                            finalPassword = KeychainAccess.Keychain(service: "com.vibrdrome")["server_\(server.id)"] ?? ""
                        } else {
                            finalPassword = password
                        }
                        onSave(serverName, url.trimmingCharacters(in: .whitespaces),
                               username.trimmingCharacters(in: .whitespaces), finalPassword)
                        dismiss()
                    }
                    .bold()
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty
                              || username.trimmingCharacters(in: .whitespaces).isEmpty
                              || (isAdd && password.isEmpty))
                }
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            let testUrl = url.trimmingCharacters(in: .whitespaces)
            guard let serverURL = URL(string: testUrl) else {
                testResult = "Invalid URL"
                return
            }
            let testPassword: String
            if case .edit(let server) = mode, password.isEmpty {
                testPassword = KeychainAccess.Keychain(service: "com.vibrdrome")["server_\(server.id)"] ?? ""
            } else {
                testPassword = password
            }
            let client = SubsonicClient(baseURL: serverURL, username: username, password: testPassword)
            do {
                let ok = try await client.ping()
                testResult = ok ? "Success! Connected to server." : "Server responded but ping failed."
            } catch {
                testResult = "Failed: \(ErrorPresenter.userMessage(for: error))"
            }
        }
    }

    private func extractName(from url: String) -> String {
        if let host = URL(string: url)?.host { return host }
        return "My Server"
    }
}
