#if os(macOS)
import SwiftUI

struct MacHomeCustomizeView: View {
    @Binding var config: MacHomeLayoutConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Customize Home")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()

            Divider()

            List {
                Section {
                    ForEach(config.visibleSections) { section in
                        sectionRow(section, visible: true)
                    }
                    .onMove { from, to in
                        config.visibleSections.move(fromOffsets: from, toOffset: to)
                        config.save()
                    }
                } header: {
                    Text("Visible Sections")
                } footer: {
                    if config.visibleSections.isEmpty {
                        Text("Tap + to add sections back.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !config.hiddenSections.isEmpty {
                    Section("Hidden") {
                        ForEach(config.hiddenSections) { section in
                            sectionRow(section, visible: false)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 340, height: 480)
    }

    @ViewBuilder
    private func sectionRow(_ section: MacHomeSection, visible: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(section.title)
            Spacer()
            Button {
                withAnimation {
                    if visible {
                        config.visibleSections.removeAll { $0 == section }
                    } else {
                        config.visibleSections.append(section)
                    }
                    config.save()
                }
            } label: {
                Image(systemName: visible ? "minus.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(visible ? .red : .green)
            }
            .buttonStyle(.plain)
        }
    }
}
#endif
