import SwiftUI
import os.log

struct PlaylistsView: View {
    @Environment(AppState.self) private var appState
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showCreateSheet = false
    @State private var showSmartSheet = false
    @AppStorage("playlistViewStyle") private var showAsList = false
    @State private var searchText = ""
    @State private var sortBy: PlaylistSortOption = .name

    enum PlaylistSortOption: String, CaseIterable {
        case name, songCount, recentlyUpdated
        var label: String {
            switch self {
            case .name: "Name"
            case .songCount: "Song Count"
            case .recentlyUpdated: "Recently Updated"
            }
        }
    }

    private var filteredPlaylists: [Playlist] {
        let base: [Playlist]
        if searchText.isEmpty {
            base = playlists
        } else {
            base = playlists.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortBy {
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .songCount:
            return base.sorted { ($0.songCount ?? 0) > ($1.songCount ?? 0) }
        case .recentlyUpdated:
            return base.sorted { ($0.changed ?? "") > ($1.changed ?? "") }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Action buttons
                #if os(iOS)
                actionButtons
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                #endif

                // Playlists grid or list
                if !filteredPlaylists.isEmpty {
                    if showAsList {
                        playlistList
                    } else {
                        playlistGrid
                    }
                }
            }
            #if os(iOS)
            .padding(.bottom, 80)
            #endif
        }
        .navigationTitle("Playlists")
        #if os(iOS)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Playlists")
        #else
        .searchable(text: $searchText, prompt: "Search Playlists")
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAsList.toggle()
                    }
                } label: {
                    Image(systemName: showAsList ? "square.grid.2x2" : "list.bullet")
                }
                .accessibilityLabel(showAsList ? "Grid View" : "List View")
                .accessibilityIdentifier("playlistViewToggle")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(PlaylistSortOption.allCases, id: \.self) { option in
                        Button {
                            sortBy = option
                        } label: {
                            HStack {
                                Text(option.label)
                                if sortBy == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        Task { await loadPlaylists() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityIdentifier("playlistSortMenu")
            }
        }
        #endif
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
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAsList.toggle()
                    }
                } label: {
                    Label(showAsList ? "Grid View" : "List View",
                          systemImage: showAsList ? "square.grid.2x2" : "list.bullet")
                }
                .help(showAsList ? "Show as Grid" : "Show as List")
            }
            ToolbarItem {
                Menu {
                    ForEach(PlaylistSortOption.allCases, id: \.self) { option in
                        Button {
                            sortBy = option
                        } label: {
                            HStack {
                                Text(option.label)
                                if sortBy == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        Task { await loadPlaylists() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
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
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("New Playlist")

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
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Smart Mix")
        }
    }

    // MARK: - Playlist Grid

    private var playlistGrid: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)
        ], spacing: 20) {
            ForEach(filteredPlaylists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistId: playlist.id)
                } label: {
                    playlistCard(playlist)
                }
                .buttonStyle(.plain)
                .contextMenu { playlistContextMenu(playlist) }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Playlist List

    private var playlistList: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredPlaylists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistId: playlist.id)
                } label: {
                    HStack(spacing: 14) {
                        PlaylistMosaicView(playlist: playlist, size: 56, cornerRadius: 8)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                if playlist.isPublic == true {
                                    Image(systemName: "globe")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(verbatim: "\(playlist.songCount ?? 0) songs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { playlistContextMenu(playlist) }

                if playlist.id != filteredPlaylists.last?.id {
                    Divider().padding(.leading, 86)
                }
            }
        }
    }

    private func playlistCard(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaylistMosaicView(playlist: playlist, size: Theme.playlistCardSize, cornerRadius: 12)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            Text(playlist.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            HStack(spacing: 4) {
                if playlist.isPublic == true {
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(verbatim: "\(playlist.songCount ?? 0) songs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func playlistContextMenu(_ playlist: Playlist) -> some View {
        Button {
            playlistAction(playlist) { songs in
                if let first = songs.first { AudioEngine.shared.play(song: first, from: songs, at: 0) }
            }
        } label: { Label("Play", systemImage: "play.fill") }

        Button {
            playlistAction(playlist) { songs in
                var shuffled = songs; shuffled.shuffle()
                if let first = shuffled.first { AudioEngine.shared.play(song: first, from: shuffled, at: 0) }
            }
        } label: { Label("Shuffle", systemImage: "shuffle") }

        Button {
            playlistAction(playlist) { songs in AudioEngine.shared.addToQueueNext(songs) }
        } label: { Label("Play Next", systemImage: "text.insert") }

        Button {
            playlistAction(playlist) { songs in AudioEngine.shared.addToQueue(songs) }
        } label: { Label("Add to Queue", systemImage: "text.append") }

        Divider()

        Button(role: .destructive) {
            deletePlaylist(playlist)
        } label: { Label("Delete", systemImage: "trash") }
    }

    private func playlistAction(_ playlist: Playlist, action: @escaping ([Song]) -> Void) {
        Task {
            do {
                let detail = try await appState.subsonicClient.getPlaylist(id: playlist.id)
                if let songs = detail.entry, !songs.isEmpty { action(songs) }
            } catch {
                Logger(subsystem: "com.vibrdrome.app", category: "Playlists")
                    .error("Playlist action failed: \(error)")
            }
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
