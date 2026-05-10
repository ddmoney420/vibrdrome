import Foundation

// MARK: - Library Pill Identifiers

enum LibraryPill: String, CaseIterable, Codable, Identifiable {
    case favorites
    case radio
    case generations
    case playlists
    case genres
    case downloads
    case artists
    case recentlyAdded
    case albums
    case recentlyPlayed
    case songs
    case randomAlbum
    case folders
    case randomMix
    case playHistory
    case smartPlaylists
    case jukebox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .radio: "Radio"
        case .generations: "Generations"
        case .playlists: "Playlists"
        case .genres: "Genres"
        case .downloads: "Downloads"
        case .artists: "Artists"
        case .recentlyAdded: "Recently Added"
        case .albums: "Albums"
        case .recentlyPlayed: "Recently Played"
        case .songs: "Songs"
        case .randomAlbum: "Random Album"
        case .folders: "Folders"
        case .randomMix: "Random Mix"
        case .playHistory: "Play History"
        case .smartPlaylists: "Smart Playlists"
        case .jukebox: "Jukebox"
        }
    }

    var icon: String {
        switch self {
        case .favorites: "heart.fill"
        case .radio: "antenna.radiowaves.left.and.right"
        case .generations: "calendar"
        case .playlists: "music.note.list"
        case .genres: "guitars.fill"
        case .downloads: "arrow.down.circle.fill"
        case .artists: "music.mic"
        case .recentlyAdded: "sparkles"
        case .albums: "square.stack.fill"
        case .recentlyPlayed: "play.circle.fill"
        case .songs: "music.note"
        case .randomAlbum: "opticaldisc.fill"
        case .folders: "folder.fill"
        case .randomMix: "dice.fill"
        case .playHistory: "clock.arrow.circlepath"
        case .smartPlaylists: "sparkles"
        case .jukebox: "hifispeaker"
        }
    }

    var color: String {
        switch self {
        case .favorites: "pink"
        case .radio: "mint"
        case .generations: "red"
        case .playlists: "purple"
        case .genres: "orange"
        case .downloads: "teal"
        case .artists: "purple"
        case .recentlyAdded: "yellow"
        case .albums: "blue"
        case .recentlyPlayed: "cyan"
        case .songs: "pink"
        case .randomAlbum: "orange"
        case .folders: "green"
        case .randomMix: "indigo"
        case .playHistory: "purple"
        case .smartPlaylists: "pink"
        case .jukebox: "orange"
        }
    }
}

// MARK: - Library Carousel Identifiers

enum LibraryCarousel: String, CaseIterable, Codable, Identifiable {
    case recentlyAdded
    case favoriteAlbums
    case mostPlayed
    case rediscover
    case randomPicks
    case recentlyPlayed
    case topArtists
    case featuredGenre

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .favoriteAlbums: "Favorite Albums"
        case .mostPlayed: "Most Played"
        case .rediscover: "Rediscover"
        case .randomPicks: "Random Picks"
        case .recentlyPlayed: "Recently Played"
        case .topArtists: "Your Top Artists"
        case .featuredGenre: "Featured Genre"
        }
    }
}

// MARK: - macOS Home Section Identifiers

enum MacHomeSection: String, CaseIterable, Codable, Identifiable {
    case quickActions
    case jumpBackIn
    case recentlyAdded
    case topArtists
    case rediscover
    case mostPlayed
    case featuredGenre
    case randomPicks
    case favoriteAlbums

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickActions: "Quick Actions"
        case .jumpBackIn: "Jump Back In"
        case .recentlyAdded: "Recently Added"
        case .topArtists: "Your Top Artists"
        case .rediscover: "Rediscover"
        case .mostPlayed: "Most Played"
        case .featuredGenre: "Featured Genre"
        case .randomPicks: "Random Picks"
        case .favoriteAlbums: "Favorite Albums"
        }
    }

    var icon: String {
        switch self {
        case .quickActions: "bolt.fill"
        case .jumpBackIn: "arrow.uturn.backward.circle.fill"
        case .recentlyAdded: "sparkles"
        case .topArtists: "music.mic"
        case .rediscover: "heart.fill"
        case .mostPlayed: "star.fill"
        case .featuredGenre: "guitars.fill"
        case .randomPicks: "dice.fill"
        case .favoriteAlbums: "heart.circle.fill"
        }
    }
}

// MARK: - macOS Home Layout Configuration

struct MacHomeLayoutConfig: Codable, Equatable {
    var visibleSections: [MacHomeSection]

    static let `default` = MacHomeLayoutConfig(
        visibleSections: [
            .quickActions,
            .jumpBackIn,
            .recentlyAdded,
            .topArtists,
            .rediscover,
            .mostPlayed,
            .featuredGenre,
            .randomPicks,
            .favoriteAlbums
        ]
    )

    static func load() -> MacHomeLayoutConfig {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.macHomeLayout),
              let config = try? JSONDecoder().decode(MacHomeLayoutConfig.self, from: data) else {
            return .default
        }
        // Forward-compat: add any new sections not in stored config
        var loaded = config
        let missing = MacHomeSection.allCases.filter { !loaded.visibleSections.contains($0) }
        loaded.visibleSections.append(contentsOf: missing)
        return loaded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.macHomeLayout)
        }
    }

    var hiddenSections: [MacHomeSection] {
        MacHomeSection.allCases.filter { !visibleSections.contains($0) }
    }
}

// MARK: - Layout Configuration

struct LibraryLayoutConfig: Codable, Equatable {
    var visiblePills: [LibraryPill]
    var visibleCarousels: [LibraryCarousel]

    static let `default` = LibraryLayoutConfig(
        visiblePills: LibraryPill.allCases,
        visibleCarousels: LibraryCarousel.allCases
    )

    // MARK: - Persistence

    static func load() -> LibraryLayoutConfig {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.libraryLayout),
              let config = try? JSONDecoder().decode(LibraryLayoutConfig.self, from: data) else {
            return .default
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.libraryLayout)
        }
    }

    var hiddenPills: [LibraryPill] {
        LibraryPill.allCases.filter { !visiblePills.contains($0) }
    }

    var hiddenCarousels: [LibraryCarousel] {
        LibraryCarousel.allCases.filter { !visibleCarousels.contains($0) }
    }
}
