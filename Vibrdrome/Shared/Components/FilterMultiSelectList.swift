import SwiftUI

/// A searchable, scrollable multi-select list for filter sidebars.
/// Each item has a label, optional subtitle, optional image, and a checkmark when selected.
struct FilterMultiSelectList<T: Identifiable & Hashable>: View {
    let title: String
    let items: [T]
    @Binding var selectedIds: Set<String>
    let id: KeyPath<T, String>
    let label: KeyPath<T, String>
    let subtitle: ((T) -> String?)?
    let imageId: ((T) -> String?)?

    @State private var searchText = ""

    init(
        title: String,
        items: [T],
        selectedIds: Binding<Set<String>>,
        id: KeyPath<T, String>,
        label: KeyPath<T, String>,
        subtitle: ((T) -> String?)? = nil,
        imageId: ((T) -> String?)? = nil
    ) {
        self.title = title
        self.items = items
        self._selectedIds = selectedIds
        self.id = id
        self.label = label
        self.subtitle = subtitle
        self.imageId = imageId
    }

    private var filteredItems: [T] {
        if searchText.isEmpty { return items }
        return items.filter { $0[keyPath: label].localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !selectedIds.isEmpty {
                    Text("\(selectedIds.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Search \(title.lowercased())…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems, id: id) { item in
                        let itemId = item[keyPath: self.id]
                        let isSelected = selectedIds.contains(itemId)
                        Button {
                            if isSelected {
                                selectedIds.remove(itemId)
                            } else {
                                selectedIds.insert(itemId)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if let imageId, let artId = imageId(item) {
                                    AlbumArtView(coverArtId: artId, size: 30, cornerRadius: 4)
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item[keyPath: label])
                                        .font(.caption)
                                        .lineLimit(1)
                                    if let subtitle, let sub = subtitle(item) {
                                        Text(sub)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                    }
                }
            }
            .frame(height: 200)
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            #else
            .background(Color(.systemBackground).opacity(0.5))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
