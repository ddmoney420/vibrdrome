#if os(macOS)
import SwiftUI
import SwiftData

/// Which entity type the filter sidebar is controlling.
enum FilterContext {
    case album, artist, song
}

/// Feishin-style filter sidebar shown as a macOS side panel.
/// Adapts its controls based on the entity type being filtered.
struct LibraryFilterSidebarView: View {
    let context: FilterContext

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CachedArtist.name) private var artists: [CachedArtist]
    @State private var genres: [String] = []
    @State private var labels: [String] = []

    private var filter: LibraryFilter {
        switch context {
        case .album: appState.albumFilter
        case .artist: appState.artistFilter
        case .song: appState.songFilter
        }
    }

    private var panelTitle: String {
        switch context {
        case .album: "Album Filters"
        case .artist: "Artist Filters"
        case .song: "Song Filters"
        }
    }

    var body: some View {
        SidePanelContainer(title: panelTitle, onClose: {
            appState.activeSidePanel = nil
        }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerButtons

                    if appState.librarySyncManager.lastSyncDate == nil {
                        syncRequiredView
                    } else {
                        filterControls
                    }
                }
                .padding(14)
            }
        }
        .task { loadCachedMetadata() }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerButtons: some View {
        HStack {
            if filter.isActive {
                Text("\(filter.activeFilterCount) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reset") {
                filter.reset()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .font(.subheadline)
            .disabled(!filter.isActive)
        }
    }

    // MARK: - Sync Required

    @ViewBuilder
    private var syncRequiredView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Library sync required")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Sync your library to enable filtering.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Sync Now") {
                Task {
                    await appState.librarySyncManager.sync(
                        client: appState.subsonicClient,
                        container: PersistenceController.shared.container
                    )
                    loadCachedMetadata()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Filter Controls

    @ViewBuilder
    private var filterControls: some View {
        if let progress = appState.librarySyncManager.syncProgress {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        @Bindable var state = appState

        // Favorited — all contexts
        favoritedControl

        // Rated — album and song only
        if context == .album || context == .song {
            ratedControl
        }

        // Recently played — album and song only
        if context == .album || context == .song {
            recentlyPlayedControl
        }

        Divider()

        // Artist multi-select — album and song only
        if context == .album || context == .song {
            artistMultiSelect
            Divider()
        }

        // Genre multi-select — all contexts
        genreMultiSelect

        // Label multi-select — album only
        if context == .album {
            Divider()
            labelMultiSelect
        }

        // Year filter — album and song only
        if context == .album || context == .song {
            Divider()
            yearFilter
        }
    }

    // MARK: - Boolean Filter Controls

    @ViewBuilder
    private var favoritedControl: some View {
        @Bindable var state = appState
        switch context {
        case .album: TriStateFilterControl(label: "Is favorited", value: $state.albumFilter.isFavorited)
        case .artist: TriStateFilterControl(label: "Is favorited", value: $state.artistFilter.isFavorited)
        case .song: TriStateFilterControl(label: "Is favorited", value: $state.songFilter.isFavorited)
        }
    }

    @ViewBuilder
    private var ratedControl: some View {
        @Bindable var state = appState
        switch context {
        case .album: TriStateFilterControl(label: "Is rated", value: $state.albumFilter.isRated)
        case .song: TriStateFilterControl(label: "Is rated", value: $state.songFilter.isRated)
        case .artist: EmptyView()
        }
    }

    @ViewBuilder
    private var recentlyPlayedControl: some View {
        @Bindable var state = appState
        HStack {
            Text("Is recently played")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            switch context {
            case .album:
                Toggle("", isOn: $state.albumFilter.isRecentlyPlayed)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Is recently played")
            case .song:
                Toggle("", isOn: $state.songFilter.isRecentlyPlayed)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Is recently played")
            case .artist:
                EmptyView()
            }
        }
    }

    // MARK: - Artist Multi-Select

    @ViewBuilder
    private var artistMultiSelect: some View {
        @Bindable var state = appState
        switch context {
        case .album:
            FilterMultiSelectList(
                title: "Artists", items: artists,
                selectedIds: $state.albumFilter.selectedArtistIds,
                id: \.id, label: \.name,
                subtitle: { a in a.albumCount.map { "\($0) album\($0 == 1 ? "" : "s")" } },
                imageId: { $0.coverArtId }
            )
        case .song:
            FilterMultiSelectList(
                title: "Artists", items: artists,
                selectedIds: $state.songFilter.selectedArtistIds,
                id: \.id, label: \.name,
                subtitle: { a in a.albumCount.map { "\($0) album\($0 == 1 ? "" : "s")" } },
                imageId: { $0.coverArtId }
            )
        case .artist:
            EmptyView()
        }
    }

    // MARK: - Genre Multi-Select

    @ViewBuilder
    private var genreMultiSelect: some View {
        @Bindable var state = appState
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Genres")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !filter.selectedGenres.isEmpty {
                    Text("\(filter.selectedGenres.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            switch context {
            case .album:
                StringFilterList(items: genres, selectedItems: $state.albumFilter.selectedGenres, placeholder: "Search genres…")
            case .artist:
                StringFilterList(items: genres, selectedItems: $state.artistFilter.selectedGenres, placeholder: "Search genres…")
            case .song:
                StringFilterList(items: genres, selectedItems: $state.songFilter.selectedGenres, placeholder: "Search genres…")
            }
        }
    }

    // MARK: - Label Multi-Select

    @ViewBuilder
    private var labelMultiSelect: some View {
        @Bindable var state = appState
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Labels")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if !filter.selectedLabels.isEmpty {
                    Text("\(filter.selectedLabels.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            StringFilterList(items: labels, selectedItems: $state.albumFilter.selectedLabels, placeholder: "Search labels…")
        }
    }

    // MARK: - Year Filter

    @ViewBuilder
    private var yearFilter: some View {
        @Bindable var state = appState
        VStack(alignment: .leading, spacing: 4) {
            Text("Year")
                .font(.subheadline)
                .fontWeight(.medium)
            HStack {
                switch context {
                case .album:
                    TextField("e.g. 2024", value: $state.albumFilter.year, format: .number)
                        .textFieldStyle(.roundedBorder).font(.caption)
                        .accessibilityLabel("Filter by year")
                case .song:
                    TextField("e.g. 2024", value: $state.songFilter.year, format: .number)
                        .textFieldStyle(.roundedBorder).font(.caption)
                        .accessibilityLabel("Filter by year")
                case .artist:
                    EmptyView()
                }
                if filter.year != nil {
                    Button {
                        filter.year = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear year filter")
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadCachedMetadata() {
        // Genres from albums (artists inherit album genres) or songs
        let genreSet: Set<String>
        if context == .song {
            let songDescriptor = FetchDescriptor<CachedSong>()
            let songs = (try? modelContext.fetch(songDescriptor)) ?? []
            genreSet = Set(songs.compactMap(\.genre)).subtracting([""])
        } else {
            let descriptor = FetchDescriptor<CachedAlbum>()
            let albums = (try? modelContext.fetch(descriptor)) ?? []
            genreSet = Set(albums.flatMap(\.genres)).subtracting([""])

            if context == .album {
                let labelSet = Set(albums.compactMap(\.label)).subtracting([""])
                labels = labelSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
        }
        genres = genreSet.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - Reusable String Filter List

struct StringFilterList: View {
    let items: [String]
    @Binding var selectedItems: Set<String>
    var placeholder: String = "Search…"
    @State private var searchText = ""

    private var filteredItems: [String] {
        if searchText.isEmpty { return items }
        return items.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        TextField(placeholder, text: $searchText)
            .textFieldStyle(.roundedBorder)
            .font(.caption)

        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredItems, id: \.self) { item in
                    let isSelected = selectedItems.contains(item)
                    Button {
                        if isSelected {
                            selectedItems.remove(item)
                        } else {
                            selectedItems.insert(item)
                        }
                    } label: {
                        HStack {
                            Text(item)
                                .font(.caption)
                                .lineLimit(1)
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
                    .accessibilityLabel(item)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .frame(height: 160)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
#endif
