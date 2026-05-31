import SwiftUI

struct PlaylistEditorView: View {
    enum Mode {
        case create
        case edit(playlistId: String, currentName: String)
        case smartPlaylist(playlistId: String, currentName: String, existingRules: NSPCriteria?)
    }

    let mode: Mode
    var onSave: (() async -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var searchQuery = ""
    @State private var searchResults: [Song] = []
    @State private var selectedSongs: [Song] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var ruleSet: FilterRuleSet = FilterRuleSet()

    init(mode: Mode, onSave: (() async -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            self._name = State(initialValue: "")
        case .edit(_, let currentName):
            self._name = State(initialValue: currentName)
        case .smartPlaylist(_, let currentName, let existingRules):
            self._name = State(initialValue: currentName)
            if let criteria = existingRules {
                self._ruleSet = State(initialValue: FilterRuleSet(from: criteria))
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist Name") {
                    TextField("Name", text: $name, prompt: Text("My Playlist"))
                }

                #if os(macOS)
                if case .smartPlaylist = mode {
                    Section("Rules") {
                        FilterRuleBuilderView(
                            ruleSet: $ruleSet,
                            allowedFields: FilterField.smartPlaylistFields,
                            expandedKey: "smartPlaylistEditorExpanded"
                        )
                    }
                    if let msg = errorMessage {
                        Section {
                            Text(msg)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }
                #endif

                if case .create = mode {
                    Section("Add Songs") {
                        TextField("Search songs...", text: $searchQuery)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .onChange(of: searchQuery) { _, newValue in
                                searchTask?.cancel()
                                guard newValue.count >= 2 else {
                                    searchResults = []
                                    return
                                }
                                searchTask = Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled else { return }
                                    let results = try? await appState.subsonicClient.search(
                                        query: newValue, artistCount: 0, albumCount: 0, songCount: 30)
                                    searchResults = results?.song ?? []
                                }
                            }

                        ForEach(searchResults) { song in
                            Button {
                                if !selectedSongs.contains(where: { $0.id == song.id }) {
                                    selectedSongs.append(song)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.title)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(song.artist ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if selectedSongs.contains(where: { $0.id == song.id }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "plus.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }

                    if !selectedSongs.isEmpty {
                        Section("Selected (\(selectedSongs.count))") {
                            ForEach(selectedSongs) { song in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.title)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(song.artist ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .onDelete { offsets in
                                selectedSongs.remove(atOffsets: offsets)
                            }
                            .onMove { source, destination in
                                selectedSongs.move(fromOffsets: source, toOffset: destination)
                            }
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("playlistEditorCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Create" : "Save") {
                        save()
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .accessibilityIdentifier("playlistEditorSaveButton")
                }
            }
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "New Playlist"
        case .edit: return "Edit Playlist"
        case .smartPlaylist: return "Edit Smart Playlist"
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                switch mode {
                case .create:
                    let songIds = selectedSongs.map(\.id)
                    try await appState.subsonicClient.createPlaylist(
                        name: name.trimmingCharacters(in: .whitespaces),
                        songIds: songIds
                    )
                case .edit(let playlistId, _):
                    try await appState.subsonicClient.updatePlaylist(
                        id: playlistId,
                        name: name.trimmingCharacters(in: .whitespaces)
                    )
                case .smartPlaylist(let playlistId, _, _):
                    guard let ndClient = appState.navidromeClient else {
                        errorMessage = "Navidrome connection not available"
                        return
                    }
                    let criteria = NSPCriteria(from: ruleSet)
                    try await ndClient.updateSmartPlaylist(
                        id: playlistId,
                        name: name.trimmingCharacters(in: .whitespaces),
                        rules: criteria
                    )
                }
                await onSave?()
                dismiss()
            } catch {
                errorMessage = ErrorPresenter.userMessage(for: error)
            }
        }
    }
}
