import SwiftUI

struct LibraryCustomizeView: View {
    @Binding var config: LibraryLayoutConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Pills

                Section {
                    ForEach(config.visiblePills) { pill in
                        pillRow(pill, visible: true)
                    }
                    .onMove { from, to in
                        config.visiblePills.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Quick Access")
                } footer: {
                    if config.visiblePills.isEmpty {
                        Text("Tap + to add items back.")
                    }
                }

                if !config.hiddenPills.isEmpty {
                    Section("Hidden") {
                        ForEach(config.hiddenPills) { pill in
                            pillRow(pill, visible: false)
                        }
                    }
                }

                // MARK: - Carousels

                Section {
                    ForEach(config.visibleCarousels) { carousel in
                        carouselRow(carousel, visible: true)
                    }
                    .onMove { from, to in
                        config.visibleCarousels.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Carousels")
                }

                if !config.hiddenCarousels.isEmpty {
                    Section("Hidden Carousels") {
                        ForEach(config.hiddenCarousels) { carousel in
                            carouselRow(carousel, visible: false)
                        }
                    }
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Customize Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        config.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Reset to Default") {
                            config = .default
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
            }
        }
    }

    // MARK: - Pill Row

    private func pillRow(_ pill: LibraryPill, visible: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: pill.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorForName(pill.color))
                .frame(width: 24)

            Text(pill.title)
                .foregroundColor(visible ? .primary : .secondary)

            Spacer()

            if visible {
                Button {
                    withAnimation {
                        config.visiblePills.removeAll { $0 == pill }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation {
                        config.visiblePills.append(pill)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Carousel Row

    private func carouselRow(_ carousel: LibraryCarousel, visible: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: carouselIcon(carousel))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            Text(carousel.title)
                .foregroundColor(visible ? .primary : .secondary)

            Spacer()

            if visible {
                Button {
                    withAnimation {
                        config.visibleCarousels.removeAll { $0 == carousel }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation {
                        config.visibleCarousels.append(carousel)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func carouselIcon(_ carousel: LibraryCarousel) -> String {
        switch carousel {
        case .recentlyAdded: "clock"
        case .mostPlayed: "star"
        case .rediscover: "heart"
        case .randomPicks: "shuffle"
        case .recentlyPlayed: "play.circle"
        }
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "pink": .pink
        case "mint": .mint
        case "red": .red
        case "purple": .purple
        case "orange": .orange
        case "teal": .teal
        case "yellow": .yellow
        case "blue": .blue
        case "cyan": .cyan
        case "green": .green
        case "indigo": .indigo
        default: .primary
        }
    }
}
