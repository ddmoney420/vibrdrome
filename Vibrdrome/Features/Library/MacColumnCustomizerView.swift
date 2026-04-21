#if os(macOS)
import SwiftUI

// MARK: - Column customizer popover

struct MacColumnCustomizerView: View {
    @Bindable var settings: TrackTableColumnSettings

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Customize Columns")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            List {
                ForEach(settings.entries) { entry in
                    HStack(spacing: 10) {
                        // Drag handle
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        // Toggle
                        Toggle(isOn: Binding(
                            get: { entry.visible },
                            set: { _ in settings.toggle(entry.column) }
                        )) {
                            Text(entry.column.label)
                                .font(.body)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!entry.column.isRemovable)
                    }
                    .accessibilityElement(children: .combine)
                }
                .onMove { source, destination in
                    settings.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .frame(height: min(CGFloat(settings.entries.count) * 34 + 8, 400))

            Divider()

            // Reset
            HStack {
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 260)
    }
}
#endif
