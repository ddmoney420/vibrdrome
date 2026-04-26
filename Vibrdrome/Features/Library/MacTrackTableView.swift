#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Unified macOS track table (header + LazyVStack rows)

/// Drop-in macOS replacement for `List { ForEach { TrackRow } }`.
/// Provide `songs`, a `TrackTableColumnSettings` instance keyed to the view,
/// and optionally disc separators (for album detail context).
struct MacTrackTableView: View {
    let songs: [Song]
    let settings: TrackTableColumnSettings
    var showDiscSeparators: Bool = false

    @State private var sortColumn: TrackTableColumn?
    @State private var sortAscending: Bool = true
    @State private var showCustomizer: Bool = false
    @State private var selectedSongId: String?

    @Query(filter: #Predicate<DownloadedSong> { $0.isComplete == true })
    private var completedDownloads: [DownloadedSong]

    private var downloadedSongIds: Set<String> {
        Set(completedDownloads.map(\.songId))
    }

    // MARK: - Computed sort

    private var displayedSongs: [Song] {
        guard let col = sortColumn else { return songs }
        // When disc separators are shown, sort within each disc group so that
        // disc ordering is preserved and separators don't get scattered.
        if showDiscSeparators {
            let discNumbers = songs.compactMap(\.discNumber)
            let hasDiscs = !discNumbers.isEmpty
            if hasDiscs {
                // Group by disc number (preserving disc order), sort within each group.
                let orderedDiscs = Set(songs.compactMap((\.discNumber))).sorted()
                let noDisc = songs.filter { $0.discNumber == nil }
                let grouped: [[Song]] = orderedDiscs.map { disc in
                    songs
                        .filter { $0.discNumber == disc }
                        .sorted { compareSongs($0, $1, by: col, ascending: sortAscending) }
                }
                let sortedNoDisc = noDisc.sorted { compareSongs($0, $1, by: col, ascending: sortAscending) }
                return grouped.flatMap { $0 } + sortedNoDisc
            }
        }
        return songs.sorted { compareSongs($0, $1, by: col, ascending: sortAscending) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                MacTrackTableHeader(
                    settings: settings,
                    availableWidth: geo.size.width,
                    sortColumn: $sortColumn,
                    sortAscending: $sortAscending,
                    showCustomizer: $showCustomizer
                )
            }
            .frame(height: 26)
            .popover(isPresented: $showCustomizer, arrowEdge: .top) {
                MacColumnCustomizerView(settings: settings)
            }
            // Right-click anywhere on the header also opens customizer
            .contextMenu {
                Button("Customize Columns…") { showCustomizer = true }
            }

            if songs.isEmpty {
                ContentUnavailableView(
                    "No Tracks",
                    systemImage: "music.note",
                    description: Text("No songs to display.")
                )
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        let ordered = displayedSongs
                        // Pre-compute first-occurrence indices for disc separators — O(n) not O(n²)
                        let discFirstIndices: Set<Int> = {
                            guard showDiscSeparators else { return [] }
                            var seen = Set<Int>()
                            var result = Set<Int>()
                            for (idx, song) in ordered.enumerated() {
                                if let disc = song.discNumber, !seen.contains(disc) {
                                    seen.insert(disc)
                                    result.insert(idx)
                                }
                            }
                            return result
                        }()

                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, song in
                            if showDiscSeparators && discFirstIndices.contains(index),
                               let disc = song.discNumber {
                                discSeparator(disc)
                            }

                            MacTrackTableRow(
                                song: song,
                                settings: settings,
                                queue: ordered,
                                index: index,
                                downloadedSongIds: downloadedSongIds,
                                selectedSongId: $selectedSongId
                            )
                            .accessibilityIdentifier("macTrackRow_\(song.id)")

                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Disc separator

    @ViewBuilder
    private func discSeparator(_ disc: Int) -> some View {
        HStack {
            Image(systemName: "opticaldisc")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Disc \(disc)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    // MARK: - Sort comparator

    private func compareSongs(_ lhs: Song, _ rhs: Song, by col: TrackTableColumn, ascending: Bool) -> Bool {
        let result: Bool
        switch col {
        case .trackNumber:
            result = (lhs.track ?? Int.max) < (rhs.track ?? Int.max)
        case .title:
            result = lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case .artist:
            result = (lhs.artist ?? "").localizedCaseInsensitiveCompare(rhs.artist ?? "") == .orderedAscending
        case .album:
            result = (lhs.album ?? "").localizedCaseInsensitiveCompare(rhs.album ?? "") == .orderedAscending
        case .duration:
            result = (lhs.duration ?? 0) < (rhs.duration ?? 0)
        case .year:
            result = (lhs.year ?? 0) < (rhs.year ?? 0)
        case .genre:
            result = (lhs.genre ?? "").localizedCaseInsensitiveCompare(rhs.genre ?? "") == .orderedAscending
        case .bitRate:
            result = (lhs.bitRate ?? 0) < (rhs.bitRate ?? 0)
        case .format:
            result = (lhs.suffix ?? "").localizedCaseInsensitiveCompare(rhs.suffix ?? "") == .orderedAscending
        case .bpm:
            result = (lhs.bpm ?? 0) < (rhs.bpm ?? 0)
        case .dateAdded:
            result = (lhs.created ?? "") < (rhs.created ?? "")
        }
        return ascending ? result : !result
    }
}
#endif
