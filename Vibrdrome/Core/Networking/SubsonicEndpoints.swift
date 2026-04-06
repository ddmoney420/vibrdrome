import Foundation

enum AlbumListType: String, Sendable {
    case random, newest, frequent, recent, starred
    case alphabeticalByName, alphabeticalByArtist
    case byYear, byGenre
}

enum SubsonicEndpoint: Sendable {
    case ping
    case getArtists(musicFolderId: String? = nil)
    case getArtist(id: String)
    case getAlbum(id: String)
    case getSong(id: String)
    case search3(query: String, artistCount: Int = 20, albumCount: Int = 20,
                 songCount: Int = 20, artistOffset: Int = 0, albumOffset: Int = 0,
                 songOffset: Int = 0, musicFolderId: String? = nil)
    case getAlbumList2(type: AlbumListType, size: Int = 20, offset: Int = 0,
                       fromYear: Int? = nil, toYear: Int? = nil, genre: String? = nil,
                       musicFolderId: String? = nil)
    case getRandomSongs(size: Int = 20, genre: String? = nil,
                        fromYear: Int? = nil, toYear: Int? = nil,
                        musicFolderId: String? = nil)
    case getStarred2(musicFolderId: String? = nil)
    case getGenres
    case star(id: String? = nil, albumId: String? = nil, artistId: String? = nil)
    case unstar(id: String? = nil, albumId: String? = nil, artistId: String? = nil)
    case setRating(id: String, rating: Int)
    case scrobble(id: String, time: Int? = nil, submission: Bool = true)
    case getPlaylists
    case getPlaylist(id: String)
    case createPlaylist(name: String, songIds: [String])
    case updatePlaylist(id: String, name: String? = nil, comment: String? = nil,
                       isPublic: Bool? = nil, songIdsToAdd: [String] = [],
                       songIndexesToRemove: [Int] = [])
    case deletePlaylist(id: String)
    case stream(id: String, maxBitRate: Int? = nil, format: String? = nil)
    case download(id: String)
    case getCoverArt(id: String, size: Int? = nil)
    case getLyricsBySongId(id: String)
    case getInternetRadioStations
    case createInternetRadioStation(streamUrl: String, name: String, homepageUrl: String? = nil)
    case deleteInternetRadioStation(id: String)
    case getPlayQueue
    case savePlayQueue(ids: [String], current: String? = nil, position: Int? = nil)
    case getBookmarks
    case createBookmark(id: String, position: Int, comment: String? = nil)
    case deleteBookmark(id: String)
    case getArtistInfo2(id: String, count: Int = 20)
    case getSimilarSongs2(id: String, count: Int = 50)
    case getTopSongs(artist: String, count: Int = 50)
    case getMusicFolders
    case getIndexes(musicFolderId: String? = nil)
    case getMusicDirectory(id: String)
    case jukeboxControl(action: String, index: Int? = nil, offset: Int? = nil,
                        ids: [String]? = nil, gain: Float? = nil)

