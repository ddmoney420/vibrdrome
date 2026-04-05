import SwiftUI

struct WatchQueueView: View {
    @ObservedObject var session: WatchSessionManager

    var body: some View {
        NavigationStack {
            if session.queue.isEmpty {
                ContentUnavailableView {
                    Label("No Queue", systemImage: "list.bullet")
                } description: {
                    Text("Play music on your iPhone")
                }
            } else {
                List {
                    // Now playing
                    if !session.title.isEmpty {
                        Section("Now Playing") {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(session.title)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                    Text(session.artist)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    // Up next
                    Section("Up Next") {
                        ForEach(Array(session.queue.enumerated()), id: \.offset) { index, item in
                            Button {
                                session.sendCommand("skipToIndex:\(index)")
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(item.artist)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
