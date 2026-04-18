import SwiftData
import SwiftUI

struct LabelsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var labels: [LabelInfo] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var sortBy: LabelSortOption = .name
    @State private var labelArt: [String: String] = [:] // label → coverArtId
    @AppStorage("labelsViewStyle") private var showAsList = true
    @State private var cachedFilteredLabels: [LabelInfo] = []

    struct LabelInfo: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let albumCount: Int
    }

    enum LabelSortOption: String, CaseIterable {
        case name, albumCount
        var label: String {
            switch self {
            case .name: "Name (A-Z)"
            case .albumCount: "Album Count"
            }
        }
    }

    private func computeFilteredLabels() -> [LabelInfo] {
        let base: [LabelInfo]
        if searchText.isEmpty {
            base = labels
        } else {
            base = labels.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortBy {
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .albumCount:
            return base.sorted { $0.albumCount > $1.albumCount }
        }
    }

    var body: some View {
        Group {
            if showAsList {
                labelList
            } else {
                labelGrid
            }
        }
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle("Labels")
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Labels")
        #else
        .searchable(text: $searchText, prompt: "Search Labels")
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if isLoading && labels.isEmpty {
                ProgressView("Loading labels...")
            } else if !isLoading && labels.isEmpty {
                ContentUnavailableView {
                    Label("No Labels", systemImage: "tag")
                } description: {
                    Text("No record labels found. Sync your library to populate labels.")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAsList.toggle()
                    }
                } label: {
                    Image(systemName: showAsList ? "square.grid.2x2" : "list.bullet")
                }
                .accessibilityLabel(showAsList ? "Grid View" : "List View")
                .accessibilityIdentifier("labelsViewToggle")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(LabelSortOption.allCases, id: \.self) { option in
                        Button {
                            sortBy = option
                        } label: {
                            HStack {
                                Text(option.label)
                                if sortBy == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        loadLabels()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .task { loadLabels() }
        .onChange(of: searchText) { recomputeFilteredLabels() }
        .onChange(of: sortBy) { recomputeFilteredLabels() }
        .refreshable { loadLabels() }
    }

    // MARK: - List view

    private var labelList: some View {
        List(cachedFilteredLabels) { labelInfo in
            NavigationLink {
                AlbumsView(listType: .alphabeticalByName, title: labelInfo.name, label: labelInfo.name)
            } label: {
                HStack(spacing: 12) {
                    LabelIconView(labelName: labelInfo.name, coverArtId: labelArt[labelInfo.name])
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(labelInfo.name)
                            .font(.body)
                        Text(verbatim: "\(labelInfo.albumCount) albums")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .accessibilityIdentifier("labelRow_\(labelInfo.name)")
        }
        .listStyle(.plain)
    }

    // MARK: - Grid view

    private var labelGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)
            ], spacing: 20) {
                ForEach(cachedFilteredLabels) { labelInfo in
                    NavigationLink {
                        AlbumsView(listType: .alphabeticalByName, title: labelInfo.name, label: labelInfo.name)
                    } label: {
                        labelCard(labelInfo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("labelCard_\(labelInfo.name)")
                }
            }
            .padding(16)
        }
    }

    private func labelCard(_ labelInfo: LabelInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabelIconView(labelName: labelInfo.name, coverArtId: labelArt[labelInfo.name])
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(labelInfo.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(verbatim: "\(labelInfo.albumCount) albums")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func recomputeFilteredLabels() {
        cachedFilteredLabels = computeFilteredLabels()
    }

    private func loadLabels() {
        let allAlbums = (try? modelContext.fetch(FetchDescriptor<CachedAlbum>())) ?? []
        var labelCounts: [String: Int] = [:]

        for album in allAlbums {
            guard let label = album.label, !label.isEmpty else { continue }
            labelCounts[label, default: 0] += 1
        }

        labels = labelCounts.map { LabelInfo(name: $0.key, albumCount: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        recomputeFilteredLabels()
        isLoading = false

        // Load cover art for top labels
        Task {
            await loadLabelArt(albums: allAlbums)
        }
    }

    private func loadLabelArt(albums: [CachedAlbum]) async {
        for labelInfo in labels.prefix(30) where labelArt[labelInfo.name] == nil {
            if let album = albums.first(where: { $0.label == labelInfo.name && $0.coverArtId != nil }) {
                labelArt[labelInfo.name] = album.coverArtId
            }
        }
    }
}

// MARK: - Label Icon View

struct LabelIconView: View {
    let labelName: String
    let coverArtId: String?

    var body: some View {
        if let coverArtId {
            AlbumArtView(coverArtId: coverArtId, size: 48, cornerRadius: 8)
        } else {
            ZStack {
                LinearGradient(
                    colors: [.init(red: 0.4, green: 0.5, blue: 0.7), .init(red: 0.2, green: 0.3, blue: 0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "tag.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
}
