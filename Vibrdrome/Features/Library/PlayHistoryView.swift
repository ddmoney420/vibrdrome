import SwiftUI
import SwiftData

struct PlayHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlayHistory.playedAt, order: .reverse) private var allPlays: [PlayHistory]

    var body: some View {
        List {
            if !todayPlays.isEmpty {
                statsSection
            }

            if !topArtists.isEmpty {
                topArtistsSection
            }

            if !topAlbums.isEmpty {
                topAlbumsSection
            }

            recentSection
        }
        .accessibilityIdentifier("playHistoryList")
        .listStyle(.plain)
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
    }

    // MARK: - Computed Data

    private var todayPlays: [PlayHistory] {
        allPlays.filter { Calendar.current.isDateInToday($0.playedAt) }
    }

    private var weekPlays: [PlayHistory] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return allPlays.filter { $0.playedAt >= weekAgo }
    }

    private var topArtists: [(String, Int)] {
        let week = weekPlays
        var counts: [String: Int] = [:]
        for play in week {
            if let artist = play.artistName {
                counts[artist, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private var topAlbums: [(String, String?, Int)] {
        let week = weekPlays
        var counts: [String: (artist: String?, count: Int)] = [:]
        for play in week {
            if let album = play.albumName {
                let existing = counts[album]
                counts[album] = (play.artistName, (existing?.count ?? 0) + 1)
            }
        }
        return counts.sorted { $0.value.count > $1.value.count }
            .prefix(5)
            .map { ($0.key, $0.value.artist, $0.value.count) }
    }

    // MARK: - Sections

    private var statsSection: some View {
        Section {
            HStack(spacing: 24) {
                statBadge(value: todayPlays.count, label: "Today")
                statBadge(value: weekPlays.count, label: "This Week")
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
            ForEach(topArtists, id: \.0) { artist, count in
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
            ForEach(topAlbums, id: \.0) { album, artist, count in
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
