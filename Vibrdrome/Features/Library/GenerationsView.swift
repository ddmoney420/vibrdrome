import SwiftUI

struct GenerationsView: View {
    @Environment(AppState.self) private var appState
    @State private var decadeArt: [String: String] = [:] // decade label → coverArtId

    private let decades: [(String, Int, Int)] = [
        ("2020s", 2020, 2029),
        ("2010s", 2010, 2019),
        ("2000s", 2000, 2009),
        ("1990s", 1990, 1999),
        ("1980s", 1980, 1989),
        ("1970s", 1970, 1979),
        ("1960s", 1960, 1969),
        ("1950s", 1950, 1959),
        ("Earlier", 1900, 1949),
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(decades, id: \.0) { decade in
                    NavigationLink {
                        AlbumsView(
                            listType: .byYear,
                            title: decade.0,
                            fromYear: decade.1,
                            toYear: decade.2
                        )
                    } label: {
                        decadeCard(decade)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("decadeCard_\(decade.0)")
                }
            }
            .padding(16)
        }
        .navigationTitle("Generations")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 80)
        #endif
        .task { await loadDecadeArt() }
    }

    private func decadeCard(_ decade: (String, Int, Int)) -> some View {
        ZStack {
            // Album art background
            if let artId = decadeArt[decade.0] {
                AlbumArtView(coverArtId: artId, size: 200, cornerRadius: 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()
                    .overlay(Color.black.opacity(0.5))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(height: 120)
            }

            // Decade label
            VStack(spacing: 4) {
                Text(decade.0)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("\(decade.1)–\(decade.2)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
    }

    private func loadDecadeArt() async {
        let client = appState.subsonicClient
        for decade in decades where decadeArt[decade.0] == nil {
            if let albums = try? await client.getAlbumList(
                type: .byYear, size: 1, fromYear: decade.1, toYear: decade.2
            ), let coverArt = albums.first?.coverArt {
                decadeArt[decade.0] = coverArt
            }
        }
    }
}
