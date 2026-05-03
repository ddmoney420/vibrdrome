import Foundation

// MARK: - Top-level Response Wrapper

struct SubsonicResponse: Decodable {
    let subsonicResponse: SubsonicResponseBody

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct SubsonicResponseBody: Decodable {
    let status: String
    let version: String
    let type: String?
    let serverVersion: String?
    let openSubsonic: Bool?
    let error: SubsonicAPIError?

    // Payload keys — each endpoint uses a different one
    let artists: ArtistsResponse?
    let artist: Artist?
    let album: Album?
    let song: Song?
    let searchResult3: SearchResult3?
    let playlists: PlaylistsWrapper?
    let playlist: Playlist?
    let genres: GenresWrapper?
    let starred2: Starred2?
    let albumList2: AlbumList2Response?
    let randomSongs: RandomSongsResponse?
    let internetRadioStations: InternetRadioStationsWrapper?
    let lyricsList: LyricsList?
    let playQueue: PlayQueue?
    let bookmarks: BookmarksWrapper?
    let artistInfo2: ArtistInfo2?
    let albumInfo: AlbumInfo2?
    let similarSongs2: SimilarSongs2Response?
    let topSongs: TopSongsResponse?
    let musicFolders: MusicFoldersWrapper?
    let directory: MusicDirectory?
    let indexes: IndexesResponse?
    let jukeboxStatus: JukeboxStatus?
    let jukeboxPlaylist: JukeboxPlaylist?

    enum CodingKeys: String, CodingKey {
        case status, version, type, serverVersion, openSubsonic, error
        case artists, artist, album, song, searchResult3
        case playlists, playlist, genres, starred2, albumList2, randomSongs
        case internetRadioStations, lyricsList, playQueue, bookmarks
        case artistInfo2, albumInfo, similarSongs2, topSongs
        case musicFolders, directory, indexes
        case jukeboxStatus, jukeboxPlaylist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        version = try container.decode(String.self, forKey: .version)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        serverVersion = try container.decodeIfPresent(String.self, forKey: .serverVersion)
        openSubsonic = try container.decodeIfPresent(Bool.self, forKey: .openSubsonic)
        error = try container.decodeIfPresent(SubsonicAPIError.self, forKey: .error)
        artists = try container.decodeIfPresent(ArtistsResponse.self, forKey: .artists)
        artist = try container.decodeIfPresent(Artist.self, forKey: .artist)
        album = try container.decodeIfPresent(Album.self, forKey: .album)
        song = try container.decodeIfPresent(Song.self, forKey: .song)
        searchResult3 = try container.decodeIfPresent(SearchResult3.self, forKey: .searchResult3)
        playlists = try container.decodeIfPresent(PlaylistsWrapper.self, forKey: .playlists)
        playlist = try container.decodeIfPresent(Playlist.self, forKey: .playlist)
        genres = try container.decodeIfPresent(GenresWrapper.self, forKey: .genres)
        starred2 = try container.decodeIfPresent(Starred2.self, forKey: .starred2)
        albumList2 = try container.decodeIfPresent(AlbumList2Response.self, forKey: .albumList2)
        randomSongs = try container.decodeIfPresent(RandomSongsResponse.self, forKey: .randomSongs)
        internetRadioStations = try container.decodeIfPresent(InternetRadioStationsWrapper.self, forKey: .internetRadioStations)
        lyricsList = try container.decodeIfPresent(LyricsList.self, forKey: .lyricsList)
        playQueue = try container.decodeIfPresent(PlayQueue.self, forKey: .playQueue)
        bookmarks = try container.decodeIfPresent(BookmarksWrapper.self, forKey: .bookmarks)
        artistInfo2 = try container.decodeIfPresent(ArtistInfo2.self, forKey: .artistInfo2)
        albumInfo = try container.decodeIfPresent(AlbumInfo2.self, forKey: .albumInfo)
        similarSongs2 = try container.decodeIfPresent(SimilarSongs2Response.self, forKey: .similarSongs2)
        topSongs = try container.decodeIfPresent(TopSongsResponse.self, forKey: .topSongs)
        musicFolders = try container.decodeIfPresent(MusicFoldersWrapper.self, forKey: .musicFolders)
        directory = try container.decodeIfPresent(MusicDirectory.self, forKey: .directory)
        indexes = try container.decodeIfPresent(IndexesResponse.self, forKey: .indexes)
        jukeboxStatus = try container.decodeIfPresent(JukeboxStatus.self, forKey: .jukeboxStatus)
        jukeboxPlaylist = try container.decodeIfPresent(JukeboxPlaylist.self, forKey: .jukeboxPlaylist)
    }
}

struct SubsonicAPIError: Decodable {
    let code: Int
    let message: String
}

// MARK: - Artist Models

struct ArtistIndex: Decodable, Identifiable, Sendable {
    let name: String
    let artist: [Artist]?
    var id: String { name }
}

struct ArtistsResponse: Decodable, Sendable {
    let index: [ArtistIndex]?
    let ignoredArticles: String?
}

struct Artist: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let coverArt: String?
    let albumCount: Int?
    let starred: String?
    let album: [Album]?
}

