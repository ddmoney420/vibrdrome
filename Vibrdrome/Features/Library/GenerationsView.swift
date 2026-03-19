import SwiftUI

struct GenerationsView: View {
    @Environment(AppState.self) private var appState

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

    var body: some View {
        List(decades, id: \.0) { decade in
            NavigationLink {
                AlbumsView(
                    listType: .byYear,
                    title: decade.0,
                    fromYear: decade.1,
                    toYear: decade.2
                )
            } label: {
                HStack {
                    Label(decade.0, systemImage: "calendar")
                    Spacer()
                }
            }
        }
        .navigationTitle("Generations")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
