import SwiftUI
import SwiftData
import NukeUI

#if os(macOS)
private struct ArtistBlurredBackground: View {
    let url: URL?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let url {
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: 60)
                    .saturation(1.3)
                    .overlay(Color.black.opacity(0.35))
                }
            }
        }
    }
}
#endif

#if os(macOS)
private struct ArtworkLightbox: View {
    let url: URL?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture { onDismiss() }

            if let url {
                LazyImage(url: url) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.6), radius: 40, y: 10)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: 600, maxHeight: 600)
                .onTapGesture { onDismiss() }
            }
        }
        .contentShape(Rectangle())
    }
}
#endif

struct ArtistDetailView: View {
    let artistId: String

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var artist: Artist?
    @State private var topSongs: [Song] = []
    @State private var similarArtists: [Artist] = []
    @State private var biography: String?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isStarred = false
    @State private var appearsOnAlbums: [Album] = []
    #if os(macOS)
    @State private var columnSettings = TrackTableColumnSettings(viewKey: "artist")
    @State private var showFullBio = false
    @State private var showAllTracks = false
    @State private var headerArtURL: URL?
    @State private var showArtworkViewer = false
    #else
    @State private var showFullBio = false
    #endif

    // MARK: - Computed

    private var artistGenres: [String] {
        let genres = artist?.album?.flatMap { $0.allGenres } ?? []
        return Array(NSOrderedSet(array: genres)).compactMap { $0 as? String }
    }

    private var yearRange: String? {
        let years = artist?.album?.compactMap { $0.year }.sorted() ?? []
        guard let first = years.first, let last = years.last else { return nil }
        return first == last ? "\(first)" : "\(first) – \(last)"
    }

    private var discographyAlbums: [Album] {
        (artist?.album ?? []).sorted { ($0.year ?? 0) > ($1.year ?? 0) }
    }

    // MARK: - Body

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            if let artist {
                artistHeaderMacOS(artist)
            } else if isLoading {
                Color.black.frame(height: 220)
                    .overlay(ProgressView().tint(.white))
            }