struct ArtistInfo2: Decodable, Sendable {
    let similarArtist: [Artist]?
    let biography: String?
    let musicBrainzId: String?
    let lastFmUrl: String?
    let smallImageUrl: String?
    let mediumImageUrl: String?
    let largeImageUrl: String?
}

struct AlbumInfo2: Decodable, Sendable {
    let notes: String?
    let musicBrainzId: String?
    let lastFmUrl: String?
    let smallImageUrl: String?
    let mediumImageUrl: String?
    let largeImageUrl: String?
}

// MARK: - Album Models

struct RecordLabel: Decodable, Sendable {
    let name: String
}

struct AlbumGenre: Decodable, Sendable {
    let name: String
}

struct Album: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let year: Int?
    let genre: String?
    let starred: String?
    let created: String?
    let userRating: Int?
    let song: [Song]?
    let replayGain: ReplayGain?
    let musicBrainzId: String?
    let recordLabels: [RecordLabel]?
    let genres: [AlbumGenre]?

    /// First record label name, for convenience.
    var label: String? { recordLabels?.first?.name }

    /// All genre names, deduplicated. Prefers the OpenSubsonic `genres` array when present,
    /// then falls back to `genre` / per-song genres (semicolon-split).
    var allGenres: [String] {
        if let genres, !genres.isEmpty {
            return genres.map(\.name)
        }
        var seen = Set<String>()
        var result: [String] = []
        let sources = (song ?? []).compactMap(\.genre) + [genre].compactMap { $0 }
        for raw in sources {
            for part in raw.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) })
            where !part.isEmpty && !seen.contains(part) {
                seen.insert(part)
                result.append(part)
            }
        }
        return result
    }
}

struct AlbumList2Response: Decodable, Sendable {
    let album: [Album]?
}

struct RandomSongsResponse: Decodable, Sendable {
    let song: [Song]?
}

struct SimilarSongs2Response: Decodable, Sendable {
    let song: [Song]?
}

struct TopSongsResponse: Decodable, Sendable {
    let song: [Song]?
}

// MARK: - Song Model

struct Song: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let parent: String?
    let title: String
    let album: String?
    let artist: String?
    let albumArtist: String?
    let albumId: String?
    let artistId: String?
    let track: Int?
    let year: Int?
    let genre: String?
    let coverArt: String?
    let size: Int?
    let contentType: String?
    let suffix: String?
    let duration: Int?
    let bitRate: Int?
    let path: String?
    let discNumber: Int?
    let created: String?
    let starred: String?
    let userRating: Int?
    let bpm: Int?
    let replayGain: ReplayGain?
    let musicBrainzId: String?

    init(
        id: String, parent: String? = nil, title: String, album: String? = nil,
        artist: String? = nil, albumArtist: String? = nil,
        albumId: String? = nil, artistId: String? = nil,
        track: Int? = nil, year: Int? = nil, genre: String? = nil,
        coverArt: String? = nil, size: Int? = nil,
        contentType: String? = nil, suffix: String? = nil,
        duration: Int? = nil, bitRate: Int? = nil, path: String? = nil,
        discNumber: Int? = nil, created: String? = nil,
        starred: String? = nil, userRating: Int? = nil,
        bpm: Int? = nil, replayGain: ReplayGain? = nil, musicBrainzId: String? = nil
    ) {
        self.id = id; self.parent = parent; self.title = title; self.album = album
        self.artist = artist; self.albumArtist = albumArtist
        self.albumId = albumId; self.artistId = artistId
        self.track = track; self.year = year; self.genre = genre
        self.coverArt = coverArt; self.size = size
        self.contentType = contentType; self.suffix = suffix
        self.duration = duration; self.bitRate = bitRate; self.path = path
        self.discNumber = discNumber; self.created = created
        self.starred = starred; self.userRating = userRating
        self.bpm = bpm; self.replayGain = replayGain; self.musicBrainzId = musicBrainzId
    }
}

struct ReplayGain: Decodable, Sendable, Equatable {
    let trackGain: Double?
    let albumGain: Double?
    let trackPeak: Double?
    let albumPeak: Double?
    let baseGain: Double?
}

