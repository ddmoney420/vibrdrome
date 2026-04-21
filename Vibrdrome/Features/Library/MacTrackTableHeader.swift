#if os(macOS)
import SwiftUI

// MARK: - Column header row

struct MacTrackTableHeader: View {
    let visibleColumns: [TrackTableColumn]
    @Binding var sortColumn: TrackTableColumn?
    @Binding var sortAscending: Bool
    @Binding var showCustomizer: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleColumns) { col in
                Button {
                    guard col.isSortable else { return }
                    if sortColumn == col {
                        sortAscending.toggle()
                    } else {
                        sortColumn = col
                        sortAscending = true
                    }
                } label: {
                    headerCell(col)
                }
                .buttonStyle(.plain)
            }

            // Fixed trailing area — must be identical width to MacTrackTableRow trailing actions (80pt)
            HStack(spacing: 0) {
                Spacer()
                Button {
                    showCustomizer.toggle()
                } label: {
                    Image(systemName: "tablecells.badge.ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Customize Columns")
                .accessibilityLabel("Customize Columns")
            }
            .frame(width: 80)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func headerCell(_ col: TrackTableColumn) -> some View {
        HStack(spacing: 3) {
            Text(col.label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(sortColumn == col ? Color.accentColor : .secondary)
                .lineLimit(1)

            if sortColumn == col {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 4)
        .frame(
            minWidth: col.minWidth,
            maxWidth: col.isFlexible ? .infinity : col.minWidth,
            alignment: col == .trackNumber ? .trailing : .leading
        )
    }
}
#endif
