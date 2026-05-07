#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Column header row

struct MacTrackTableHeader: View {
    let settings: TrackTableColumnSettings
    /// Total pixel width of the header row (from GeometryReader in parent).
    let availableWidth: CGFloat
    @Binding var sortColumn: TrackTableColumn?
    @Binding var sortAscending: Bool
    @Binding var showCustomizer: Bool

    // Reference-type box so mutations don't trigger SwiftUI re-renders,
    // which would reset the DragGesture translation back to zero mid-drag.
    @State private var dragBox = ColumnDragBox()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(settings.visibleColumns) { col in
                headerCellWithHandle(col)
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

    // MARK: - Header cell with optional resize handle

    @ViewBuilder
    private func headerCellWithHandle(_ col: TrackTableColumn) -> some View {
        let cellWidth: CGFloat = col.isUserResizable
            ? settings.columnWidth(for: col)
            : col.minWidth

        Button {
            guard col.isSortable else { return }
            if sortColumn == col {
                sortAscending.toggle()
            } else {
                sortColumn = col
                sortAscending = true
            }
        } label: {
            headerCellLabel(col)
        }
        .buttonStyle(.plain)
        .frame(
            minWidth: col == .title ? col.minWidth : cellWidth,
            maxWidth: col == .title ? .infinity : cellWidth,
            alignment: col == .trackNumber ? .trailing : .leading
        )
        .overlay(alignment: .leading) {
            if col.isUserResizable {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .global)
                            .onChanged { value in
                                if dragBox.column != col {
                                    dragBox.column = col
                                    dragBox.startWidth = settings.columnWidth(for: col)
                                }
                                // Use global coordinates: immune to local frame re-renders
                                // caused by settings.setWidth() triggering @Observable updates.
                                let delta = value.location.x - value.startLocation.x
                                let rawWidth = dragBox.startWidth - delta
                                let maxWidth = maxColumnWidth(for: col)
                                let newWidth = min(max(col.minWidth, rawWidth), maxWidth)
                                settings.setWidth(newWidth, for: col)
                            }
                            .onEnded { _ in
                                settings.persistWidths()
                                dragBox.column = nil
                                dragBox.startWidth = 0
                            }
                    )
            }
        }
    }

    @ViewBuilder
    private func headerCellLabel(_ col: TrackTableColumn) -> some View {
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
        .frame(maxWidth: .infinity, alignment: col == .trackNumber ? .trailing : .leading)
    }

    // MARK: - Max width computation

    /// Maximum width `col` may be set to — leaves enough room for Title to stay at its minimum.
    private func maxColumnWidth(for col: TrackTableColumn) -> CGFloat {
        // Fixed layout budget consumed by non-flexible columns and chrome:
        //   • 80pt trailing actions
        //   • 24pt horizontal padding (12 each side)
        //   • title minimum width
        //   • all other visible fixed columns (not title, not the column being dragged)
        //   • all other visible resizable columns (not the column being dragged)
        let chrome: CGFloat = 80 + 24 + TrackTableColumn.title.minWidth
        let otherFixed = settings.visibleColumns
            .filter { $0 != col && $0 != .title && !$0.isUserResizable }
            .reduce(0) { $0 + $1.minWidth }
        let otherResizable = settings.visibleColumns
            .filter { $0 != col && $0.isUserResizable }
            .reduce(0) { $0 + settings.columnWidth(for: $1) }
        let budget = availableWidth - chrome - otherFixed - otherResizable
        return max(col.minWidth, budget)
    }
}

// MARK: - Drag state box

/// Reference type so property mutations don't trigger SwiftUI re-renders,
/// keeping the DragGesture translation stable throughout the drag.
private final class ColumnDragBox {
    var column: TrackTableColumn?
    var startWidth: CGFloat = 0
}
#endif