    var path: String {
        switch self {
        case .ping: "/rest/ping"
        case .getArtists: "/rest/getArtists"
        case .getArtist: "/rest/getArtist"
        case .getAlbum: "/rest/getAlbum"
        case .getSong: "/rest/getSong"
        case .search3: "/rest/search3"
        case .getAlbumList2: "/rest/getAlbumList2"
        case .getRandomSongs: "/rest/getRandomSongs"
        case .getStarred2: "/rest/getStarred2"
        case .getGenres: "/rest/getGenres"
        case .star: "/rest/star"
        case .unstar: "/rest/unstar"
        case .setRating: "/rest/setRating"
        case .scrobble: "/rest/scrobble"
        case .getPlaylists: "/rest/getPlaylists"
        case .getPlaylist: "/rest/getPlaylist"
        case .createPlaylist: "/rest/createPlaylist"
        case .updatePlaylist: "/rest/updatePlaylist"
        case .deletePlaylist: "/rest/deletePlaylist"
        case .stream: "/rest/stream"
        case .download: "/rest/download"
        case .getCoverArt: "/rest/getCoverArt"
        case .getLyricsBySongId: "/rest/getLyricsBySongId"
        case .getInternetRadioStations: "/rest/getInternetRadioStations"
        case .createInternetRadioStation: "/rest/createInternetRadioStation"
        case .deleteInternetRadioStation: "/rest/deleteInternetRadioStation"
        case .getPlayQueue: "/rest/getPlayQueue"
        case .savePlayQueue: "/rest/savePlayQueue"
        case .getBookmarks: "/rest/getBookmarks"
        case .createBookmark: "/rest/createBookmark"
        case .deleteBookmark: "/rest/deleteBookmark"
        case .getArtistInfo2: "/rest/getArtistInfo2"
        case .getSimilarSongs2: "/rest/getSimilarSongs2"
        case .getTopSongs: "/rest/getTopSongs"
        case .getMusicFolders: "/rest/getMusicFolders"
        case .getIndexes: "/rest/getIndexes"
        case .getMusicDirectory: "/rest/getMusicDirectory"
        case .jukeboxControl: "/rest/jukeboxControl"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case .ping, .getGenres, .getPlaylists,
             .getInternetRadioStations, .getPlayQueue, .getBookmarks,
             .getMusicFolders:
            return []

        case .getStarred2(let musicFolderId):
            var items: [URLQueryItem] = []
            if let musicFolderId { items.append(URLQueryItem(name: "musicFolderId", value: musicFolderId)) }
            return items

        case .getArtists(let musicFolderId):
            var items: [URLQueryItem] = []
            if let musicFolderId { items.append(URLQueryItem(name: "musicFolderId", value: musicFolderId)) }
            return items

        case .getArtist(let id):
            return [URLQueryItem(name: "id", value: id)]

        case .getAlbum(let id):
            return [URLQueryItem(name: "id", value: id)]

        case .getSong(let id):
            return [URLQueryItem(name: "id", value: id)]

        case .search3(let query, let artistCount, let albumCount, let songCount,
                      let artistOffset, let albumOffset, let songOffset, let musicFolderId):
            var items = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "artistCount", value: "\(artistCount)"),
                URLQueryItem(name: "albumCount", value: "\(albumCount)"),
                URLQueryItem(name: "songCount", value: "\(songCount)"),
            ]
            if artistOffset > 0 { items.append(URLQueryItem(name: "artistOffset", value: "\(artistOffset)")) }
            if albumOffset > 0 { items.append(URLQueryItem(name: "albumOffset", value: "\(albumOffset)")) }
            if songOffset > 0 { items.append(URLQueryItem(name: "songOffset", value: "\(songOffset)")) }
            if let musicFolderId { items.append(URLQueryItem(name: "musicFolderId", value: musicFolderId)) }
            return items

        case .getAlbumList2(let type, let size, let offset, let fromYear, let toYear,
                            let genre, let musicFolderId):
            var items = [
                URLQueryItem(name: "type", value: type.rawValue),
                URLQueryItem(name: "size", value: "\(size)"),
            ]
            if offset > 0 { items.append(URLQueryItem(name: "offset", value: "\(offset)")) }
            if let fromYear { items.append(URLQueryItem(name: "fromYear", value: "\(fromYear)")) }
            if let toYear { items.append(URLQueryItem(name: "toYear", value: "\(toYear)")) }
            if let genre { items.append(URLQueryItem(name: "genre", value: genre)) }
            if let musicFolderId { items.append(URLQueryItem(name: "musicFolderId", value: musicFolderId)) }
            return items

        case .getRandomSongs(let size, let genre, let fromYear, let toYear, let musicFolderId):
            var items = [URLQueryItem(name: "size", value: "\(size)")]
            if let genre { items.append(URLQueryItem(name: "genre", value: genre)) }
            if let fromYear { items.append(URLQueryItem(name: "fromYear", value: "\(fromYear)")) }
            if let toYear { items.append(URLQueryItem(name: "toYear", value: "\(toYear)")) }
            if let musicFolderId { items.append(URLQueryItem(name: "musicFolderId", value: musicFolderId)) }
            return items

        case .star(let id, let albumId, let artistId):
            var items: [URLQueryItem] = []
            if let id { items.append(URLQueryItem(name: "id", value: id)) }
            if let albumId { items.append(URLQueryItem(name: "albumId", value: albumId)) }
            if let artistId { items.append(URLQueryItem(name: "artistId", value: artistId)) }
            return items

        case .unstar(let id, let albumId, let artistId):
            var items: [URLQueryItem] = []
            if let id { items.append(URLQueryItem(name: "id", value: id)) }
            if let albumId { items.append(URLQueryItem(name: "albumId", value: albumId)) }
            if let artistId { items.append(URLQueryItem(name: "artistId", value: artistId)) }
            return items

