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
    let artistImageUrl: String?
    let albumCount: Int?
    let starred: String?
    let userRating: Int?
    let averageRating: Double?
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

struct RecordLabel: Decodable, Sendable, Equatable {
    let name: String
}

/// OpenSubsonic genre tag on an album or song (name-keyed, distinct from the library Genre type).
struct ItemGenre: Decodable, Sendable, Equatable {
    let name: String
}

/// OpenSubsonic ArtistID3 — artist reference as returned in album and artist browse responses.
struct ArtistID3: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let coverArt: String?
    let artistImageUrl: String?
    let albumCount: Int?
    let starred: String?
    let musicBrainzId: String?
    let sortName: String?
    let roles: [String]?
}

/// OpenSubsonic partial date (year/month/day all optional).
struct ItemDate: Decodable, Sendable, Equatable {
    let year: Int?
    let month: Int?
    let day: Int?
}

/// OpenSubsonic disc title entry.
struct DiscTitle: Decodable, Sendable, Equatable {
    let disc: Int
    let title: String
    let coverArt: String?
}

/// OpenSubsonic contributor artist for a song (composer, performer, lyricist, etc.).
struct Contributor: Decodable, Sendable, Equatable {
    let role: String
    let subRole: String?
    let artist: ArtistID3
}

/// OpenSubsonic work associated with a song (classical music).
struct Work: Decodable, Sendable, Equatable {
    let name: String
    let musicBrainzId: String?
}

/// OpenSubsonic movement associated with a song (classical music).
struct Movement: Decodable, Sendable, Equatable {
    let name: String
    let number: Int?
    let count: Int?
}

