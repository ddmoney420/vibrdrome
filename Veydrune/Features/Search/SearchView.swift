import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var results: SearchResult3?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if let results {
                    // Artists
                    if let artists = results.artist, !artists.isEmpty {
                        Section("Artists") {
                            ForEach(artists) { artist in
                                NavigationLink {
                                    ArtistDetailView(artistId: artist.id)
                                } label: {
                                    ArtistRow(artist: artist)
                                }
                            }
                        }
                    }

                    // Albums
                    if let albums = results.album, !albums.isEmpty {
                        Section("Albums") {
                            ForEach(albums) { album in
                                NavigationLink {
                                    AlbumDetailView(albumId: album.id)
                                } label: {
                                    AlbumCard(album: album)
                                }
                            }
                        }
                    }

                    // Songs
                    if let songs = results.song, !songs.isEmpty {
                        Section("Songs") {
                            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                TrackRow(song: song, showTrackNumber: false)
                                    .trackContextMenu(song: song, queue: songs, index: index)
                                    .onTapGesture {
                                        AudioEngine.shared.play(song: song, from: songs, at: index)
                                    }
                            }
                        }
                    }

                    // No results
                    if (results.artist?.isEmpty ?? true) &&
                       (results.album?.isEmpty ?? true) &&
                       (results.song?.isEmpty ?? true) {
                        ContentUnavailableView.search(text: query)
                    }
                } else if let searchError, !query.isEmpty {
                    ContentUnavailableView {
                        Label("Search Failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(searchError)
                    } actions: {
                        Button("Retry") {
                            let q = query
                            searchTask?.cancel()
                            searchTask = Task {
                                isSearching = true
                                defer { isSearching = false }
                                do {
                                    let searchResults = try await appState.subsonicClient.search(query: q)
                                    guard !Task.isCancelled else { return }
                                    self.searchError = nil
                                    results = searchResults
                                } catch {
                                    guard !Task.isCancelled else { return }
                                    self.searchError = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else if query.isEmpty {
                    ContentUnavailableView {
                        Label("Search", systemImage: "magnifyingglass")
                    } description: {
                        Text("Search for artists, albums, and songs")
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Artists, albums, songs...")
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()

                guard newValue.count >= 2 else {
                    results = nil
                    return
                }

                searchTask = Task {
                    // Debounce 300ms
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }

                    isSearching = true
                    defer { isSearching = false }

                    do {
                        let searchResults = try await appState.subsonicClient.search(query: newValue)
                        guard !Task.isCancelled else { return }
                        searchError = nil
                        results = searchResults
                    } catch {
                        guard !Task.isCancelled else { return }
                        searchError = error.localizedDescription
                        results = nil
                    }
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                }
            }
        }
    }
}
