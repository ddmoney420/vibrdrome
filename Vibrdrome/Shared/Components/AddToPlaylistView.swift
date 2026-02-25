import os.log
import SwiftUI

struct AddToPlaylistView: View {
    let songIds: [String]

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var addedTo: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if playlists.isEmpty {
                    ContentUnavailableView {
                        Label("No Playlists", systemImage: "music.note.list")
                    } description: {
                        Text("Create a playlist first")
                    }
                } else {
                    ForEach(playlists) { playlist in
                        Button {
                            addToPlaylist(playlist)
                        } label: {
                            HStack(spacing: 12) {
                                AlbumArtView(coverArtId: playlist.coverArt, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                        .font(.body)
                                    Text(verbatim: "\(playlist.songCount ?? 0) songs")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if addedTo == playlist.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadPlaylists() }
        }
    }

    private func loadPlaylists() async {
        isLoading = true
        defer { isLoading = false }
        do {
            playlists = try await appState.subsonicClient.getPlaylists()
        } catch {
            Logger(subsystem: "com.vibrdrome.app", category: "Playlists")
                .error("Failed to load playlists: \(error)")
            playlists = []
        }
    }

    private func addToPlaylist(_ playlist: Playlist) {
        Task {
            do {
                try await appState.subsonicClient.updatePlaylist(
                    id: playlist.id,
                    songIdsToAdd: songIds
                )
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "Playlists")
                    .error("Failed to add to playlist: \(error.localizedDescription)")
            }
            addedTo = playlist.id
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        }
    }
}