struct Album: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    /// OpenSubsonic: per-album artist list. When present (and count > 1), each entry
    /// gets its own tappable link instead of routing everything through `artistId`.
    let artists: [ArtistID3]?
    /// OpenSubsonic: consolidated display string (e.g. "Varg²™ & DJ Smokey").
    let displayArtist: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let playCount: Int?
    let year: Int?
    let genre: String?
    let genres: [ItemGenre]?
    let starred: String?
    let played: String?
    let created: String?
    let userRating: Int?
    let song: [Song]?
    let replayGain: ReplayGain?
    let musicBrainzId: String?
    let recordLabels: [RecordLabel]?
    let version: String?
    let releaseTypes: [String]?
    let moods: [String]?
    let sortName: String?
    let originalReleaseDate: ItemDate?
    let releaseDate: ItemDate?
    let isCompilation: Bool?
    let explicitStatus: String?
    let discTitles: [DiscTitle]?

    /// Title without the edition suffix, for display only. Both the Subsonic and Navidrome
    /// native APIs include the edition in `name` (e.g. `"Heroes" (West Germany)`); this
    /// strips it so the title and edition can be shown on separate lines.
    var displayTitle: String {
        guard let ed = version, !ed.isEmpty else { return name }
        for suffix in [" (\(ed))", " [\(ed)]"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    /// First record label name, for convenience.
    var label: String? { recordLabels?.first?.name }

    /// All genres for this album. Prefers the OpenSubsonic `genres` array when present;
    /// falls back to the legacy single `genre` string.
    var allGenres: [String] {
        if let items = genres, !items.isEmpty {
            return items.map(\.name)
        }
        return genre.map { [$0] } ?? []
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

/// Lightweight artist reference used in the OpenSubsonic `artists` array on a song.
struct SongArtist: Decodable, Sendable, Equatable {
    let id: String
    let name: String
}

struct Song: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let parent: String?
    let title: String
    let album: String?
    let artist: String?
    let albumArtist: String?
    let albumId: String?
    let artistId: String?
    /// OpenSubsonic extension: per-track artists list. When present and non-empty,
    /// prefer over `artist` for display (fixes VA albums where `artist` = "Various Artists").
    let artists: [SongArtist]?
    /// OpenSubsonic: single-value display artist string from server (raw decoded value).
    private let _displayArtist: String?
    /// OpenSubsonic: album artist credits separate from track artists.
    let albumArtists: [ArtistID3]?
    /// OpenSubsonic: single-value display album artist string from server.
    let displayAlbumArtist: String?
    /// OpenSubsonic: contributor credits (composer, lyricist, performer, etc.).
    let contributors: [Contributor]?
    /// OpenSubsonic: single-value display composer string from server.
    let displayComposer: String?
    /// Pre-joined display name sourced from `artists`; set when reconstructing from cache.
    let displayArtistOverride: String?
    let track: Int?
    let year: Int?
    let genre: String?
    /// OpenSubsonic: genre array. Prefer over legacy `genre` string when present.
    let genres: [ItemGenre]?
    let coverArt: String?
    let size: Int?
    let contentType: String?
    let suffix: String?
    let duration: Int?
    let bitRate: Int?
    let bitDepth: Int?
    let samplingRate: Int?
    let channelCount: Int?
    let comment: String?
    let path: String?
    let discNumber: Int?
    let created: String?
    /// OpenSubsonic: ISO 8601 date the song was last played on the server.
    let played: String?
    let starred: String?
    let userRating: Int?
    let playCount: Int64?
    let bpm: Int?
    let replayGain: ReplayGain?
    let musicBrainzId: String?
    /// OpenSubsonic: ISRC codes for this track.
    let isrc: [String]?
    let sortName: String?
    let mediaType: String?
    let type: String?
    /// OpenSubsonic: mood/style tags.
    let moods: [String]?
    /// OpenSubsonic: "explicit", "clean", or "".
    let explicitStatus: String?
    /// OpenSubsonic: classical music works.
    let works: [Work]?
    /// OpenSubsonic: classical music movements.
    let movements: [Movement]?
    /// OpenSubsonic: grouping tags.
    let groupings: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, parent, title, album, artist, albumArtist, albumId, artistId
        case artists
        case _displayArtist = "displayArtist"
        case albumArtists, displayAlbumArtist
        case contributors, displayComposer
        case track, year, genre, genres, coverArt, size, contentType, suffix
        case duration, bitRate, bitDepth, samplingRate, channelCount, comment
        case path, discNumber, created, played, starred, userRating, playCount
        case bpm, replayGain, musicBrainzId, isrc, sortName, mediaType, type
        case moods, explicitStatus, works, movements, groupings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        title = try c.decode(String.self, forKey: .title)
        album = try c.decodeIfPresent(String.self, forKey: .album)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        albumArtist = try c.decodeIfPresent(String.self, forKey: .albumArtist)
        albumId = try c.decodeIfPresent(String.self, forKey: .albumId)
        artistId = try c.decodeIfPresent(String.self, forKey: .artistId)
        artists = try c.decodeIfPresent([SongArtist].self, forKey: .artists)
        _displayArtist = try c.decodeIfPresent(String.self, forKey: ._displayArtist)
        albumArtists = try c.decodeIfPresent([ArtistID3].self, forKey: .albumArtists)
        displayAlbumArtist = try c.decodeIfPresent(String.self, forKey: .displayAlbumArtist)
        contributors = try c.decodeIfPresent([Contributor].self, forKey: .contributors)
        displayComposer = try c.decodeIfPresent(String.self, forKey: .displayComposer)
        displayArtistOverride = nil
        track = try c.decodeIfPresent(Int.self, forKey: .track)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        genres = try c.decodeIfPresent([ItemGenre].self, forKey: .genres)
        coverArt = try c.decodeIfPresent(String.self, forKey: .coverArt)
        size = try c.decodeIfPresent(Int.self, forKey: .size)
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType)
        suffix = try c.decodeIfPresent(String.self, forKey: .suffix)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        bitRate = try c.decodeIfPresent(Int.self, forKey: .bitRate)
        bitDepth = try c.decodeIfPresent(Int.self, forKey: .bitDepth)
        samplingRate = try c.decodeIfPresent(Int.self, forKey: .samplingRate)
        channelCount = try c.decodeIfPresent(Int.self, forKey: .channelCount)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        discNumber = try c.decodeIfPresent(Int.self, forKey: .discNumber)
        created = try c.decodeIfPresent(String.self, forKey: .created)
        played = try c.decodeIfPresent(String.self, forKey: .played)
        starred = try c.decodeIfPresent(String.self, forKey: .starred)
        userRating = try c.decodeIfPresent(Int.self, forKey: .userRating)
        playCount = try c.decodeIfPresent(Int64.self, forKey: .playCount)
        bpm = try c.decodeIfPresent(Int.self, forKey: .bpm)
        replayGain = try c.decodeIfPresent(ReplayGain.self, forKey: .replayGain)
        musicBrainzId = try c.decodeIfPresent(String.self, forKey: .musicBrainzId)
        isrc = try c.decodeIfPresent([String].self, forKey: .isrc)
        sortName = try c.decodeIfPresent(String.self, forKey: .sortName)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        moods = try c.decodeIfPresent([String].self, forKey: .moods)
        explicitStatus = try c.decodeIfPresent(String.self, forKey: .explicitStatus)
        works = try c.decodeIfPresent([Work].self, forKey: .works)
        movements = try c.decodeIfPresent([Movement].self, forKey: .movements)
        groupings = try c.decodeIfPresent([String].self, forKey: .groupings)
    }

    /// Resolved display artist for UI. Resolution order:
    /// 1. Cache override (set when reconstructing from local store)
    /// 2. Server `displayArtist` field (OpenSubsonic)
    /// 3. Joined `artists` array (OpenSubsonic per-track credits)
    /// 4. Legacy `artist` string
    var displayArtist: String? {
        if let override = displayArtistOverride, !override.isEmpty { return override }
        if let da = _displayArtist, !da.isEmpty { return da }
        if let names = artists?.map(\.name), !names.isEmpty {
            return names.joined(separator: ", ")
        }
        return artist
    }

    /// All genres for this song. Prefers the OpenSubsonic `genres` array; falls back to
    /// the legacy single `genre` string.
    var allGenres: [String] {
        if let items = genres, !items.isEmpty { return items.map(\.name) }
        return genre.map { [$0] } ?? []
    }

    init(
        id: String, parent: String? = nil, title: String, album: String? = nil,
        artist: String? = nil, albumArtist: String? = nil,
        albumId: String? = nil, artistId: String? = nil,
        artists: [SongArtist]? = nil,
        serverDisplayArtist: String? = nil,
        albumArtists: [ArtistID3]? = nil, displayAlbumArtist: String? = nil,
        contributors: [Contributor]? = nil, displayComposer: String? = nil,
        displayArtistOverride: String? = nil,
        track: Int? = nil, year: Int? = nil, genre: String? = nil, genres: [ItemGenre]? = nil,
        coverArt: String? = nil, size: Int? = nil,
        contentType: String? = nil, suffix: String? = nil,
        duration: Int? = nil, bitRate: Int? = nil,
        bitDepth: Int? = nil, samplingRate: Int? = nil, channelCount: Int? = nil,
        comment: String? = nil,
        path: String? = nil, discNumber: Int? = nil, created: String? = nil,
        played: String? = nil,
        starred: String? = nil, userRating: Int? = nil, playCount: Int64? = nil,
        bpm: Int? = nil, replayGain: ReplayGain? = nil, musicBrainzId: String? = nil,
        isrc: [String]? = nil, sortName: String? = nil,
        mediaType: String? = nil, type: String? = nil,
        moods: [String]? = nil, explicitStatus: String? = nil,
        works: [Work]? = nil, movements: [Movement]? = nil, groupings: [String]? = nil
    ) {
        self.id = id; self.parent = parent; self.title = title; self.album = album
        self.artist = artist; self.albumArtist = albumArtist
        self.albumId = albumId; self.artistId = artistId
        self.artists = artists
        self._displayArtist = serverDisplayArtist
        self.albumArtists = albumArtists; self.displayAlbumArtist = displayAlbumArtist
        self.contributors = contributors; self.displayComposer = displayComposer
        self.displayArtistOverride = displayArtistOverride
        self.track = track; self.year = year; self.genre = genre; self.genres = genres
        self.coverArt = coverArt; self.size = size
        self.contentType = contentType; self.suffix = suffix
        self.duration = duration; self.bitRate = bitRate
        self.bitDepth = bitDepth; self.samplingRate = samplingRate; self.channelCount = channelCount
        self.comment = comment
        self.path = path; self.discNumber = discNumber; self.created = created
        self.played = played
        self.starred = starred; self.userRating = userRating; self.playCount = playCount
        self.bpm = bpm; self.replayGain = replayGain; self.musicBrainzId = musicBrainzId
        self.isrc = isrc; self.sortName = sortName
        self.mediaType = mediaType; self.type = type
        self.moods = moods; self.explicitStatus = explicitStatus
        self.works = works; self.movements = movements; self.groupings = groupings
    }

    func withStarred(_ starred: String?) -> Song {
        Song(
            id: id, parent: parent, title: title, album: album,
            artist: artist, albumArtist: albumArtist,
            albumId: albumId, artistId: artistId,
            artists: artists, serverDisplayArtist: _displayArtist,
            albumArtists: albumArtists, displayAlbumArtist: displayAlbumArtist,
            contributors: contributors, displayComposer: displayComposer,
            displayArtistOverride: displayArtistOverride,
            track: track, year: year, genre: genre, genres: genres,
            coverArt: coverArt, size: size,
            contentType: contentType, suffix: suffix,
            duration: duration, bitRate: bitRate,
            bitDepth: bitDepth, samplingRate: samplingRate, channelCount: channelCount,
            comment: comment,
            path: path, discNumber: discNumber, created: created, played: played,
            starred: starred, userRating: userRating, playCount: playCount,
            bpm: bpm, replayGain: replayGain, musicBrainzId: musicBrainzId,
            isrc: isrc, sortName: sortName, mediaType: mediaType, type: type,
            moods: moods, explicitStatus: explicitStatus,
            works: works, movements: movements, groupings: groupings
        )
    }

    func withUserRating(_ rating: Int?) -> Song {
        Song(
            id: id, parent: parent, title: title, album: album,
            artist: artist, albumArtist: albumArtist,
            albumId: albumId, artistId: artistId,
            artists: artists, serverDisplayArtist: _displayArtist,
            albumArtists: albumArtists, displayAlbumArtist: displayAlbumArtist,
            contributors: contributors, displayComposer: displayComposer,
            displayArtistOverride: displayArtistOverride,
            track: track, year: year, genre: genre, genres: genres,
            coverArt: coverArt, size: size,
            contentType: contentType, suffix: suffix,
            duration: duration, bitRate: bitRate,
            bitDepth: bitDepth, samplingRate: samplingRate, channelCount: channelCount,
            comment: comment,
            path: path, discNumber: discNumber, created: created, played: played,
            starred: starred, userRating: rating, playCount: playCount,
            bpm: bpm, replayGain: replayGain, musicBrainzId: musicBrainzId,
            isrc: isrc, sortName: sortName, mediaType: mediaType, type: type,
            moods: moods, explicitStatus: explicitStatus,
            works: works, movements: movements, groupings: groupings
        )
    }
}

