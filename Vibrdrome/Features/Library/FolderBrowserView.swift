import SwiftUI

struct FolderBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var folders: [MusicFolder] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading folders...")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Folders Unavailable", systemImage: "folder.badge.questionmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { Task { await loadFolders() } }
                }
            } else if folders.isEmpty {
                ContentUnavailableView(
                    "No Folders",
                    systemImage: "folder",
                    description: Text("No music folders found on this server.")
                )
            } else {
                List(folders) { folder in
                    NavigationLink(destination: FolderIndexView(folder: folder).environment(appState)) {
                        Label(folder.name ?? "Unknown Folder", systemImage: "folder.fill")
                    }
                    .accessibilityIdentifier("folderRow_\(folder.id)")
                }
            }
        }
        .navigationTitle("Folders")
        .task { await loadFolders() }
    }

    private func loadFolders() async {
        isLoading = true
        errorMessage = nil
        do {
            folders = try await appState.subsonicClient.getMusicFolders()
            isLoading = false
        } catch {
            errorMessage = ErrorPresenter.userMessage(for: error)
            isLoading = false
        }
    }
}
