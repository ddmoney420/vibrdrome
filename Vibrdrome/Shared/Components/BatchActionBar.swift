import SwiftUI

struct BatchActionBar: View {
    let selectedSongIds: Set<String>
    let songs: [Song]
    let onAddToPlaylist: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 20) {
            Button {
                let selected = songs.filter { selectedSongIds.contains($0.id) }
                for song in selected {
                    DownloadManager.shared.download(song: song, client: appState.subsonicClient)
                }
                #if os(iOS)
                Haptics.light()
                #endif
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                    Text("Download")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("batchDownloadButton")

            Button {
                onAddToPlaylist()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "music.note.list")
                    Text("Add to Playlist")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("batchAddToPlaylistButton")

            Button {
                let selected = songs.filter { selectedSongIds.contains($0.id) }
                for song in selected {
                    AudioEngine.shared.addToQueue(song)
                }
                #if os(iOS)
                Haptics.light()
                #endif
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "text.append")
                    Text("Add to Queue")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("batchAddToQueueButton")
        }
        .font(.subheadline)
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity)
    }
}