extension Song {
    var asAlbum: Album {
        Album(
            id: albumId ?? id,
            name: album ?? title,
            artist: artist,
            artistId: artistId,
            artists: nil, displayArtist: nil,
            coverArt: coverArt,
            songCount: nil, duration: nil, playCount: nil,
            year: year, genre: genre, genres: nil,
            starred: starred, played: nil, created: nil,
            userRating: userRating, song: nil,
            replayGain: nil, musicBrainzId: nil, recordLabels: nil,
            version: nil, releaseTypes: nil, moods: nil, sortName: nil,
            originalReleaseDate: nil, releaseDate: nil,
            isCompilation: nil, explicitStatus: nil, discTitles: nil
        )
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
    let position: Int64?
    let username: String?
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
    let albumId: String?
    let artistId: String?
    let coverArt: String?
    let duration: Int?
    let track: Int?
    let year: Int?
    let genre: String?
    let genres: [ItemGenre]?
    let size: Int?
    let suffix: String?
    let bitRate: Int?
    let bitDepth: Int?
    let samplingRate: Int?
    let channelCount: Int?
    let contentType: String?
    let path: String?
    let parent: String?
    let discNumber: Int?
    let created: String?
    let played: String?
    let starred: String?
    let userRating: Int?
    let playCount: Int64?
    let bpm: Int?
    let comment: String?
    let sortName: String?
    let musicBrainzId: String?
    let isrc: [String]?
    let artists: [SongArtist]?
    let displayArtist: String?
    let albumArtists: [ArtistID3]?
    let displayAlbumArtist: String?
    let contributors: [Contributor]?
    let displayComposer: String?
    let moods: [String]?
    let replayGain: ReplayGain?
    let explicitStatus: String?
    let works: [Work]?
    let movements: [Movement]?
    let groupings: [String]?
    let mediaType: String?
    let type: String?
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
