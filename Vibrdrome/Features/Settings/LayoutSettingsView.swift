#if os(macOS)
import SwiftUI

struct LayoutSettingsView: View {
    @AppStorage(UserDefaultsKeys.macNowPlayingPlacement) private var nowPlayingPlacement: String = "sidebar"
    @AppStorage(UserDefaultsKeys.macSidePanelMechanic) private var sidePanelMechanic: String = "trailingColumn"
    @AppStorage(UserDefaultsKeys.macSidePanelWidth) private var sidePanelWidth: String = "medium"
    @AppStorage(UserDefaultsKeys.macMiniPlayerPanelTrigger) private var miniPlayerTrigger: String = "navigateFirst"

    var body: some View {
        Form {
            Section {
                Picker("Now Playing Placement", selection: $nowPlayingPlacement) {
                    Text("Sidebar item").tag("sidebar")
                    Text("Replace detail when playing").tag("replaceDetail")
                    Text("Overlay").tag("overlay")
                }
                .pickerStyle(.inline)
            } header: {
                Text("Now Playing")
            } footer: {
                let nowPlayingFooter = """
                Where the Now Playing screen appears in the main window. \
                Sidebar item is the default — Now Playing shows in the detail pane \
                like any other section, with a Pop Out button to open it as a separate window.
                """
                Text(nowPlayingFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Side Panel Mechanic", selection: $sidePanelMechanic) {
                    Text("Trailing column").tag("trailingColumn")
                    Text("Overlay").tag("overlay")
                }
                .pickerStyle(.inline)

                Picker("Side Panel Width", selection: $sidePanelWidth) {
                    Text("Small (300pt)").tag("small")
                    Text("Medium (360pt)").tag("medium")
                    Text("Large (480pt)").tag("large")
                }
                .pickerStyle(.inline)
            } header: {
                Text("Side Panels (Queue / Lyrics / Artist Info)")
            } footer: {
                let panelFooter = """
                Trailing column adds a third column to the right of the main window. \
                Overlay floats the panel above the current detail content.
                """
                Text(panelFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Mini-Player Panel Trigger", selection: $miniPlayerTrigger) {
                    Text("Navigate to Now Playing first").tag("navigateFirst")
                    Text("Overlay over current view").tag("overlayCurrent")
                }
                .pickerStyle(.inline)
            } header: {
                Text("Cross-View Triggers")
            } footer: {
                let triggerFooter = """
                When you trigger a side panel (Queue / Lyrics) while browsing another section, \
                this controls whether the app navigates to Now Playing first or shows the panel \
                as an overlay over your current view.
                """
                Text(triggerFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Layout")
    }
}

extension LayoutSettingsView {
    static func currentSidePanelWidth() -> CGFloat {
        switch UserDefaults.standard.string(forKey: UserDefaultsKeys.macSidePanelWidth) ?? "medium" {
        case "small": return 300
        case "large": return 480
        default: return 360
        }
    }
}
#endif
