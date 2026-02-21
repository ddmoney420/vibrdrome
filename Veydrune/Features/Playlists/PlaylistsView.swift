import SwiftUI

struct PlaylistsView: View {
    @Environment(AppState.self) private var appState
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showCreateSheet = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlistId: playlist.id)
                    } label: {
                        HStack(spacing: 12) {
                            AlbumArtView(coverArtId: playlist.coverArt, size: 50)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                    .font(.body)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(verbatim: "\(playlist.songCount ?? 0) songs")
                                    if let duration = playlist.duration {
                                        Text("·")
                                        Text(formatDuration(duration))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: deletePlaylists)
            }
            .listStyle(.plain)
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                PlaylistEditorView(mode: .create) {
                    await loadPlaylists()
                }
                .environment(appState)
            }
            .overlay {
                if isLoading && playlists.isEmpty {
                    ProgressView("Loading playlists...")
                } else if let error, playlists.isEmpty {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await loadPlaylists() } }
                            .buttonStyle(.bordered)
                    }
                } else if !isLoading && playlists.isEmpty {
                    ContentUnavailableView {
                        Label("No Playlists", systemImage: "music.note.list")
                    } description: {
                        Text("Tap + to create a playlist")
                    }
                }
            }
            .task { await loadPlaylists() }
            .refreshable { await loadPlaylists() }
        }
    }

    private func loadPlaylists() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            playlists = try await appState.subsonicClient.getPlaylists()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deletePlaylists(at offsets: IndexSet) {
        let toDelete = offsets.map { playlists[$0] }
        playlists.remove(atOffsets: offsets)
        for playlist in toDelete {
            Task {
                try? await appState.subsonicClient.deletePlaylist(id: playlist.id)
            }
        }
    }
}