        case .setRating(let id, let rating):
            return [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "rating", value: "\(rating)"),
            ]

        case .scrobble(let id, let time, let submission):
            var items = [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "submission", value: submission ? "true" : "false"),
            ]
            if let time { items.append(URLQueryItem(name: "time", value: "\(time)")) }
            return items

        case .getPlaylist(let id):
            return [URLQueryItem(name: "id", value: id)]

        case .createPlaylist(let name, let songIds):
            var items = [URLQueryItem(name: "name", value: name)]
            for songId in songIds {
                items.append(URLQueryItem(name: "songId", value: songId))
            }
            return items

        case .updatePlaylist(let id, let name, let comment, let isPublic,
                             let songIdsToAdd, let songIndexesToRemove):
            var items = [URLQueryItem(name: "playlistId", value: id)]
            if let name { items.append(URLQueryItem(name: "name", value: name)) }
            if let comment { items.append(URLQueryItem(name: "comment", value: comment)) }
            if let isPublic { items.append(URLQueryItem(name: "public", value: isPublic ? "true" : "false")) }
            for songId in songIdsToAdd {
                items.append(URLQueryItem(name: "songIdToAdd", value: songId))
            }
            for index in songIndexesToRemove {
                items.append(URLQueryItem(name: "songIndexToRemove", value: "\(index)"))
            }
            return items

        case .deletePlaylist(let id):
            return [URLQueryItem(name: "id", value: id)]

        case .stream(let id, let maxBitRate, let format):
            var items = [URLQueryItem(name: "id", value: id)]
            if let maxBitRate { items.append(URLQueryItem(name: "maxBitRate", value: "\(maxBitRate)")) }
            if let format { items.append(URLQueryItem(name: "format", value: format)) }
            return items

        case .download(let id):
            return [URLQueryItem(name: "id", value: id)]

        case .getCoverArt(let id, let size):
            var items = [URLQueryItem(name: "id", value: id)]
            if let size { items.append(URLQueryItem(name: "size", value: "\(size)")) }
            return items

        case .getLyricsBySongId(let id):
            return [URLQueryItem(name: "id", value: id)]

        case .createInternetRadioStation(let streamUrl, let name, let homepageUrl):
            var items = [
                URLQueryItem(name: "streamUrl", value: streamUrl),
                URLQueryItem(name: "name", value: name)
            ]
            if let homepageUrl { items.append(URLQueryItem(name: "homepageUrl", value: homepageUrl)) }
            return items

        case .deleteInternetRadioStation(let id):
            return [URLQueryItem(name: "id", value: id)]

        case .savePlayQueue(let ids, let current, let position):
            var items: [URLQueryItem] = []
            for id in ids {
                items.append(URLQueryItem(name: "id", value: id))
            }
            if let current { items.append(URLQueryItem(name: "current", value: current)) }
            if let position { items.append(URLQueryItem(name: "position", value: "\(position)")) }
            return items

        case .createBookmark(let id, let position, let comment):
            var items = [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "position", value: "\(position)"),
            ]
            if let comment { items.append(URLQueryItem(name: "comment", value: comment)) }
            return items

        case .deleteBookmark(let id):
            return [URLQueryItem(name: "id", value: id)]

        case .getArtistInfo2(let id, let count):
            return [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "count", value: "\(count)"),
            ]

        case .getSimilarSongs2(let id, let count):
            return [
                URLQueryItem(name: "id", value: id),
                URLQueryItem(name: "count", value: "\(count)"),
            ]

        case .getTopSongs(let artist, let count):
            return [
                URLQueryItem(name: "artist", value: artist),
                URLQueryItem(name: "count", value: "\(count)")
            ]

        case .getIndexes(let musicFolderId):
            var items: [URLQueryItem] = []
            if let musicFolderId { items.append(URLQueryItem(name: "musicFolderId", value: musicFolderId)) }
            return items

        case .getMusicDirectory(let id):
            return [URLQueryItem(name: "id", value: id)]

        case .jukeboxControl(let action, let index, let offset, let ids, let gain):
            var items = [URLQueryItem(name: "action", value: action)]
            if let index { items.append(URLQueryItem(name: "index", value: "\(index)")) }
            if let offset { items.append(URLQueryItem(name: "offset", value: "\(offset)")) }
            if let ids {
                for id in ids {
                    items.append(URLQueryItem(name: "id", value: id))
                }
            }
            if let gain { items.append(URLQueryItem(name: "gain", value: "\(gain)")) }
            return items
        }
    }
}
