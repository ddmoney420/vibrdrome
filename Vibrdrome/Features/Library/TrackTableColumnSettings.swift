#if os(macOS)
import Foundation
import Observation

// MARK: - Per-view column settings

/// Manages column visibility and ordering for a single macOS track table context.
/// Each view instantiates this with its own `viewKey`, keeping preferences independent.
@Observable
@MainActor
final class TrackTableColumnSettings {

    // MARK: - Public state

    /// Ordered list of all columns with their current visibility.
    private(set) var entries: [TrackTableColumnEntry]

    /// Ordered list of currently visible columns (for rendering).
    var visibleColumns: [TrackTableColumn] {
        entries.filter(\.visible).map(\.column)
    }

    // MARK: - Private

    private let storageKey: String

    // MARK: - Init

    init(viewKey: String) {
        self.storageKey = UserDefaultsKeys.trackTableColumnsPrefix + viewKey
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([TrackTableColumnEntry].self, from: data) {
            // Merge saved prefs: honour saved order/visibility, append any new columns at end
            var merged = decoded
            let savedIds = Set(decoded.map(\.column))
            for col in TrackTableColumn.allCases where !savedIds.contains(col) {
                merged.append(TrackTableColumnEntry(column: col, visible: col.isOnByDefault))
            }
            self.entries = merged
        } else {
            self.entries = TrackTableColumn.allCases.map {
                TrackTableColumnEntry(column: $0, visible: $0.isOnByDefault)
            }
        }
    }

    // MARK: - Mutations

    func toggle(_ column: TrackTableColumn) {
        guard column.isRemovable else { return }
        guard let idx = entries.firstIndex(where: { $0.column == column }) else { return }
        entries[idx].visible.toggle()
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func resetToDefaults() {
        entries = TrackTableColumn.allCases.map {
            TrackTableColumnEntry(column: $0, visible: $0.isOnByDefault)
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
#endif
