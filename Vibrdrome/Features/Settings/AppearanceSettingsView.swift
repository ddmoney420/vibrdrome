import SwiftUI

// MARK: - Appearance Settings View

struct AppearanceSettingsView: View {
    // Theme
    @AppStorage(UserDefaultsKeys.appColorScheme) private var appColorScheme: String = "system"
    @AppStorage(UserDefaultsKeys.accentColorTheme) private var accentColorTheme: String = "blue"
    @AppStorage(UserDefaultsKeys.enableLiquidGlass) private var enableLiquidGlass: Bool = true

    // Text
    @AppStorage(UserDefaultsKeys.textSize) private var textSizePref: String = "default"
    @AppStorage(UserDefaultsKeys.boldText) private var boldText: Bool = false

    // Lists
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private var showAlbumArtInLists: Bool = true
    @AppStorage(UserDefaultsKeys.gridDensity) private var gridDensityRaw: String = GridDensity.comfortable.rawValue

    // Mini Player
    @AppStorage(UserDefaultsKeys.disableSpinningArt) private var disableSpinningArt: Bool = false
    @AppStorage(UserDefaultsKeys.enableMiniPlayerTint) private var enableMiniPlayerTint: Bool = false

    var body: some View {
        List {
            themeSection
            textSection
            listsSection
            miniPlayerSection
        }
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle("Appearance")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        Section {
            Picker(selection: $appColorScheme) {
                Text("System").tag("system")
                Text("Dark").tag("dark")
                Text("Light").tag("light")
            } label: {
                Label("Theme", systemImage: "circle.lefthalf.filled")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("themePicker")

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $enableLiquidGlass) {
                    Label("Liquid Glass", systemImage: "drop.fill")
                        .foregroundColor(.primary)
                }
                .accessibilityIdentifier("enableLiquidGlassToggle")
                Text("Tinted pill backgrounds and translucent tab bar. Turn off for plain icons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Accent color picker
            VStack(alignment: .leading, spacing: 10) {
                Label("Accent Color", systemImage: "paintpalette.fill")

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 36), spacing: 10)
                ], spacing: 10) {
                    ForEach(AccentColorTheme.allCases) { theme in
                        Button {
                            accentColorTheme = theme.rawValue
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(theme.color.gradient)
                                    .frame(width: 32, height: 32)
                                if accentColorTheme == theme.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(theme.rawValue)
                        .accessibilityValue(accentColorTheme == theme.rawValue ? "Selected" : "")
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            settingSectionHeader("Theme", icon: "paintbrush.fill", color: .orange)
        }
    }

    // MARK: - Text Section

    private var textSection: some View {
        Section {
            Picker(selection: $textSizePref) {
                Text("Small").tag("small")
                Text("Default").tag("default")
                Text("Large").tag("large")
                Text("Extra Large").tag("xlarge")
            } label: {
                Label("Text Size", systemImage: "textformat.size")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("textSizePicker")

            Toggle(isOn: $boldText) {
                Label("Bold Text", systemImage: "bold")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("boldTextToggle")
        } header: {
            settingSectionHeader("Text", icon: "textformat", color: .blue)
        }
    }

    // MARK: - Lists Section

    private var listsSection: some View {
        Section {
            Toggle(isOn: $showAlbumArtInLists) {
                Label("Album Art in Lists", systemImage: "photo")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("albumArtInListsToggle")

            Picker(selection: $gridDensityRaw) {
                ForEach(GridDensity.allCases, id: \.rawValue) { density in
                    Text(density.label).tag(density.rawValue)
                }
            } label: {
                Label("Grid Density", systemImage: "square.grid.2x2")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("gridDensityPicker")
        } header: {
            settingSectionHeader("Lists", icon: "list.bullet", color: .green)
        }
    }

    // MARK: - Mini Player Section

    private var miniPlayerSection: some View {
        Section {
            Toggle(isOn: $disableSpinningArt) {
                Label("Disable Spinning Art", systemImage: "circle.dashed")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("disableSpinningArtToggle_appearance")

            Toggle(isOn: $enableMiniPlayerTint) {
                Label("Mini Player Tint", systemImage: "paintbrush.pointed.fill")
                    .foregroundColor(.primary)
            }
            .accessibilityIdentifier("enableMiniPlayerTintToggle")
        } header: {
            settingSectionHeader("Mini Player", icon: "rectangle.bottomhalf.filled", color: .purple)
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
