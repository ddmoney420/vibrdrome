import SwiftUI

struct SmartPlaylistView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: GeneratorType?
    @State private var isGenerating = false
    @State private var genres: [Genre] = []
    @State private var error: String?
    @AppStorage("reduceMotion") private var reduceMotion = false

    // Selection state
    @State private var artistQuery = ""
    @State private var artistResults: [Artist] = []
    @State private var selectedGenre: Genre?
    @State private var searchTask: Task<Void, Never>?

    enum GeneratorType: String, CaseIterable, Identifiable {
        case artist = "Artist Mix"
        case genre = "Genre Mix"
        case similar = "Similar Songs"
        case random = "Random Mix"
        case bsides = "B-Sides & Obscure"
        case curated = "Curated Weekly"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .artist: "music.mic"
            case .genre: "guitars.fill"
            case .similar: "waveform.path"
            case .random: "dice.fill"
            case .bsides: "record.circle"
            case .curated: "sparkles"
            }
        }
        var color: Color {
            switch self {
            case .artist: .purple
            case .genre: .orange
            case .similar: .cyan
            case .random: .indigo
            case .bsides: .teal
            case .curated: .pink
            }
        }
        var description: String {
            switch self {
            case .artist: "Top songs from an artist"
            case .genre: "Random songs from a genre"
            case .similar: "Songs similar to what's playing"
            case .random: "A random mix of your library"
            case .bsides: "Deep cuts and hidden gems"
            case .curated: "Mix of favorites, random, and recent"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Generator type cards
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(GeneratorType.allCases) { type in
                            generatorCard(type)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Selection UI based on type
                    if let selectedType {
                        selectionView(for: selectedType)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .navigationTitle("Smart Playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                genres = (try? await appState.subsonicClient.getGenres()) ?? []
            }
        }
    }

    // MARK: - Generator Card

    private func generatorCard(_ type: GeneratorType) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                selectedType = selectedType == type ? nil : type
                error = nil
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundColor(type.color)
                Text(type.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(type.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedType == type
                          ? type.color.opacity(0.15)
                          : Color.secondary.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedType == type ? type.color : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection Views

    @ViewBuilder
    private func selectionView(for type: GeneratorType) -> some View {
        switch type {
        case .artist:
            artistSelectionView
        case .genre:
            genreSelectionView
        case .similar:
            similarView
        case .random:
            generateButton("Generate Random Mix") {
                await generateRandom()
            }
        case .bsides:
            generateButton("Generate B-Sides Mix") {
                await generateBSides()
            }
        case .curated:
            generateButton("Generate Curated Weekly") {
                await generateCurated()
            }
        }
    }

    // Artist selection
    private var artistSelectionView: some View {
        VStack(spacing: 12) {
            TextField("Search for an artist...", text: $artistQuery)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .padding(.horizontal, 16)
                .onChange(of: artistQuery) { _, newValue in
                    searchTask?.cancel()
                    guard newValue.count >= 2 else {
                        artistResults = []
                        return
                    }
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        let results = try? await appState.subsonicClient.search(
                            query: newValue, artistCount: 10, albumCount: 0, songCount: 0)
                        artistResults = results?.artist ?? []
                    }
                }

            if !artistResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(artistResults) { artist in
                        Button {
                            Task { await generateArtistMix(artist: artist) }
                        } label: {
                            HStack(spacing: 12) {
                                AlbumArtView(coverArtId: artist.coverArt, size: 40, cornerRadius: 20)
                                Text(artist.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Spacer()
                                if isGenerating {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.purple)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating)

                        if artist.id != artistResults.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }
        }
    }

    // Genre selection
    private var genreSelectionView: some View {
        VStack(spacing: 12) {
            let sortedGenres = genres.sorted { ($0.songCount ?? 0) > ($1.songCount ?? 0) }
            let topGenres = Array(sortedGenres.prefix(20))

            if topGenres.isEmpty {
                ProgressView("Loading genres...")
            } else {
                // Wrap genres in a flow layout
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100), spacing: 8)
                ], spacing: 8) {
                    ForEach(topGenres, id: \.value) { genre in
                        Button {
                            Task { await generateGenreMix(genre: genre) }
                        } label: {
                            Text(genre.value)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(.orange.opacity(0.15), in: Capsule())
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // Similar songs view
    private var similarView: some View {
        VStack(spacing: 12) {
            if let song = AudioEngine.shared.currentSong {
                HStack(spacing: 12) {
                    AlbumArtView(coverArtId: song.coverArt, size: 48, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Based on:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(song.title)
                            .font(.body)
                            .fontWeight(.medium)
                        Text(song.artist ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                generateButton("Generate Similar Mix") {
                    await generateSimilar(songId: song.id, songTitle: song.title)
                }
            } else {
                Text("Play a song first to generate similar songs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }

    // Generate button helper
    private func generateButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                if isGenerating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(isGenerating ? "Generating..." : title)
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
        .padding(.horizontal, 16)
    }

    // MARK: - Generators

    private func generateArtistMix(artist: Artist) async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        do {
            let songs = try await appState.subsonicClient.getTopSongs(artist: artist.name, count: 40)
            guard !songs.isEmpty else {
                error = "No songs found for \(artist.name)"
                return
            }
            var shuffled = songs
            shuffled.shuffle()
            let ids = Array(shuffled.prefix(30)).map(\.id)
            try await appState.subsonicClient.createPlaylist(
                name: "\(artist.name) Mix", songIds: ids)
            dismiss()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func generateGenreMix(genre: Genre) async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        do {
            let songs = try await appState.subsonicClient.getRandomSongs(size: 30, genre: genre.value)
            guard !songs.isEmpty else {
                error = "No songs found for \(genre.value)"
                return
            }
            let ids = songs.map(\.id)
            try await appState.subsonicClient.createPlaylist(
                name: "\(genre.value) Mix", songIds: ids)
            dismiss()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func generateSimilar(songId: String, songTitle: String) async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        do {
            let songs = try await appState.subsonicClient.getSimilarSongs(id: songId, count: 30)
            guard !songs.isEmpty else {
                error = "No similar songs found"
                return
            }
            let ids = songs.map(\.id)
            let name = "Similar to \(songTitle)"
            try await appState.subsonicClient.createPlaylist(
                name: String(name.prefix(60)), songIds: ids)
            dismiss()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func generateRandom() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        do {
            let songs = try await appState.subsonicClient.getRandomSongs(size: 40)
            guard !songs.isEmpty else {
                error = "No songs in library"
                return
            }
            let ids = songs.map(\.id)
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let name = "Random Mix — \(formatter.string(from: Date()))"
            try await appState.subsonicClient.createPlaylist(name: name, songIds: ids)
            dismiss()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func generateBSides() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        do {
            // Get random albums, then pick deep cuts (track 3+)
            let albums = try await appState.subsonicClient.getAlbumList(type: .random, size: 20)
            var deepCuts: [Song] = []
            var seenIds = Set<String>()

            for album in albums {
                guard let fullAlbum = try? await appState.subsonicClient.getAlbum(id: album.id),
                      let songs = fullAlbum.song else { continue }
                // Skip lead tracks — take track 3+ (the b-sides / deep cuts)
                let bsides = songs.filter { ($0.track ?? 1) >= 3 }
                let picks = bsides.isEmpty ? songs.suffix(1) : Array(bsides.shuffled().prefix(2))
                for song in picks where seenIds.insert(song.id).inserted {
                    deepCuts.append(song)
                }
                if deepCuts.count >= 30 { break }
            }

            guard !deepCuts.isEmpty else {
                error = "Not enough songs found"
                return
            }

            deepCuts.shuffle()
            let ids = Array(deepCuts.prefix(30)).map(\.id)
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let name = "B-Sides & Obscure — \(formatter.string(from: Date()))"
            try await appState.subsonicClient.createPlaylist(name: name, songIds: ids)
            dismiss()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }

    private func generateCurated() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }
        do {
            // Mix: random + starred + recently added
            async let randomSongs = appState.subsonicClient.getRandomSongs(size: 20)
            async let starredResult = appState.subsonicClient.getStarred()
            async let recentAlbums = appState.subsonicClient.getAlbumList(type: .newest, size: 5)

            let random = (try? await randomSongs) ?? []
            let starred = (try? await starredResult)?.song ?? []
            let recent = (try? await recentAlbums) ?? []

            // Get songs from recent albums
            var recentSongs: [Song] = []
            for album in recent.prefix(3) {
                if let fullAlbum = try? await appState.subsonicClient.getAlbum(id: album.id),
                   let songs = fullAlbum.song {
                    recentSongs.append(contentsOf: songs.prefix(3))
                }
            }

            // Combine, deduplicate, shuffle
            var allSongs: [Song] = []
            var seenIds = Set<String>()
            for song in (Array(starred.shuffled().prefix(10)) + random + recentSongs)
                where seenIds.insert(song.id).inserted {
                allSongs.append(song)
            }
            allSongs.shuffle()
            let finalSongs = Array(allSongs.prefix(35))

            guard !finalSongs.isEmpty else {
                error = "Not enough songs to create a mix"
                return
            }

            let ids = finalSongs.map(\.id)
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let name = "Curated Weekly — \(formatter.string(from: Date()))"
            try await appState.subsonicClient.createPlaylist(name: name, songIds: ids)
            dismiss()
        } catch {
            self.error = ErrorPresenter.userMessage(for: error)
        }
    }
}
