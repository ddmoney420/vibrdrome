import SwiftUI
import os.log

struct PlaylistsView: View {
    @Environment(AppState.self) private var appState
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showCreateSheet = false
    @State private var showSmartSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Action buttons
                #if os(iOS)
                actionButtons
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                #endif

                // Playlists grid
                if !playlists.isEmpty {
                    playlistGrid
                }
            }
            #if os(iOS)
            .padding(.bottom, 80)
            #endif
        }
        .navigationTitle("Playlists")
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                Button { showCreateSheet = true } label: {
                    Label("New Playlist", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { showSmartSheet = true } label: {
                    Label("Smart Mix", systemImage: "sparkles")
                }
            }
            ToolbarItem {
                Button { Task { await loadPlaylists() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        #endif
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
            GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)
        ], spacing: 20) {
            ForEach(playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistId: playlist.id)
                } label: {
                    playlistCard(playlist)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        Task {
                            do {
                                let detail = try await appState.subsonicClient.getPlaylist(id: playlist.id)
                                if let songs = detail.entry, let first = songs.first {
                                    AudioEngine.shared.play(song: first, from: songs, at: 0)
                                }
                            } catch {
                                Logger(subsystem: "com.vibrdrome.app", category: "Playlists")
                                    .error("Failed to load playlist for playback: \(error)")
                            }
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    Button {
                        Task {
                            do {
                                let detail = try await appState.subsonicClient.getPlaylist(id: playlist.id)
                                if var songs = detail.entry, !songs.isEmpty {
                                    songs.shuffle()
                                    AudioEngine.shared.play(song: songs[0], from: songs, at: 0)
                                }
                            } catch {
                                Logger(subsystem: "com.vibrdrome.app", category: "Playlists")
                                    .error("Failed to load playlist for shuffle: \(error)")
                            }
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    Divider()
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
            AlbumArtView(coverArtId: playlist.coverArt, size: Theme.playlistCardSize, cornerRadius: 12)
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
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        Task {
            do {
                try await appState.subsonicClient.deletePlaylist(id: playlist.id)
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "Playlists")
                    .error("Failed to delete playlist: \(error)")
            }
        }
    }
}
