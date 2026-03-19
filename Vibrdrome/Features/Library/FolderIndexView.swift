import SwiftUI

struct FolderIndexView: View {
    let folder: MusicFolder

    @Environment(AppState.self) private var appState
    @State private var indexes: IndexesResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var allArtists: [FolderArtist] {
        indexes?.index?.flatMap { $0.artist ?? [] } ?? []
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
                    Button("Retry") { Task { await loadIndexes() } }
                }
            } else if allArtists.isEmpty {
                ContentUnavailableView(
                    "Empty Folder",
                    systemImage: "folder",
                    description: Text("No artists found in this folder.")
                )
            } else {
                List {
                    ForEach(indexes?.index ?? [], id: \.name) { section in
                        if let artists = section.artist, !artists.isEmpty {
                            Section(section.name) {
                                ForEach(artists) { artist in
                                    NavigationLink(destination: FolderDetailView(directoryId: artist.id).environment(appState)) {
                                        HStack {
                                            Label(artist.name, systemImage: "music.mic")
                                            Spacer()
                                            if let count = artist.albumCount, count > 0 {
                                                Text("\(count) album\(count == 1 ? "" : "s")")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(folder.name ?? "Folder")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadIndexes() }
    }

    private func loadIndexes() async {
        isLoading = true
        errorMessage = nil
        do {
            indexes = try await appState.subsonicClient.getIndexes(musicFolderId: folder.id)
            isLoading = false
        } catch {
            errorMessage = ErrorPresenter.userMessage(for: error)
            isLoading = false
        }
    }
}
