import SwiftUI

struct GenresView: View {
    @Environment(AppState.self) private var appState
    @State private var genres: [Genre] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List(genres) { genre in
            NavigationLink {
                AlbumsView(listType: .byGenre, title: genre.value, genre: genre.value)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(genre.value)
                            .font(.body)
                        Text(verbatim: "\(genre.albumCount ?? 0) albums · \(genre.songCount ?? 0) songs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Genres")
        .overlay {
            if isLoading && genres.isEmpty {
                ProgressView("Loading genres...")
            } else if let error, genres.isEmpty {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadGenres() } }
                        .buttonStyle(.bordered)
                }
            } else if !isLoading && genres.isEmpty {
                ContentUnavailableView {
                    Label("No Genres", systemImage: "music.note")
                } description: {
                    Text("No genres found in your library")
                }
            }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                Button { Task { await loadGenres() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        #endif
        .task { await loadGenres() }
        .refreshable { await loadGenres() }
    }

    private func loadGenres() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            genres = try await appState.subsonicClient.getGenres()
                .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
