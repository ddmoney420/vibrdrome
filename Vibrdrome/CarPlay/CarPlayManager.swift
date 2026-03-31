#if os(iOS)
import CarPlay

@MainActor
final class CarPlayManager {
    private let interfaceController: CPInterfaceController
    private var searchHandler: CarPlaySearchHandler?
    private var isNavigating = false
    /// Self-cleaning task set: each task removes itself on completion (C1)
    private var activeTasks: Set<UUID> = []
    private var taskMap: [UUID: Task<Void, Never>] = [:]
    private var configObservation: Task<Void, Never>?

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    func tearDown() {
        // C2: Reset navigation flag explicitly
        isNavigating = false
        // Cancel all active tasks
        for (_, task) in taskMap { task.cancel() }
        taskMap.removeAll()
        activeTasks.removeAll()
        // C5: Cancel search handler tasks
        searchHandler?.cancel()
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
                // C2: Check cancellation before pushing
                guard !Task.isCancelled else { return }
                guard let template = try await builder() else { return }
                guard !Task.isCancelled else { return }
                self.interfaceController.pushTemplate(template, animated: true) { _, _ in }
            } catch {
                // C2: Don't push error template if task was cancelled (disconnect)
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

        // Search item at the end
        let searchItem = CPListItem(text: "Search", detailText: nil, image: UIImage(systemName: "magnifyingglass"))
        searchItem.handler = { [weak self] _, completion in
            self?.showSearch()
            completion()
        }
        items.append(searchItem)

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
            let items = sorted.prefix(30).map { genre in
                let detail = genre.songCount.map { "\($0) songs" }
                let item = CPListItem(text: genre.value, detailText: detail)
                item.handler = { [weak self] _, completion in
                    self?.playGenre(genre.value)
                    completion()
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
            let sections = indexes.map { index in
                let items = (index.artist ?? []).map { artist in
                    let item = CPListItem(text: artist.name,
                                          detailText: "\(artist.albumCount ?? 0) albums")
                    item.handler = { [weak self] _, completion in
                        self?.showArtistDetail(id: artist.id)
                        completion()
                    }
                    return item
                }
                return CPListSection(items: items, header: index.name,
                                     sectionIndexTitle: index.name)
            }
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

            let trackItems = songs.map { song in
                let item = CPListItem(text: song.title,
                                      detailText: song.artist ?? album.artist ?? "")
                item.handler = { _, completion in
                    AudioEngine.shared.play(
                        song: song, from: songs,
                        at: songs.firstIndex(where: { $0.id == song.id }) ?? 0)
                    completion()
                }
                item.playingIndicatorLocation = .trailing
                return item
            }

            let playAll = CPListItem(text: "Play All",
                                     detailText: "\(songs.count) songs",
                                     image: UIImage(systemName: "play.fill"))
            playAll.handler = { _, completion in
                AudioEngine.shared.play(song: songs[0], from: songs)
                completion()
            }

            let shuffle = CPListItem(text: "Shuffle", detailText: nil,
                                     image: UIImage(systemName: "shuffle"))
            shuffle.handler = { _, completion in
                var shuffled = songs
                shuffled.shuffle()
                AudioEngine.shared.play(song: shuffled[0], from: shuffled)
                completion()
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
            let size = type == .newest
                ? max(10, UserDefaults.standard.integer(forKey: UserDefaultsKeys.carPlayRecentCount))
                : 50
            let albums = try await client.getAlbumList(type: type, size: size == 0 ? 25 : size)
            let items = albums.map { album in
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
            let title = type == .newest ? "Recently Added" : "Albums"
            return CPListTemplate(title: title,
                                  sections: [CPListSection(items: items)])
        }
    }

    // MARK: - Favorites

    private func showStarred() {
        navigateTo { [weak self] in
            let client = AppState.shared.subsonicClient
            let starred = try await client.getStarred()
            var sections: [CPListSection] = []

            if let songs = starred.song, !songs.isEmpty {
                let visibleSongs = Array(songs.prefix(20))
                let songItems = visibleSongs.map { song in
                    let item = CPListItem(text: song.title,
                                          detailText: song.artist ?? "")
                    item.handler = { _, completion in
                        AudioEngine.shared.play(
                            song: song, from: visibleSongs,
                            at: visibleSongs.firstIndex(where: { $0.id == song.id }) ?? 0)
                        completion()
                    }
                    return item
                }
                sections.append(CPListSection(items: songItems, header: "Songs",
                                              sectionIndexTitle: nil))
            }

            if let albums = starred.album, !albums.isEmpty {
                let albumItems = albums.prefix(20).map { album in
                    let item = CPListItem(text: album.name,
                                          detailText: album.artist ?? "")
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
                let items = playlists.map { playlist in
                    let item = CPListItem(text: playlist.name,
                                          detailText: "\(playlist.songCount ?? 0) songs")
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

            let trackItems = songs.map { song in
                let item = CPListItem(text: song.title,
                                      detailText: song.artist ?? "")
                item.handler = { _, completion in
                    AudioEngine.shared.play(
                        song: song, from: songs,
                        at: songs.firstIndex(where: { $0.id == song.id }) ?? 0)
                    completion()
                }
                return item
            }

            let playAll = CPListItem(text: "Play All",
                                     detailText: "\(songs.count) songs",
                                     image: UIImage(systemName: "play.fill"))
            playAll.handler = { _, completion in
                AudioEngine.shared.play(song: songs[0], from: songs)
                completion()
            }

            let shuffle = CPListItem(text: "Shuffle", detailText: nil,
                                     image: UIImage(systemName: "shuffle"))
            shuffle.handler = { _, completion in
                var shuffled = songs
                shuffled.shuffle()
                AudioEngine.shared.play(song: shuffled[0], from: shuffled)
                completion()
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

        trackTask {
            do {
                let client = AppState.shared.subsonicClient
                let stations = try await client.getRadioStations()
                guard !Task.isCancelled else { return }
                let items = stations.map { station in
                    let item = CPListItem(text: station.name, detailText: nil,
                                          image: UIImage(systemName: "radio"))
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

    private func showSearch() {
        let handler = CarPlaySearchHandler()
        self.searchHandler = handler
        let template = CPSearchTemplate()
        template.delegate = handler
        interfaceController.pushTemplate(template, animated: true) { _, _ in }
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
}
#endif
