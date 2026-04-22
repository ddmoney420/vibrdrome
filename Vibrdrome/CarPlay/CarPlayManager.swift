#if os(iOS) && CARPLAY_ENABLED
import CarPlay
import os.log
import SwiftData

@MainActor
final class CarPlayManager: NSObject {
    private let interfaceController: CPInterfaceController
    private var isNavigating = false
    /// Self-cleaning task set: each task removes itself on completion (C1)
    private var activeTasks: Set<UUID> = []
    private var taskMap: [UUID: Task<Void, Never>] = [:]
    private var configObservation: Task<Void, Never>?

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        super.init()
        configureNowPlayingTemplate()
    }

    func tearDown() {
        CPNowPlayingTemplate.shared.remove(self)
        // C2: Reset navigation flag explicitly
        isNavigating = false
        // Cancel all active tasks
        for (_, task) in taskMap { task.cancel() }
        taskMap.removeAll()
        activeTasks.removeAll()
        // C6: Stop config observation
        configObservation?.cancel()
        configObservation = nil
    }

    func setupRootTemplate() {
        guard AppState.shared.isConfigured else {
            let item = CPListItem(text: "Not Connected", detailText: "Open Vibrdrome on your phone to sign in")
            let section = CPListSection(items: [item])
            let template = CPListTemplate(title: "Vibrdrome", sections: [section])
            template.tabImage = UIImage(systemName: "music.note")
            let tabBar = CPTabBarTemplate(templates: [template])
            interfaceController.setRootTemplate(tabBar, animated: false) { _, _ in }

            // C6: Observe config changes to auto-refresh when user signs in
            configObservation?.cancel()
            configObservation = Task { [weak self] in
                // Poll for configuration change
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    if Task.isCancelled { break }
                    if AppState.shared.isConfigured {
                        self?.setupRootTemplate()
                        break
                    }
                }
            }
            return
        }

        configObservation?.cancel()
        configObservation = nil

        var tabs: [CPTemplate] = [
            makeLibraryTab(),
            makePlaylistsTab(),
        ]
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.carPlayShowRadio) ||
           !UserDefaults.standard.dictionaryRepresentation().keys.contains(UserDefaultsKeys.carPlayShowRadio) {
            // Default to showing radio (true) if key not set
            tabs.append(makeRadioTab())
        }

        // CPTabBarTemplate supports max 4 CPListTemplate tabs.
        // CPSearchTemplate is NOT valid as a tab — it must be
        // presented separately. Add search as a list item in Library instead.
        // Limit to 4 tabs max (CarPlay requirement).
        let validTabs = Array(tabs.prefix(4))
        let tabBar = CPTabBarTemplate(templates: validTabs)
        interfaceController.setRootTemplate(tabBar, animated: false) { _, _ in }
    }

    // MARK: - Now Playing Template

    private func configureNowPlayingTemplate() {
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.add(self)

        let shuffle = CPNowPlayingShuffleButton { _ in
            AudioEngine.shared.toggleShuffle()
        }
        let repeatBtn = CPNowPlayingRepeatButton { _ in
            AudioEngine.shared.cycleRepeatMode()
        }
        nowPlaying.updateNowPlayingButtons([shuffle, repeatBtn])
        nowPlaying.isUpNextButtonEnabled = true
        nowPlaying.upNextTitle = "Up Next"

        // Refresh MPNowPlayingInfoCenter in case music is already playing
        if let song = AudioEngine.shared.currentSong {
            NowPlayingManager.shared.update(song: song, isPlaying: AudioEngine.shared.isPlaying)
            NowPlayingManager.shared.updateElapsedTime(AudioEngine.shared.currentTime)
        }
    }

    private func showUpNext() {
        let engine = AudioEngine.shared
        let upcoming = engine.upNext
        guard !upcoming.isEmpty else {
            let empty = CPListTemplate(title: "Up Next", sections: [
                CPListSection(items: [CPListItem(text: "Queue is empty", detailText: nil)])
            ])
            interfaceController.pushTemplate(empty, animated: true) { _, _ in }
            return
        }

        let items = upcoming.prefix(30).enumerated().map { offset, song in
            let item = CPListItem(text: song.title, detailText: song.artist ?? "")
            if let coverArtId = song.coverArt {
                loadImage(id: coverArtId, size: 120, into: item)
            }
            item.handler = { _, completion in
                engine.skipToIndex(engine.currentIndex + 1 + offset)
                completion()
            }
            return item
        }

        let template = CPListTemplate(
            title: "Up Next", sections: [CPListSection(items: items)]
        )
        interfaceController.pushTemplate(template, animated: true) { _, _ in }
    }

    // MARK: - Task Tracking (C1)

    /// Track a task that auto-removes itself on completion
    @discardableResult
    private func trackTask(_ work: @escaping @MainActor () async -> Void) -> UUID {
        let id = UUID()
        activeTasks.insert(id)
        let task = Task { [weak self] in
            await work()
            self?.activeTasks.remove(id)
            self?.taskMap.removeValue(forKey: id)
        }
        taskMap[id] = task
        return id
    }

    // MARK: - Navigation Guard

    private func navigateTo(_ builder: @escaping @MainActor () async throws -> CPListTemplate?) {
        guard !isNavigating else { return }
        isNavigating = true

        trackTask { [weak self] in
            guard let self else { return }
            defer { self.isNavigating = false }
            do {
                guard !Task.isCancelled else { return }
                guard let template = try await builder() else { return }
                guard !Task.isCancelled else { return }
                self.interfaceController.pushTemplate(template, animated: true) { _, _ in }
            } catch {
                guard !Task.isCancelled else { return }
                let errorTemplate = CPListTemplate(
                    title: "Error",
                    sections: [CPListSection(items: [
                        CPListItem(text: "Could not load", detailText: nil)
                    ])]
                )
                self.interfaceController.pushTemplate(errorTemplate, animated: true) { _, _ in }
            }
        }
    }

    // MARK: - Library Tab

    private func makeLibraryTab() -> CPListTemplate {
        var items = [
            CPListItem(text: "Artists", detailText: nil, image: UIImage(systemName: "music.mic")),
            CPListItem(text: "Albums", detailText: nil, image: UIImage(systemName: "square.stack")),
            CPListItem(text: "Recently Added", detailText: nil, image: UIImage(systemName: "clock")),
            CPListItem(text: "Favorites", detailText: nil, image: UIImage(systemName: "heart.fill")),
            CPListItem(text: "Random", detailText: nil, image: UIImage(systemName: "shuffle")),
        ]

        items[0].handler = { [weak self] _, completion in
            self?.showArtists()
            completion()
        }
        items[1].handler = { [weak self] _, completion in
            self?.showAlbums(type: .alphabeticalByName)
            completion()
        }
        items[2].handler = { [weak self] _, completion in
            self?.showAlbums(type: .newest)
            completion()
        }
        items[3].handler = { [weak self] _, completion in
            self?.showStarred()
            completion()
        }
        items[4].handler = { [weak self] _, completion in
            self?.playRandom()
            completion()
        }

        // Add Genres if setting is enabled (default: true)
        let showGenres = UserDefaults.standard.bool(forKey: UserDefaultsKeys.carPlayShowGenres) ||
            !UserDefaults.standard.dictionaryRepresentation().keys.contains(UserDefaultsKeys.carPlayShowGenres)
        if showGenres {
            let genreItem = CPListItem(text: "Genres", detailText: nil, image: UIImage(systemName: "guitars"))
            genreItem.handler = { [weak self] _, completion in
                self?.showGenres()
                completion()
            }
            items.insert(genreItem, at: 3)
        }

        // Now Playing item
        let nowPlayingItem = CPListItem(
            text: "Now Playing", detailText: nil,
            image: UIImage(systemName: "play.circle.fill")
        )
        nowPlayingItem.handler = { [weak self] _, completion in
            self?.interfaceController.pushTemplate(
                CPNowPlayingTemplate.shared, animated: true
            ) { _, _ in }
            completion()
        }
        items.append(nowPlayingItem)

        // Search item at the end
        let recentItem = CPListItem(text: "Recently Played", detailText: nil, image: UIImage(systemName: "clock.arrow.circlepath"))
        recentItem.handler = { [weak self] _, completion in
            self?.showRecentlyPlayed()
            completion()
        }
        items.append(recentItem)

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Library", sections: [section])
        template.tabImage = UIImage(systemName: "music.note.house")
        return template
    }

    private func showGenres() {
        navigateTo { [weak self] in
            let client = AppState.shared.subsonicClient
            let genres = try await client.getGenres()
            let sorted = genres.sorted { ($0.songCount ?? 0) > ($1.songCount ?? 0) }
            let context = PersistenceController.shared.container.mainContext
            let cached = (try? context.fetch(FetchDescriptor<GenreArtwork>())) ?? []
            let coverArtByGenre = Dictionary(
                cached.map { ($0.genre, $0.coverArtId) },
                uniquingKeysWith: { first, _ in first }
            )

            // Use an SF Symbol as the instant fallback instead of rendering
            // GenreIconView through ImageRenderer for every row. For large
            // genre libraries (50+) the per-row SwiftUI render was blocking
            // the CarPlay main actor long enough to trip the scene watchdog
            // and crash the app on Genres tap. The real album art still
            // loads async below and replaces the symbol when ready.
            let symbolFallback = UIImage(systemName: "guitars")
            let items = sorted.map { genre -> CPListItem in
                let detail = genre.songCount.map { "\($0) songs" }
                let item = CPListItem(text: genre.value, detailText: detail,
                                      image: symbolFallback)
                item.handler = { [weak self] _, completion in
                    self?.playGenre(genre.value)
                    completion()
                }
                if let coverArtId = coverArtByGenre[genre.value] {
                    let url = client.coverArtURL(id: coverArtId, size: 200)
                    Task {
                        if let (data, _) = try? await URLSession.shared.data(from: url),
                           let image = UIImage(data: data) {
                            item.setImage(image)
                        }
                    }
                }
                return item
            }
            return CPListTemplate(title: "Genres",
                                  sections: [CPListSection(items: items)])
        }
    }

    private func playGenre(_ genre: String) {
        trackTask {
            do {
                let client = AppState.shared.subsonicClient
                let songs = try await client.getRandomSongs(size: 30, genre: genre)
                guard let first = songs.first else { return }
                AudioEngine.shared.play(song: first, from: songs)
            } catch {
                print("Genre play failed: \(ErrorPresenter.userMessage(for: error))")
            }
        }
    }

    // MARK: - Artists drill-down

    private func showArtists() {
        navigateTo { [weak self] in
            let client = AppState.shared.subsonicClient
            let indexes = try await client.getArtists()
            let buckets: [(letter: String, items: [CPListItem])] = indexes.map { index in
                let items = (index.artist ?? []).map { artist -> CPListItem in
                    let item = CPListItem(text: artist.name,
                                          detailText: "\(artist.albumCount ?? 0) albums")
                    item.handler = { [weak self] _, completion in
                        self?.showArtistDetail(id: artist.id)
                        completion()
                    }
                    return item
                }
                return (letter: index.name, items: items)
            }
            let sections = self?.fitAlphabetSections(buckets: buckets) ?? []
            return CPListTemplate(title: "Artists", sections: sections)
        }
    }

    private func showArtistDetail(id: String) {
        navigateTo { [weak self] in
            let client = AppState.shared.subsonicClient
            let artist = try await client.getArtist(id: id)

            // Artist Radio button
            let radioItem = CPListItem(text: "Start Radio",
                                       detailText: "Mix based on \(artist.name)",
                                       image: UIImage(systemName: "dot.radiowaves.left.and.right"))
            radioItem.handler = { _, completion in
                AudioEngine.shared.startRadio(artistName: artist.name)
                completion()
            }

            let albumItems = (artist.album ?? []).map { album in
                let item = CPListItem(text: album.name,
                                      detailText: album.year.map { String($0) })
                if let coverArtId = album.coverArt {
                    self?.loadImage(id: coverArtId, size: 120, into: item)
                }
                item.handler = { [weak self] _, completion in
                    self?.showAlbumDetail(id: album.id)
                    completion()
                }
                return item
            }

            let sections = [
                CPListSection(items: [radioItem]),
                CPListSection(items: albumItems, header: "Albums",
                              sectionIndexTitle: nil),
            ]
            return CPListTemplate(title: artist.name, sections: sections)
        }
    }

    private func showAlbumDetail(id: String) {
        navigateTo {
            let client = AppState.shared.subsonicClient
            let album = try await client.getAlbum(id: id)
            guard let songs = album.song, !songs.isEmpty else {
                return CPListTemplate(title: album.name, sections: [
                    CPListSection(items: [CPListItem(text: "No songs", detailText: nil)])
                ])
            }

            let trackItems = songs.map { [weak self] song in
                let item = CPListItem(text: song.title,
                                      detailText: song.artist ?? album.artist ?? "")
                if let coverArtId = song.coverArt ?? album.coverArt {
                    self?.loadImage(id: coverArtId, size: 120, into: item)
                }
                item.handler = { [weak self] _, completion in
                    AudioEngine.shared.play(
                        song: song, from: songs,
                        at: songs.firstIndex(where: { $0.id == song.id }) ?? 0)
                    completion()
                    self?.pushNowPlaying()
                }
                item.playingIndicatorLocation = .trailing
                return item
            }

            let playAll = CPListItem(text: "Play All",
                                     detailText: "\(songs.count) songs",
                                     image: UIImage(systemName: "play.fill"))
            playAll.handler = { [weak self] _, completion in
                if let first = songs.first { AudioEngine.shared.play(song: first, from: songs) }
                completion()
                self?.pushNowPlaying()
            }

            let shuffle = CPListItem(text: "Shuffle", detailText: nil,
                                     image: UIImage(systemName: "shuffle"))
            shuffle.handler = { [weak self] _, completion in
                var shuffled = songs
                shuffled.shuffle()
                if let first = shuffled.first { AudioEngine.shared.play(song: first, from: shuffled) }
                completion()
                self?.pushNowPlaying()
            }

            let sections = [
                CPListSection(items: [playAll, shuffle]),
                CPListSection(items: trackItems, header: album.name,
                              sectionIndexTitle: nil),
            ]
            return CPListTemplate(title: album.name, sections: sections)
        }
    }

    // MARK: - Albums

    private func showAlbums(type: AlbumListType) {
        navigateTo { [weak self] in
            let client = AppState.shared.subsonicClient
            let maxItems = max(1, Int(CPListTemplate.maximumItemCount))

            if type == .newest {
                let recent = max(10, UserDefaults.standard.integer(forKey: UserDefaultsKeys.carPlayRecentCount))
                let size = min(recent == 0 ? 25 : recent, maxItems)
                let albums = try await client.getAlbumList(type: type, size: size)
                let items = albums.map { album -> CPListItem in
                    let item = CPListItem(text: album.name,
                                          detailText: album.artist ?? "")
                    if let coverArtId = album.coverArt {
                        self?.loadImage(id: coverArtId, size: 120, into: item)
                    }
                    item.handler = { [weak self] _, completion in
                        self?.showAlbumDetail(id: album.id)
                        completion()
                    }
                    return item
                }
                return CPListTemplate(title: "Recently Added",
                                      sections: [CPListSection(items: items)])
            }

            // Alphabetical albums: paginate Subsonic's 500-per-call limit up to
            // CarPlay's maximumItemCount, then bucket by first letter so the
            // sidebar gives a usable A-Z jump instead of a flat 50-album wall.
            var albums: [Album] = []
            let pageSize = 500
            var offset = 0
            while albums.count < maxItems {
                let page = try await client.getAlbumList(type: type,
                                                         size: pageSize,
                                                         offset: offset)
                if page.isEmpty { break }
                albums.append(contentsOf: page)
                if page.count < pageSize { break }
                offset += pageSize
            }
            albums = Array(albums.prefix(maxItems))

            var letterOrder: [String] = []
            var byLetter: [String: [CPListItem]] = [:]
            for album in albums {
                let letter = Self.bucketLetter(for: album.name)
                if byLetter[letter] == nil {
                    byLetter[letter] = []
                    letterOrder.append(letter)
                }
                let item = CPListItem(text: album.name,
                                      detailText: album.artist ?? "")
                if let coverArtId = album.coverArt {
                    self?.loadImage(id: coverArtId, size: 120, into: item)
                }
                item.handler = { [weak self] _, completion in
                    self?.showAlbumDetail(id: album.id)
                    completion()
                }
                byLetter[letter]?.append(item)
            }
            let buckets = letterOrder.map { (letter: $0, items: byLetter[$0] ?? []) }
            let sections = self?.fitAlphabetSections(buckets: buckets) ?? []
            return CPListTemplate(title: "Albums", sections: sections)
        }
    }

    // MARK: - Favorites

    /// Split CarPlay's total-item budget between Favorites' songs and albums
    /// sections. When both are present each gets half; when only one is present
    /// it claims the whole budget. Avoids silent truncation at the prior 200
    /// hard cap.
    private static func starredBudgets(
        songCount: Int, albumCount: Int
    ) -> (songs: Int, albums: Int) {
        let total = max(1, Int(CPListTemplate.maximumItemCount))
        switch (songCount > 0, albumCount > 0) {
        case (true, true): return (total / 2, total - total / 2)
        case (true, false): return (total, 0)
        case (false, true): return (0, total)
        case (false, false): return (0, 0)
        }
    }

    private func showStarred() {
        navigateTo { [weak self] in
            let client = AppState.shared.subsonicClient
            let starred = try await client.getStarred()
            var sections: [CPListSection] = []

            let budgets = Self.starredBudgets(
                songCount: starred.song?.count ?? 0,
                albumCount: starred.album?.count ?? 0)
            let songsBudget = budgets.songs
            let albumsBudget = budgets.albums

            if let songs = starred.song, !songs.isEmpty {
                let visibleSongs = Array(songs.prefix(songsBudget))
                let songItems = visibleSongs.map { [weak self] song in
                    let item = CPListItem(text: song.title,
                                          detailText: song.artist ?? "")
                    if let coverArtId = song.coverArt {
                        self?.loadImage(id: coverArtId, size: 120, into: item)
                    }
                    item.handler = { [weak self] _, completion in
                        AudioEngine.shared.play(
                            song: song, from: visibleSongs,
                            at: visibleSongs.firstIndex(where: { $0.id == song.id }) ?? 0)
                        completion()
                        self?.pushNowPlaying()
                    }
                    return item
                }
                sections.append(CPListSection(items: songItems, header: "Songs",
                                              sectionIndexTitle: nil))
            }

            if let albums = starred.album, !albums.isEmpty {
                let albumItems = albums.prefix(albumsBudget).map { [weak self] album in
                    let item = CPListItem(text: album.name,
                                          detailText: album.artist ?? "")
                    if let coverArtId = album.coverArt {
                        self?.loadImage(id: coverArtId, size: 120, into: item)
                    }
                    item.handler = { [weak self] _, completion in
                        self?.showAlbumDetail(id: album.id)
                        completion()
                    }
                    return item
                }
                sections.append(CPListSection(items: albumItems, header: "Albums",
                                              sectionIndexTitle: nil))
            }

            if sections.isEmpty {
                sections.append(CPListSection(items: [
                    CPListItem(text: "No favorites yet", detailText: nil)
                ]))
            }

            return CPListTemplate(title: "Favorites", sections: sections)
        }
    }

    // MARK: - Random

    private func playRandom() {
        // C7: Show error feedback instead of silent swallow
        trackTask {
            do {
                let client = AppState.shared.subsonicClient
                let songs = try await client.getRandomSongs(size: 20)
                guard let first = songs.first else { return }
                AudioEngine.shared.play(song: first, from: songs)
            } catch {
                // Can't push a template for a non-navigation action,
                // but at least log it for diagnostics
                print("Random play failed: \(ErrorPresenter.userMessage(for: error))")
            }
        }
    }

    // MARK: - Playlists Tab

    private func makePlaylistsTab() -> CPListTemplate {
        let template = CPListTemplate(title: "Playlists", sections: [])
        template.tabImage = UIImage(systemName: "music.note.list")

        trackTask { [weak self] in
            do {
                let client = AppState.shared.subsonicClient
                let playlists = try await client.getPlaylists()
                // C16: Check cancellation before updating template
                guard !Task.isCancelled else { return }
                let items = playlists.map { [weak self] playlist in
                    let item = CPListItem(text: playlist.name,
                                          detailText: "\(playlist.songCount ?? 0) songs")
                    if let coverArtId = playlist.coverArt {
                        self?.loadImage(id: coverArtId, size: 120, into: item)
                    }
                    item.handler = { [weak self] _, completion in
                        self?.showPlaylistDetail(id: playlist.id)
                        completion()
                    }
                    return item
                }
                template.updateSections([CPListSection(items: items)])
            } catch {
                guard !Task.isCancelled else { return }
                template.updateSections([CPListSection(items: [
                    CPListItem(text: "Could not load playlists", detailText: nil)
                ])])
            }
        }

        return template
    }

    private func showPlaylistDetail(id: String) {
        navigateTo {
            let client = AppState.shared.subsonicClient
            let playlist = try await client.getPlaylist(id: id)
            guard let songs = playlist.entry, !songs.isEmpty else {
                return CPListTemplate(title: playlist.name, sections: [
                    CPListSection(items: [CPListItem(text: "No songs", detailText: nil)])
                ])
            }

            let trackItems = songs.map { [weak self] song in
                let item = CPListItem(text: song.title,
                                      detailText: song.artist ?? "")
                if let coverArtId = song.coverArt {
                    self?.loadImage(id: coverArtId, size: 120, into: item)
                }
                item.handler = { [weak self] _, completion in
                    AudioEngine.shared.play(
                        song: song, from: songs,
                        at: songs.firstIndex(where: { $0.id == song.id }) ?? 0)
                    completion()
                    self?.pushNowPlaying()
                }
                return item
            }

            let playAll = CPListItem(text: "Play All",
                                     detailText: "\(songs.count) songs",
                                     image: UIImage(systemName: "play.fill"))
            playAll.handler = { [weak self] _, completion in
                if let first = songs.first { AudioEngine.shared.play(song: first, from: songs) }
                completion()
                self?.pushNowPlaying()
            }

            let shuffle = CPListItem(text: "Shuffle", detailText: nil,
                                     image: UIImage(systemName: "shuffle"))
            shuffle.handler = { [weak self] _, completion in
                var shuffled = songs
                shuffled.shuffle()
                if let first = shuffled.first { AudioEngine.shared.play(song: first, from: shuffled) }
                completion()
                self?.pushNowPlaying()
            }

            let sections = [
                CPListSection(items: [playAll, shuffle]),
                CPListSection(items: trackItems, header: playlist.name,
                              sectionIndexTitle: nil),
            ]
            return CPListTemplate(title: playlist.name, sections: sections)
        }
    }

    // MARK: - Radio Tab

    private func makeRadioTab() -> CPListTemplate {
        let template = CPListTemplate(title: "Radio", sections: [])
        template.tabImage = UIImage(systemName: "antenna.radiowaves.left.and.right")

        trackTask { [weak self] in
            do {
                let client = AppState.shared.subsonicClient
                let stations = try await client.getRadioStations()
                guard !Task.isCancelled else { return }

                // Single flat list — CarPlay's CPListTemplate supports up to
                // ~500 items across a template. Earlier multi-section chunking
                // with "1-20 of N" headers didn't scroll past the first section
                // on some head units, hiding stations from the user.
                let items = stations.map { station -> CPListItem in
                    let item = CPListItem(text: station.name, detailText: nil,
                                          image: UIImage(systemName: "radio"))
                    if let artId = station.radioCoverArtId {
                        self?.loadImage(id: artId, size: 120, into: item)
                    } else if let host = station.homePageUrl.flatMap({ URL(string: $0)?.host }) {
                        self?.loadFavicon(host: host, into: item)
                    }
                    item.handler = { _, completion in
                        AudioEngine.shared.playRadio(station: station)
                        completion()
                    }
                    return item
                }
                template.updateSections([CPListSection(items: items)])
            } catch {
                guard !Task.isCancelled else { return }
                template.updateSections([CPListSection(items: [
                    CPListItem(text: "Could not load stations", detailText: nil)
                ])])
            }
        }

        return template
    }

    // MARK: - Search

    private func showRecentlyPlayed() {
        navigateTo { [weak self] in
            let songs = AudioEngine.shared.recentlyPlayed
            guard !songs.isEmpty else {
                return CPListTemplate(title: "Recently Played", sections: [
                    CPListSection(items: [
                        CPListItem(text: "No recent songs", detailText: "Start playing to build history"),
                    ]),
                ])
            }
            let items = songs.prefix(30).map { song in
                let item = CPListItem(text: song.title, detailText: song.artist ?? "")
                if let coverArtId = song.coverArt {
                    self?.loadImage(id: coverArtId, size: 120, into: item)
                }
                item.handler = { _, completion in
                    AudioEngine.shared.play(song: song, from: Array(songs))
                    completion()
                }
                return item
            }
            return CPListTemplate(
                title: "Recently Played",
                sections: [CPListSection(items: items)]
            )
        }
    }

    // MARK: - Now Playing Navigation

    /// Push the Now Playing template after starting playback from a track list
    private func pushNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        // Only push if not already showing
        if interfaceController.topTemplate !== nowPlaying {
            interfaceController.pushTemplate(nowPlaying, animated: true) { _, _ in }
        }
    }

    // MARK: - Helpers

    private func loadImage(id: String, size: Int, into item: CPListItem) {
        let url = AppState.shared.subsonicClient.coverArtURL(id: id, size: size)
        trackTask {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                item.setImage(image)
            }
        }
    }

    private func loadFavicon(host: String, into item: CPListItem) {
        guard let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") else { return }
        trackTask {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                item.setImage(image)
            }
        }
    }

    // MARK: - Alphabet bucketing

    /// Build CPListSections from already-letter-grouped buckets, respecting
    /// CarPlay's runtime caps on sections and total items. When the number of
    /// letter buckets exceeds `maximumSectionCount`, consecutive letters are
    /// merged into ranges (e.g. "A-F") so the first-letter sidebar still covers
    /// the whole alphabet. Total items are clamped to `maximumItemCount` across
    /// all sections -- CarPlay silently drops overflow otherwise.
    private func fitAlphabetSections(
        buckets: [(letter: String, items: [CPListItem])]
    ) -> [CPListSection] {
        let maxSections = max(1, Int(CPListTemplate.maximumSectionCount))
        let maxItems = max(1, Int(CPListTemplate.maximumItemCount))

        var clamped: [(letter: String, items: [CPListItem])] = []
        var running = 0
        for bucket in buckets {
            let remaining = maxItems - running
            if remaining <= 0 { break }
            if bucket.items.count <= remaining {
                clamped.append(bucket)
                running += bucket.items.count
            } else {
                clamped.append((letter: bucket.letter,
                                items: Array(bucket.items.prefix(remaining))))
                break
            }
        }

        guard !clamped.isEmpty else { return [] }

        if clamped.count <= maxSections {
            return clamped.map { bucket in
                CPListSection(items: bucket.items, header: bucket.letter,
                              sectionIndexTitle: bucket.letter)
            }
        }

        let groupSize = Int((Double(clamped.count) / Double(maxSections)).rounded(.up))
        var merged: [CPListSection] = []
        var index = 0
        while index < clamped.count {
            let upper = min(index + groupSize, clamped.count)
            let slice = clamped[index..<upper]
            let firstLetter = slice.first!.letter
            let lastLetter = slice.last!.letter
            let header = firstLetter == lastLetter
                ? firstLetter
                : "\(firstLetter)-\(lastLetter)"
            let items = slice.flatMap { $0.items }
            merged.append(CPListSection(items: items, header: header,
                                        sectionIndexTitle: firstLetter))
            index = upper
        }
        return merged
    }

    /// Normalize a string's first character into an alphabet bucket label.
    /// Letters are uppercased; anything else (digits, symbols, empty) goes to "#".
    private static func bucketLetter(for name: String) -> String {
        guard let first = name.first, first.isLetter else { return "#" }
        return String(first).uppercased()
    }
}

// MARK: - Now Playing Observer

extension CarPlayManager: CPNowPlayingTemplateObserver {
    nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Task { @MainActor in
            showUpNext()
        }
    }

    nonisolated func nowPlayingTemplateAlbumArtistButtonTapped(
        _ nowPlayingTemplate: CPNowPlayingTemplate
    ) {}
}
#endif
