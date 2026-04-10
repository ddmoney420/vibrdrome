import SwiftUI

// MARK: - Tab Item Configuration

private struct TabItemConfig: Identifiable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let isAlwaysShown: Bool
    let defaultsKey: String?
    let defaultValue: Bool
}

// MARK: - Tab Bar Settings View

struct TabBarSettingsView: View {
    @AppStorage(UserDefaultsKeys.settingsInNavBar) private var settingsInNavBar: Bool = false
    @AppStorage(UserDefaultsKeys.showSearchTab) private var showSearchTab: Bool = true
    @AppStorage(UserDefaultsKeys.showPlaylistsTab) private var showPlaylistsTab: Bool = true
    @AppStorage(UserDefaultsKeys.showRadioTab) private var showRadioTab: Bool = true
    @AppStorage(UserDefaultsKeys.showDownloadsTab) private var showDownloadsTab: Bool = false
    @AppStorage(UserDefaultsKeys.tabBarOrder) private var tabBarOrderJSON: String = "[]"

    @State private var tabItems: [TabItemConfig] = []

    private var defaultTabItems: [TabItemConfig] {
        var items = [
            TabItemConfig(
                id: "library", name: "Library", icon: "music.note.house.fill",
                description: "Browse your music library",
                isAlwaysShown: true, defaultsKey: nil, defaultValue: true
            ),
            TabItemConfig(
                id: "search", name: "Search", icon: "magnifyingglass",
                description: "Search songs, albums, and artists",
                isAlwaysShown: false, defaultsKey: UserDefaultsKeys.showSearchTab, defaultValue: true
            ),
            TabItemConfig(
                id: "playlists", name: "Playlists", icon: "music.note.list",
                description: "Your playlists",
                isAlwaysShown: false, defaultsKey: UserDefaultsKeys.showPlaylistsTab, defaultValue: true
            ),
            TabItemConfig(
                id: "radio", name: "Radio", icon: "antenna.radiowaves.left.and.right",
                description: "Internet radio stations",
                isAlwaysShown: false, defaultsKey: UserDefaultsKeys.showRadioTab, defaultValue: true
            ),
            TabItemConfig(
                id: "downloads", name: "Downloads", icon: "arrow.down.circle.fill",
                description: "Offline downloads",
                isAlwaysShown: false, defaultsKey: UserDefaultsKeys.showDownloadsTab, defaultValue: false
            ),
        ]
        if !settingsInNavBar {
            items.append(
                TabItemConfig(
                    id: "settings", name: "Settings", icon: "gearshape.fill",
                    description: "App settings",
                    isAlwaysShown: true, defaultsKey: nil, defaultValue: true
                )
            )
        }
        return items
    }

    var body: some View {
        List {
            settingsLocationSection
            tabsSection
        }
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle("Tab Bar")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            loadTabOrder()
        }
        .onChange(of: settingsInNavBar) { _, _ in
            loadTabOrder()
        }
    }

    // MARK: - Settings Location Section

    private var settingsLocationSection: some View {
        Section {
            Toggle(isOn: $settingsInNavBar) {
                Label("Settings in Navigation Bar", systemImage: "gearshape")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("settingsInNavBarToggle")
        } header: {
            settingSectionHeader("Settings Location", icon: "location.fill", color: .blue)
        } footer: {
            Text("Settings will appear as a gear icon in the top-right of Library.")
        }
    }

    // MARK: - Tabs Section

    private var tabsSection: some View {
        Section {
            ForEach(tabItems) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.icon)
                        .font(.body)
                        .foregroundColor(.accentColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.body)
                        Text(item.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !item.isAlwaysShown {
                        Toggle("", isOn: toggleBinding(for: item))
                            .labelsHidden()
                            .accessibilityIdentifier("tabToggle_\(item.id)")
                    }
                }
                .accessibilityIdentifier("tabRow_\(item.id)")
            }
            .onMove { source, destination in
                tabItems.move(fromOffsets: source, toOffset: destination)
                saveTabOrder()
            }
        } header: {
            settingSectionHeader("Tabs", icon: "dock.rectangle", color: .teal)
        } footer: {
            Text("Drag to reorder tabs. Toggle to show or hide.")
        }
    }

    // MARK: - Tab Toggle Binding

    private func toggleBinding(for item: TabItemConfig) -> Binding<Bool> {
        switch item.id {
        case "search": return $showSearchTab
        case "playlists": return $showPlaylistsTab
        case "radio": return $showRadioTab
        case "downloads": return $showDownloadsTab
        default: return .constant(true)
        }
    }

    // MARK: - Tab Order Persistence

    private func loadTabOrder() {
        let defaults = defaultTabItems
        guard let data = tabBarOrderJSON.data(using: .utf8),
              let savedOrder = try? JSONDecoder().decode([String].self, from: data),
              !savedOrder.isEmpty
        else {
            tabItems = defaults
            return
        }

        // Reorder based on saved order, append any new tabs at the end
        var ordered: [TabItemConfig] = []
        for savedId in savedOrder {
            if let item = defaults.first(where: { $0.id == savedId }) {
                ordered.append(item)
            }
        }
        // Append any items not in the saved order
        for item in defaults where !ordered.contains(where: { $0.id == item.id }) {
            ordered.append(item)
        }
        tabItems = ordered
    }

    private func saveTabOrder() {
        let ids = tabItems.map(\.id)
        if let data = try? JSONEncoder().encode(ids),
           let json = String(data: data, encoding: .utf8) {
            tabBarOrderJSON = json
        }
    }

    // MARK: - Helpers

    private func settingSectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(title)
        }
        .accessibilityIdentifier("sectionHeader_\(title)")
    }
}
