import SwiftUI
import os.log

struct AlbumsView: View {
    let listType: AlbumListType
    var title: String = "Albums"
    var genre: String?
    var fromYear: Int?
    var toYear: Int?

    @Environment(AppState.self) private var appState
    @State private var albums: [Album] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var hasMore = true
    private let pageSize = 40

    var body: some View {
        List {
            ForEach(albums) { album in
                NavigationLink {
                    AlbumDetailView(albumId: album.id)
                } label: {
                    AlbumCard(album: album)
                }
                .accessibilityIdentifier("albumRow_\(album.id)")
                .contextMenu {
                    Button {
                        Task {
                            do {
                                let detail = try await appState.subsonicClient.getAlbum(id: album.id)
                                if let songs = detail.song, let first = songs.first {
                                    AudioEngine.shared.play(song: first, from: songs, at: 0)
                                }
                            } catch {
                                Logger(subsystem: "com.vibrdrome.app", category: "Albums")
                                    .error("Failed to load album for playback: \(error)")
                            }
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    Button {
                        Task {
                            do {
                                let detail = try await appState.subsonicClient.getAlbum(id: album.id)
                                if var songs = detail.song, !songs.isEmpty {
                                    songs.shuffle()
                                    AudioEngine.shared.play(song: songs[0], from: songs, at: 0)
                                }
                            } catch {
                                Logger(subsystem: "com.vibrdrome.app", category: "Albums")
                                    .error("Failed to load album for shuffle: \(error)")
                            }
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    Button {
                        Task {
                            do {
                                let detail = try await appState.subsonicClient.getAlbum(id: album.id)
                                if let songs = detail.song {
                                    DownloadManager.shared.downloadAlbum(
                                        songs: songs,
                                        client: appState.subsonicClient
                                    )
                                }
                            } catch {
                                Logger(subsystem: "com.vibrdrome.app", category: "Albums")
                                    .error("Failed to load album for download: \(error)")
                            }
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .onAppear {
                    if album.id == albums.last?.id && hasMore {
                        Task { await loadMore() }
                    }
                }
            }

            if isLoading && !albums.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .overlay {
            if isLoading && albums.isEmpty {
                ProgressView("Loading albums...")
            } else if let error, albums.isEmpty {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadAlbums() } }
                        .buttonStyle(.bordered)
                }
            } else if !isLoading && albums.isEmpty {
                ContentUnavailableView {
                    Label("No Albums", systemImage: "square.stack")
                } description: {
                    Text("No albums found")
                }
            }
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem {
                Button {
                    albums = []
                    hasMore = true
                    Task { await loadAlbums() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        #endif
        .task { await loadAlbums() }
        .refreshable {
            albums = []
            hasMore = true
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        let client = appState.subsonicClient
        let endpoint = SubsonicEndpoint.getAlbumList2(
            type: listType, size: pageSize, offset: 0,
            fromYear: fromYear, toYear: toYear, genre: genre)
        // Show cached first page instantly
        if albums.isEmpty,
           let cached = await client.cachedResponse(for: endpoint, ttl: 600) {
            albums = cached.albumList2?.album ?? []
        }
        isLoading = albums.isEmpty
        error = nil
        defer { isLoading = false }
        do {
            let result = try await client.getAlbumList(
                type: listType, size: pageSize, offset: 0, genre: genre,
                fromYear: fromYear, toYear: toYear)
            albums = result
            hasMore = result.count >= pageSize
        } catch {
            if albums.isEmpty {
                self.error = ErrorPresenter.userMessage(for: error)
            }
        }
    }

    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await appState.subsonicClient.getAlbumList(
                type: listType, size: pageSize, offset: albums.count, genre: genre,
                fromYear: fromYear, toYear: toYear)
            albums.append(contentsOf: result)
            hasMore = result.count >= pageSize
        } catch {
            hasMore = false
        }
    }
}