            if let error, artist == nil {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadArtist() } }
                        .buttonStyle(.bordered)
                }
            }

            if artist != nil {
                HStack(spacing: 0) {
                    similarArtistsSidebar
                    Divider()
                    rightContentPanel
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if showArtworkViewer, let artist {
                ArtworkLightbox(
                    url: artist.coverArt.map { appState.subsonicClient.coverArtURL(id: $0, size: 1200) },
                    onDismiss: { withAnimation(.easeInOut(duration: 0.15)) { showArtworkViewer = false } }
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: showArtworkViewer)
            }
        }
        .navigationTitle("")
        .toolbar {
            if let artist {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        AudioEngine.shared.startRadio(artistName: artist.name)
                    } label: {
                        Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .accessibilityIdentifier("startRadioButton")
                }
            }
        }
        .task { await loadArtist() }
        .refreshable { await loadArtist() }
    }

    // MARK: Hero Header

    @ViewBuilder
    private func artistHeaderMacOS(_ artist: Artist) -> some View {
        HStack(alignment: .center, spacing: 24) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { showArtworkViewer = true } } label: {
                AlbumArtView(coverArtId: artist.coverArt, size: 140, cornerRadius: 70)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(artist.name)
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(.white)

                artistStatsRow(artist)
                    .foregroundStyle(.white.opacity(0.7))

                if !artistGenres.isEmpty {
                    macOSGenrePills(artistGenres)
                }

                if let bio = biography, !bio.isEmpty {
                    biographyInHeader(bio)
                }

                artistHeaderActionButtons(artist)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background {
            ArtistBlurredBackground(url: headerArtURL)
        }
    }

    @ViewBuilder
    private func artistStatsRow(_ artist: Artist) -> some View {
        HStack(spacing: 12) {
            let albums = discographyAlbums
            if !albums.isEmpty {
                Text("\(albums.count) \(albums.count == 1 ? "Album" : "Albums")")
            }
            if !topSongs.isEmpty {
                Text("·")
                Text("\(topSongs.count) Top Tracks")
            }
            if let range = yearRange {
                Text("·")
                Text(range)
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func biographyInHeader(_ bio: String) -> some View {
        let cleaned = cleanBiography(bio)
        VStack(alignment: .leading, spacing: 4) {
            Text(cleaned)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(showFullBio ? nil : 3)

            if cleaned.count > 180 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showFullBio.toggle() }
                } label: {
                    Text(showFullBio ? "Show Less" : "Read More")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.9))
                        .underline()
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
    }

    @ViewBuilder
    private func artistHeaderActionButtons(_ artist: Artist) -> some View {
        HStack(spacing: 12) {
            Button {
                if !topSongs.isEmpty {
                    AudioEngine.shared.play(song: topSongs[0], from: topSongs, at: 0)
                }
            } label: {
                Label("Play Top Tracks", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 22)
                    .background(.white, in: Capsule())
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(topSongs.isEmpty)
            .accessibilityIdentifier("artistPlayButton")

            Button {
                AudioEngine.shared.startRadio(artistName: artist.name)
            } label: {
                Label("Artist Radio", systemImage: "dot.radiowaves.left.and.right")
                    .fontWeight(.semibold)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 22)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("artistRadioButton")

            Button {
                toggleArtistStar()
            } label: {
                Image(systemName: isStarred ? "heart.fill" : "heart")
                    .fontWeight(.semibold)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(isStarred ? Color.pink : .white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isStarred ? "Unfavorite Artist" : "Favorite Artist")
            .accessibilityIdentifier("artistFavoriteButton")

            artistExternalLinks(artist)
        }
    }

    @ViewBuilder
    private func artistExternalLinks(_ artist: Artist) -> some View {
        let links = ArtistExternalLinksManager.shared.links
        if !links.isEmpty {
            HStack(spacing: 6) {
                ForEach(links) { link in
                    if let url = link.url(for: artist.name) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            ArtistLinkIcon(link: link)
                        }
                        .buttonStyle(.plain)
                        .help(link.label)
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                        .accessibilityLabel(link.label)
                    }
                }
            }
            .padding(.leading, 4)
        }
    }

    // MARK: Similar Artists Sidebar

    private var similarArtistsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !similarArtists.isEmpty {
                    Text("Similar Artists")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                    VStack(spacing: 4) {
                        ForEach(similarArtists) { similar in
                            NavigationLink {
                                ArtistDetailView(artistId: similar.id)
                            } label: {
                                HStack(spacing: 10) {
                                    AlbumArtView(
                                        coverArtId: similar.coverArt,
                                        size: 40,
                                        cornerRadius: 20
                                    )
                                    Text(similar.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("similarArtist_\(similar.id)")
                            .artistGetInfoContextMenu(artist: similar)
                        }
                    }
                }
            }
        }
        .frame(width: 240)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: Right Content Panel

    private var rightContentPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !topSongs.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("Top Tracks")
                                .font(.title3)
                                .bold()
                            if topSongs.count > 3 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showAllTracks.toggle()
                                    }
                                } label: {
                                    Text(showAllTracks ? "Show Less" : "Show All")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .onHover { inside in
                                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                        MacTrackTableView(
                            songs: showAllTracks ? topSongs : Array(topSongs.prefix(3)),
                            settings: columnSettings,
                            embedsScrollView: false
                        )
                    }
                }

                if !discographyAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Discography (\(discographyAlbums.count))")
                            .font(.title3)
                            .bold()
                            .padding(.horizontal, 20)
                            .padding(.top, 28)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)],
                            spacing: 20
                        ) {
                            ForEach(discographyAlbums) { album in
                                NavigationLink {
                                    AlbumDetailView(albumId: album.id)
                                } label: {
                                    AlbumGridCard(album: album, cellWidth: 180)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("artistAlbumCard_\(album.id)")
                                .albumGetInfoContextMenu(album: album)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                    }
                }

                if !appearsOnAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Appears On (\(appearsOnAlbums.count))")
                            .font(.title3)
                            .bold()
                            .padding(.horizontal, 20)
                            .padding(.top, 28)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)],
                            spacing: 20
                        ) {
                            ForEach(appearsOnAlbums) { album in
                                NavigationLink {
                                    AlbumDetailView(albumId: album.id)
                                } label: {
                                    AlbumGridCard(album: album, cellWidth: 180)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("artistAppearsOnCard_\(album.id)")
                                .albumGetInfoContextMenu(album: album)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                    }
                }

                if discographyAlbums.isEmpty && topSongs.isEmpty && !isLoading {
                    ContentUnavailableView {
                        Label("No Albums", systemImage: "square.stack")
                    } description: {
                        Text("This artist has no albums")
                    }
                    .padding(.top, 60)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Shared macOS Helpers

    private func macOSHeaderPill(text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.18), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    @ViewBuilder
    private func macOSGenrePills(_ genres: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(genres, id: \.self) { genre in
                    macOSHeaderPill(text: genre) {
                        appState.pendingNavigation = .genre(name: genre)
                    }
                }
            }
        }
    }
    #endif

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSBody: some View {
        List {
            if !topSongs.isEmpty {
                Section {
                    ForEach(Array(topSongs.enumerated()), id: \.element.id) { index, song in
                        TrackRow(song: song, showTrackNumber: false)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                AudioEngine.shared.play(song: song, from: topSongs, at: index)
                            }
                            .trackContextMenu(song: song, queue: topSongs, index: index)
                    }
                } header: {
                    Text("Top Tracks")
                }
            }

            if let biography, !biography.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cleanBiography(biography))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(showFullBio ? nil : 4)

                        if biography.count > 200 {
                            Button {
                                withAnimation { showFullBio.toggle() }
                            } label: {
                                Text(showFullBio ? "Show Less" : "Read More")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                } header: {
                    Text("About")
                }
            }

            if let albums = artist?.album, !albums.isEmpty {
                Section {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(albumId: album.id)
                        } label: {
                            AlbumCard(album: album)
                        }
                        .accessibilityIdentifier("artistAlbumRow_\(album.id)")
                        .albumGetInfoContextMenu(album: album)
                    }
                } header: {
                    Text("Albums (\(albums.count))")
                }
            }

            if !appearsOnAlbums.isEmpty {
                Section {
                    ForEach(appearsOnAlbums) { album in
                        NavigationLink {
                            AlbumDetailView(albumId: album.id)
                        } label: {
                            AlbumCard(album: album)
                        }
                        .accessibilityIdentifier("artistAppearsOnRow_\(album.id)")
                        .albumGetInfoContextMenu(album: album)
                    }
                } header: {
                    Text("Appears On (\(appearsOnAlbums.count))")
                }
            }

            if !similarArtists.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(similarArtists) { similar in
                                NavigationLink {
                                    ArtistDetailView(artistId: similar.id)
                                } label: {
                                    VStack(spacing: 8) {
                                        AlbumArtView(
                                            coverArtId: similar.coverArt,
                                            size: 80,
                                            cornerRadius: 40
                                        )
                                        Text(similar.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(width: 88)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("similarArtist_\(similar.id)")
                                .artistGetInfoContextMenu(artist: similar)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Similar Artists")
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.bottom, 80)
        .navigationTitle(artist?.name ?? "Artist")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if isLoading && artist == nil {
                ProgressView()
            } else if let error, artist == nil {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await loadArtist() } }
                        .buttonStyle(.bordered)
                }
            } else if artist != nil && (artist?.album?.isEmpty ?? true) && topSongs.isEmpty {
                ContentUnavailableView {
                    Label("No Albums", systemImage: "square.stack")
                } description: {
                    Text("This artist has no albums")
                }
            }
        }
        .toolbar {
            if artist != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        toggleArtistStar()
                    } label: {
                        Image(systemName: isStarred ? "heart.fill" : "heart")
                            .foregroundStyle(isStarred ? Color.pink : Color.accentColor)
                    }
                    .accessibilityLabel(isStarred ? "Unfavorite Artist" : "Favorite Artist")
                    .accessibilityIdentifier("artistFavoriteButton")
                }
            }
            if let artist {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        AudioEngine.shared.startRadio(artistName: artist.name)
                    } label: {
                        Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .accessibilityIdentifier("startRadioButton")
                }
            }
        }
        .task { await loadArtist() }
        .refreshable { await loadArtist() }
    }
    #endif

    // MARK: - Data Loading

    private func loadArtist() async {
        loadCachedArtist()
        isLoading = artist == nil
        error = nil
        defer { isLoading = false }
        do {
            let loadedArtist = try await appState.subsonicClient.getArtist(id: artistId)
            artist = loadedArtist
            isStarred = loadedArtist.starred != nil
            #if os(macOS)
            if headerArtURL == nil {
                if let imgUrl = loadedArtist.artistImageUrl, let url = URL(string: imgUrl) {
                    headerArtURL = url
                } else if let id = loadedArtist.coverArt {
                    headerArtURL = appState.subsonicClient.coverArtURL(id: id, size: 600)
                }
            }
            #endif
            async let topSongsResult = appState.subsonicClient.getTopSongs(
                artist: loadedArtist.name, count: 10
            )
            async let artistInfoResult = appState.subsonicClient.getArtistInfo(id: artistId)
            topSongs = try await topSongsResult
            let info = try? await artistInfoResult
            similarArtists = info?.similarArtist ?? []
            biography = info?.biography
            appearsOnAlbums = await loadAppearsOn(artistName: loadedArtist.name, ownAlbums: loadedArtist.album ?? [])
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func loadCachedArtist() {
        guard artist == nil else { return }
        let aid = artistId
        let artistDesc = FetchDescriptor<CachedArtist>(predicate: #Predicate { $0.id == aid })
        guard let cached = try? modelContext.fetch(artistDesc).first else { return }
        let albumDesc = FetchDescriptor<CachedAlbum>(
            predicate: #Predicate<CachedAlbum> { $0.artistId == aid },
            sortBy: [SortDescriptor(\CachedAlbum.year, order: .reverse)]
        )
        let albums = ((try? modelContext.fetch(albumDesc)) ?? []).map { $0.toAlbum() }
        artist = Artist(
            id: cached.id, name: cached.name,
            coverArt: cached.coverArtId,
            artistImageUrl: cached.artistImageUrl,
            albumCount: cached.albumCount,
            starred: cached.isStarred ? "true" : nil,
            userRating: cached.userRating,
            averageRating: cached.averageRating,
            album: albums.isEmpty ? nil : albums
        )
        #if os(macOS)
        if headerArtURL == nil {
            if let imgUrl = cached.artistImageUrl, let url = URL(string: imgUrl) {
                headerArtURL = url
            } else if let id = cached.coverArtId {
                headerArtURL = appState.subsonicClient.coverArtURL(id: id, size: 600)
            }
        }
        #endif
    }

    private func loadAppearsOn(artistName: String, ownAlbums: [Album]) async -> [Album] {
        let ownAlbumIds = Set(ownAlbums.map(\.id))
        let searchAlbums = (try? await appState.subsonicClient.search(
            query: artistName, artistCount: 0, albumCount: 50, songCount: 0
        ))?.album ?? []
        return searchAlbums.filter { album in
            !ownAlbumIds.contains(album.id) && album.artistId != artistId
        }.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
    }

    private func cleanBiography(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func toggleArtistStar() {
        let wasStarred = isStarred
        isStarred.toggle()
        #if os(iOS)
        Haptics.light()
        #endif
        Task {
            do {
                if wasStarred {
                    try await OfflineActionQueue.shared.unstar(artistId: artistId)
                } else {
                    try await OfflineActionQueue.shared.star(artistId: artistId)
                }
            } catch {
                isStarred = wasStarred
            }
        }
    }
}
