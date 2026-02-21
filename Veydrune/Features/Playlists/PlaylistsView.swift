import SwiftUI

struct PlaylistsView: View {
    @Environment(AppState.self) private var appState
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showCreateSheet = false
    @State private var showSmartSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Action buttons
                    actionButtons
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    // Playlists grid
                    if !playlists.isEmpty {
                        playlistGrid
                    }
                }
                .padding(.bottom, 80)
            }
            .navigationTitle("Playlists")
            .sheet(isPresented: $showCreateSheet) {
                PlaylistEditorView(mode: .create) {
                    await loadPlaylists()
                }
                .environment(appState)
            }
            .sheet(isPresented: $showSmartSheet) {
                SmartPlaylistView()
                    .environment(appState)
            }
            .onChange(of: showSmartSheet) { _, isPresented in
                if !isPresented {
                    Task { await loadPlaylists() }
                }
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
                        Text("Create a playlist or generate a smart mix")
                    }
                }
            }
            .task { await loadPlaylists() }
            .refreshable { await loadPlaylists() }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button { showCreateSheet = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("New Playlist")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button { showSmartSheet = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.pink)
                    Text("Smart Mix")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Playlist Grid

    private var playlistGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 20) {
            ForEach(playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistId: playlist.id)
                } label: {
                    playlistCard(playlist)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        deletePlaylist(playlist)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func playlistCard(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumArtView(coverArtId: playlist.coverArt, size: 170, cornerRadius: 12)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(playlist.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(verbatim: "\(playlist.songCount ?? 0) songs")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Data

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

    private func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        Task {
            try? await appState.subsonicClient.deletePlaylist(id: playlist.id)
        }
    }
}
