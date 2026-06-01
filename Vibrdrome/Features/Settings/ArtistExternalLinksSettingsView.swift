#if os(macOS)
import SwiftUI

struct ArtistExternalLinksSettingsView: View {
    @State private var manager = ArtistExternalLinksManager.shared
    @State private var editingLink: ArtistExternalLink?
    @State private var isAdding = false
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                ForEach(manager.links) { link in
                    HStack(spacing: 10) {
                        ArtistLinkIcon(link: link)
                            .scaleEffect(0.7)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.label)
                                .font(.subheadline)
                            Text(link.urlTemplate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            editingLink = link
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { manager.remove(at: $0) }
                .onMove { manager.move(from: $0, to: $1) }
            } header: {
                Text("Links")
            } footer: {
                Text("Use {artist} in the URL template as a placeholder for the artist name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    isAdding = true
                } label: {
                    Label("Add Link", systemImage: "plus.circle")
                }

                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Artist Links")
        .sheet(item: $editingLink) { link in
            ArtistLinkEditView(link: link) { updated in
                manager.update(updated)
                editingLink = nil
            } onCancel: {
                editingLink = nil
            }
        }
        .sheet(isPresented: $isAdding) {
            ArtistLinkEditView(link: ArtistExternalLink(
                id: UUID().uuidString,
                label: "",
                asset: nil,
                badge: nil,
                urlTemplate: "https://"
            )) { newLink in
                manager.add(newLink)
                isAdding = false
            } onCancel: {
                isAdding = false
            }
        }
        .confirmationDialog("Reset to Defaults?", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) { manager.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your current links with the built-in defaults.")
        }
    }
}

// MARK: - Edit Sheet

private enum IconMode: String, CaseIterable {
    case asset = "Asset"
    case badge = "Text Badge"
    case none = "Generic"
}

private struct ArtistLinkEditView: View {
    @State private var link: ArtistExternalLink
    @State private var iconMode: IconMode
    let onSave: (ArtistExternalLink) -> Void
    let onCancel: () -> Void

    init(link: ArtistExternalLink, onSave: @escaping (ArtistExternalLink) -> Void, onCancel: @escaping () -> Void) {
        let initial = link
        _link = State(initialValue: initial)
        if let asset = initial.asset, !asset.isEmpty {
            _iconMode = State(initialValue: .asset)
        } else if let badge = initial.badge, !badge.isEmpty {
            _iconMode = State(initialValue: .badge)
        } else {
            _iconMode = State(initialValue: .none)
        }
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var isValid: Bool {
        !link.label.trimmingCharacters(in: .whitespaces).isEmpty &&
        link.urlTemplate.contains("{artist}") &&
        ArtistExternalLink.hasAllowedScheme(
            link.urlTemplate.replacingOccurrences(of: "{artist}", with: "test")
        )
    }

    private var preview: ArtistExternalLink {
        var copy = link
        switch iconMode {
        case .asset: copy.badge = nil
        case .badge: copy.asset = nil
        case .none: copy.asset = nil; copy.badge = nil
        }
        return copy
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Label") {
                    TextField("e.g. MusicBrainz", text: $link.label)
                }

                Section {
                    TextField("https://example.com/search?q={artist}", text: $link.urlTemplate)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("URL Template")
                } footer: {
                    Text("{artist} will be replaced with the percent-encoded artist name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Icon Style", selection: $iconMode) {
                        ForEach(IconMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: iconMode) { _, _ in
                        if iconMode != .asset { link.asset = nil }
                        if iconMode != .badge { link.badge = nil }
                    }

                    switch iconMode {
                    case .asset:
                        TextField("Asset name in bundle", text: Binding(
                            get: { link.asset ?? "" },
                            set: { link.asset = $0.isEmpty ? nil : $0 }
                        ))
                    case .badge:
                        TextField("1–2 characters", text: Binding(
                            get: { link.badge ?? "" },
                            set: { link.badge = String($0.prefix(2)).isEmpty ? nil : String($0.prefix(2)) }
                        ))
                    case .none:
                        Text("A generic link icon will be shown.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Spacer()
                        ArtistLinkIcon(link: preview)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Icon")
                } footer: {
                    switch iconMode {
                    case .asset:
                        Text("Name of an image asset in the app bundle (e.g. icon_musicbrainz).")
                            .font(.caption).foregroundStyle(.secondary)
                    case .badge:
                        Text("Up to 2 characters shown inside the circle button.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .none:
                        EmptyView()
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    var saved = link
                    switch iconMode {
                    case .asset: saved.badge = nil
                    case .badge: saved.asset = nil
                    case .none: saved.asset = nil; saved.badge = nil
                    }
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 420, height: 460)
    }
}
#endif
