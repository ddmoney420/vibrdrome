import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ArtistsView()
                } label: {
                    Label("Artists", systemImage: "music.mic")
                }

                NavigationLink {
                    AlbumsView(listType: .alphabeticalByName, title: "Albums")
                } label: {
                    Label("Albums", systemImage: "square.stack")
                }

                NavigationLink {
                    GenresView()
                } label: {
                    Label("Genres", systemImage: "guitars")
                }

                NavigationLink {
                    FavoritesView()
                } label: {
                    Label("Favorites", systemImage: "heart.fill")
                }

                NavigationLink {
                    AlbumsView(listType: .newest, title: "Recently Added")
                } label: {
                    Label("Recently Added", systemImage: "clock")
                }

                NavigationLink {
                    AlbumsView(listType: .frequent, title: "Most Played")
                } label: {
                    Label("Most Played", systemImage: "star")
                }

                NavigationLink {
                    AlbumsView(listType: .recent, title: "Recently Played")
                } label: {
                    Label("Recently Played", systemImage: "play.circle")
                }

                NavigationLink {
                    AlbumsView(listType: .random, title: "Random")
                } label: {
                    Label("Random", systemImage: "shuffle")
                }

                NavigationLink {
                    BookmarksView()
                } label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }

                NavigationLink {
                    DownloadsView()
                } label: {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
            }
            .navigationTitle("Library")
        }
    }
}
