import SwiftUI

struct WatchLibraryView: View {
    @ObservedObject var session: WatchSessionManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        session.sendCommand("playFavorites")
                    } label: {
                        Label("Play Favorites", systemImage: "heart.fill")
                    }

                    Button {
                        session.sendCommand("shuffleFavorites")
                    } label: {
                        Label("Shuffle Favorites", systemImage: "shuffle")
                    }
                }

                if !session.recentAlbums.isEmpty {
                    Section("Recent Albums") {
                        ForEach(session.recentAlbums, id: \.id) { album in
                            Button {
                                session.sendCommand("playAlbum:\(album.id)")
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(album.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Text(album.artist)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                if !session.playlists.isEmpty {
                    Section("Playlists") {
                        ForEach(session.playlists, id: \.id) { playlist in
                            Button {
                                session.sendCommand("playPlaylist:\(playlist.id)")
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(playlist.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Text("\(playlist.songCount) songs")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        session.sendCommand("shuffleAll")
                    } label: {
                        Label("Shuffle All Songs", systemImage: "shuffle")
                    }

                    Button {
                        session.sendCommand("startRadio")
                    } label: {
                        Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                    }
                }

                Section("Sleep Timer") {
                    if session.sleepTimerActive {
                        Button(role: .destructive) {
                            session.sendCommand("sleepTimerCancel")
                        } label: {
                            Label("Cancel Timer", systemImage: "xmark")
                        }
                    } else {
                        ForEach([15, 30, 45, 60], id: \.self) { mins in
                            Button {
                                session.sendCommand("sleepTimer\(mins)")
                            } label: {
                                Label("\(mins) minutes", systemImage: "moon")
                            }
                        }

                        Button {
                            session.sendCommand("sleepTimerEndOfTrack")
                        } label: {
                            Label("End of Track", systemImage: "moon.fill")
                        }
                    }
                }
            }
            .navigationTitle("Library")
        }
    }
}
