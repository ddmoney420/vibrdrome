import SwiftUI
import SwiftData

struct PlayHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlayHistory.playedAt, order: .reverse) private var allPlays: [PlayHistory]
    @State private var cachedTodayCount: Int = 0
    @State private var cachedWeekCount: Int = 0
    @State private var cachedTopArtists: [(String, Int)] = []
    @State private var cachedTopAlbums: [(String, String?, Int)] = []

    var body: some View {
        List {
            if cachedTodayCount > 0 {
                statsSection
            }

            if !cachedTopArtists.isEmpty {
                topArtistsSection
            }

            if !cachedTopAlbums.isEmpty {
                topAlbumsSection
            }

            recentSection
        }
        .accessibilityIdentifier("playHistoryList")
        .listStyle(.plain)
        #if os(iOS)
        .contentMargins(.bottom, 80)
        #endif
        .navigationTitle("Play History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay {
            if allPlays.isEmpty {
                ContentUnavailableView {
                    Label("No History", systemImage: "clock")
                } description: {
                    Text("Play some music to start tracking your history")
                }
            }
        }
        .onChange(of: allPlays) { recomputeStats() }
        .onAppear { recomputeStats() }
    }

    // MARK: - Computed Data

    private func recomputeStats() {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let weekPlays = allPlays.filter { $0.playedAt >= weekAgo }

        cachedTodayCount = allPlays.filter { Calendar.current.isDateInToday($0.playedAt) }.count
        cachedWeekCount = weekPlays.count

        var artistCounts: [String: Int] = [:]
        for play in weekPlays {
            if let artist = play.artistName {
                artistCounts[artist, default: 0] += 1
            }
        }
        cachedTopArtists = artistCounts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }

        var albumCounts: [String: (artist: String?, count: Int)] = [:]
        for play in weekPlays {
            if let album = play.albumName {
                let existing = albumCounts[album]
                albumCounts[album] = (play.artistName, (existing?.count ?? 0) + 1)
            }
        }
        cachedTopAlbums = albumCounts.sorted { $0.value.count > $1.value.count }
            .prefix(5)
            .map { ($0.key, $0.value.artist, $0.value.count) }
    }

    // MARK: - Sections

    private var statsSection: some View {
        Section {
            HStack(spacing: 24) {
                statBadge(value: cachedTodayCount, label: "Today")
                statBadge(value: cachedWeekCount, label: "This Week")
                statBadge(value: allPlays.count, label: "All Time")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    private func statBadge(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var topArtistsSection: some View {
        Section("Top Artists This Week") {
            ForEach(cachedTopArtists, id: \.0) { artist, count in
                HStack {
                    Text(artist)
                        .font(.body)
                    Spacer()
                    Text("\(count) plays")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var topAlbumsSection: some View {
        Section("Top Albums This Week") {
            ForEach(cachedTopAlbums, id: \.0) { album, artist, count in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album)
                            .font(.body)
                        if let artist {
                            Text(artist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(count) plays")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var recentSection: some View {
        Section("Recent") {
            ForEach(allPlays.prefix(50)) { play in
                HStack(spacing: 12) {
                    AlbumArtView(coverArtId: play.coverArtId, size: 40, cornerRadius: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(play.songTitle)
                            .font(.body)
                            .lineLimit(1)
                        Text(play.artistName ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(play.playedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
