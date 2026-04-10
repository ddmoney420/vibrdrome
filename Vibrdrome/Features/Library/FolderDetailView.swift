import NukeUI
import SwiftUI

struct FolderDetailView: View {
    let directoryId: String

    @Environment(AppState.self) private var appState
    @State private var directory: MusicDirectory?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @AppStorage(UserDefaultsKeys.showAlbumArtInLists) private var showAlbumArtInLists: Bool = true

    private var subfolders: [DirectoryChild] {
        directory?.child?.filter(\.isDir) ?? []
    }

    private var songs: [DirectoryChild] {
        directory?.child?.filter { !$0.isDir } ?? []
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await loadDirectory() } }
                }
            } else if directory?.child?.isEmpty ?? true {
                ContentUnavailableView(
                    "Empty Folder",
                    systemImage: "folder",
                    description: Text("This folder has no content.")
                )
            } else {
                contentList
            }
        }
        .navigationTitle(directory?.name ?? "Folder")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !songs.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    playAllMenu
                }
            }
        }
        .task { await loadDirectory() }
    }

    // MARK: - Content

    private var contentList: some View {
        List {
            if !subfolders.isEmpty {
                Section("Folders") {
                    ForEach(subfolders) { child in
                        NavigationLink(value: child.id) {
                            Label(child.title ?? "Unknown", systemImage: "folder.fill")
                        }
                    }
                }
            }

            if !songs.isEmpty {
                Section("Songs") {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, child in
                        songRow(child, index: index)
                    }
                }
            }
        }
        .navigationDestination(for: String.self) { childId in
            FolderDetailView(directoryId: childId)
                .environment(appState)
        }
    }

    private func songRow(_ child: DirectoryChild, index: Int) -> some View {
        Button {
            let allSongs = songs.map { $0.toSong() }
            AudioEngine.shared.play(song: allSongs[index], from: allSongs, at: index)
        } label: {
            HStack(spacing: 12) {
                if showAlbumArtInLists {
                    if let coverArt = child.coverArt {
                        LazyImage(url: appState.subsonicClient.coverArtURL(id: coverArt, size: 80)) { state in
                            if let image = state.image {
                                image.resizable()
                            } else {
                                albumArtPlaceholder
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        albumArtPlaceholder
                            .frame(width: 40, height: 40)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(child.title ?? "Unknown")
                        .font(.body)
                        .lineLimit(1)
                    if let artist = child.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let duration = child.duration {
                    Text(formatDuration(TimeInterval(duration)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var albumArtPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }

    // MARK: - Play All Menu

    private var playAllMenu: some View {
        Menu {
            Button {
                let allSongs = songs.map { $0.toSong() }
                guard let first = allSongs.first else { return }
                AudioEngine.shared.play(song: first, from: allSongs)
            } label: {
                Label("Play All", systemImage: "play.fill")
            }

            Button {
                let allSongs = songs.map { $0.toSong() }.shuffled()
                guard let first = allSongs.first else { return }
                AudioEngine.shared.play(song: first, from: allSongs)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
        } label: {
            Image(systemName: "play.circle.fill")
        }
    }

    // MARK: - Load

    private func loadDirectory() async {
        isLoading = true
        errorMessage = nil
        do {
            directory = try await appState.subsonicClient.getMusicDirectory(id: directoryId)
            isLoading = false
        } catch {
            errorMessage = ErrorPresenter.userMessage(for: error)
            isLoading = false
        }
    }
}

// MARK: - DirectoryChild → Song Conversion

extension DirectoryChild {
    func toSong() -> Song {
        Song(
            id: id,
            parent: parent,
            title: title ?? "Unknown",
            album: album,
            artist: artist,
            albumArtist: nil,
            albumId: nil,
            artistId: nil,
            track: track,
            year: year,
            genre: genre,
            coverArt: coverArt,
            size: size,
            contentType: contentType,
            suffix: suffix,
            duration: duration,
            bitRate: bitRate,
            path: path,
            discNumber: nil,
            created: created,
            starred: starred,
            userRating: nil,
            bpm: nil,
            replayGain: nil,
            musicBrainzId: nil
        )
    }
}
