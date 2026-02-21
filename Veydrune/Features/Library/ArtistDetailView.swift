import SwiftUI

struct ArtistDetailView: View {
    let artistId: String

    @Environment(AppState.self) private var appState
    @State private var artist: Artist?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if let albums = artist?.album {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(albumId: album.id)
                    } label: {
                        HStack(spacing: 12) {
                            AlbumArtView(coverArtId: album.coverArt, size: 56)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.name)
                                    .font(.body)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    if let year = album.year {
                                        Text(verbatim: "\(year)")
                                    }
                                    if let count = album.songCount {
                                        Text(verbatim: "· \(count) song\(count == 1 ? "" : "s")")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(artist?.name ?? "Artist")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .overlay {
            if isLoading && artist == nil {
                ProgressView()
            } else if let error, artist == nil {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadArtist() } }
                        .buttonStyle(.bordered)
                }
            } else if artist != nil && (artist?.album?.isEmpty ?? true) {
                ContentUnavailableView {
                    Label("No Albums", systemImage: "square.stack")
                } description: {
                    Text("This artist has no albums")
                }
            }
        }
        .task { await loadArtist() }
        .refreshable { await loadArtist() }
    }

    private func loadArtist() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            artist = try await appState.subsonicClient.getArtist(id: artistId)
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }
}