// MARK: - Playlist Models

struct PlaylistsWrapper: Decodable, Sendable {
    let playlist: [Playlist]?
}

struct Playlist: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let songCount: Int?
    let duration: Int?
    let created: String?
    let changed: String?
    let coverArt: String?
    let owner: String?
    let isPublic: Bool?
    let entry: [Song]?

    enum CodingKeys: String, CodingKey {
        case id, name, songCount, duration, created, changed
        case coverArt, owner, entry
        case isPublic = "public"
    }
}

// MARK: - Search Results

struct SearchResult3: Decodable, Sendable {
    let artist: [Artist]?
    let album: [Album]?
    let song: [Song]?
}

// MARK: - Starred

struct Starred2: Decodable, Sendable {
    let artist: [Artist]?
    let album: [Album]?
    let song: [Song]?
}

// MARK: - Internet Radio

struct InternetRadioStationsWrapper: Decodable, Sendable {
    let internetRadioStation: [InternetRadioStation]?
}

struct InternetRadioStation: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let streamUrl: String
    let homePageUrl: String?
    let coverArt: String?

    /// Navidrome 0.61 returns coverArt as a raw filename instead of the correct
    /// ra-{id} format (issue #5293). This property returns the corrected ID.
    var radioCoverArtId: String? {
        guard coverArt != nil else { return nil }
        if let coverArt, coverArt.hasPrefix("ra-") {
            return coverArt
        }
        return "ra-\(id)"
    }
}

// MARK: - Lyrics (OpenSubsonic)

struct LyricsList: Decodable, Sendable {
    let structuredLyrics: [StructuredLyrics]?
}

struct StructuredLyrics: Decodable, Sendable {
    let displayArtist: String?
    let displayTitle: String?
    let lang: String
    let synced: Bool
    let offset: Int?
    let line: [LyricLine]?
}

struct LyricLine: Decodable, Sendable, Identifiable {
    let start: Int?
    let value: String

    // Use a UUID for stable, unique identity in ForEach
    private let _id = UUID()
    var id: UUID { _id }

    enum CodingKeys: String, CodingKey {
        case start, value
    }
}

// MARK: - Play Queue

struct PlayQueue: Decodable, Sendable {
    let current: String?
    let position: Int?
    let changed: String?
    let changedBy: String?
    let entry: [Song]?
}

// MARK: - Genres

struct GenresWrapper: Decodable, Sendable {
    let genre: [Genre]?
}

struct Genre: Decodable, Identifiable, Sendable {
    let songCount: Int?
    let albumCount: Int?
    let value: String
    var id: String { value }
}

// MARK: - Music Folders / Directory Browsing

struct MusicFoldersWrapper: Decodable, Sendable {
    let musicFolder: [MusicFolder]?
}

struct IndexesResponse: Decodable, Sendable {
    let lastModified: Int?
    let ignoredArticles: String?
    let index: [FolderIndex]?
    let child: [DirectoryChild]?
}

struct FolderIndex: Decodable, Sendable {
    let name: String
    let artist: [FolderArtist]?
}

struct FolderArtist: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let albumCount: Int?
}

struct MusicFolder: Decodable, Identifiable, Sendable {
    let id: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // id can be Int or String in Subsonic API
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

struct MusicDirectory: Decodable, Sendable {
    let id: String
    let name: String?
    let parent: String?
    let child: [DirectoryChild]?
}

struct DirectoryChild: Decodable, Identifiable, Sendable {
    let id: String
    let title: String?
    let isDir: Bool
    let artist: String?
    let album: String?
    let coverArt: String?
    let duration: Int?
    let track: Int?
    let year: Int?
    let genre: String?
    let size: Int?
    let suffix: String?
    let bitRate: Int?
    let contentType: String?
    let path: String?
    let parent: String?
    let starred: String?
    let created: String?
}

// MARK: - Jukebox

struct JukeboxStatus: Decodable, Sendable {
    let currentIndex: Int?
    let playing: Bool?
    let gain: Float?
    let position: Int?
}

struct JukeboxPlaylist: Decodable, Sendable {
    let currentIndex: Int?
    let playing: Bool?
    let gain: Float?
    let position: Int?
    let entry: [Song]?
}

// MARK: - Bookmarks

struct BookmarksWrapper: Decodable, Sendable {
    let bookmark: [Bookmark]?
}

struct Bookmark: Decodable, Sendable {
    let position: Int
    let username: String
    let comment: String?
    let created: String
    let changed: String
    let entry: Song?
}
