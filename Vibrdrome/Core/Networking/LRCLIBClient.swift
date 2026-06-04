import Foundation

/// Fetches synced/plain lyrics from LRCLIB (https://lrclib.net) as a fallback when the
/// Subsonic server returns none (#82). Free, no API key, returns both `syncedLyrics`
/// (LRC) and `plainLyrics`.
///
/// Privacy: a lookup sends track metadata (title / artist / album / duration) to a third
/// party. The call site gates this behind the user's "fetch internet lyrics" setting.
struct LRCLIBClient {
    static let shared = LRCLIBClient()

    private let session: URLSession
    private static let base = "https://lrclib.net"

    /// In-process cache so reopening the lyrics view doesn't re-query. Stores the
    /// resolved result (including "not found", as `.some(nil)`) keyed by song id.
    private actor Cache {
        private var store: [String: StructuredLyrics?] = [:]
        func value(for key: String) -> StructuredLyrics?? { store[key] }
        func set(_ value: StructuredLyrics?, for key: String) { store[key] = value }
    }
    private let cache = Cache()

    init(session: URLSession = .shared) {
        self.session = session
    }

    private struct Track: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    /// Look up lyrics for a track. Returns parsed `StructuredLyrics`, or nil if none found.
    /// `cacheKey` should uniquely identify the song (its id) so repeat opens are free.
    func lyrics(
        title: String,
        artist: String,
        album: String?,
        duration: Int?,
        cacheKey: String
    ) async -> StructuredLyrics? {
        if let cached = await cache.value(for: cacheKey) { return cached }
        let result = await lookup(title: title, artist: artist, album: album, duration: duration)
        await cache.set(result, for: cacheKey)
        return result
    }

    private func lookup(title: String, artist: String, album: String?, duration: Int?) async -> StructuredLyrics? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return nil }

        // Exact match first (uses duration for accuracy), then a looser search.
        if let track = await getExact(title: title, artist: artist, album: album, duration: duration),
           let lyrics = Self.structured(from: track, title: title, artist: artist) {
            return lyrics
        }
        if let track = await searchFirst(title: title, artist: artist),
           let lyrics = Self.structured(from: track, title: title, artist: artist) {
            return lyrics
        }
        return nil
    }

    private func getExact(title: String, artist: String, album: String?, duration: Int?) async -> Track? {
        var comps = URLComponents(string: "\(Self.base)/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album, !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration, duration > 0 { items.append(URLQueryItem(name: "duration", value: String(duration))) }
        comps?.queryItems = items
        guard let url = comps?.url else { return nil }
        return await decode(Track.self, from: url)
    }

    private func searchFirst(title: String, artist: String) async -> Track? {
        var comps = URLComponents(string: "\(Self.base)/api/search")
        comps?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = comps?.url, let results = await decode([Track].self, from: url) else { return nil }
        // Prefer a result that actually has synced lyrics.
        return results.first(where: { !($0.syncedLyrics ?? "").isEmpty }) ?? results.first
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) async -> T? {
        var request = URLRequest(url: url)
        request.setValue("Vibrdrome (https://github.com/ddmoney420/vibrdrome)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Parsing

    private static func structured(from track: Track, title: String, artist: String) -> StructuredLyrics? {
        if let synced = track.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty {
                return StructuredLyrics(
                    displayArtist: artist, displayTitle: title,
                    lang: "xxx", synced: true, offset: 0, line: lines
                )
            }
        }
        if let plain = track.plainLyrics, !plain.isEmpty {
            let lines = plain
                .components(separatedBy: "\n")
                .map { LyricLine(start: nil, value: $0) }
            return StructuredLyrics(
                displayArtist: artist, displayTitle: title,
                lang: "xxx", synced: false, offset: 0, line: lines
            )
        }
        return nil
    }

    /// Parse LRC text into timestamped `LyricLine`s (start in milliseconds), sorted by
    /// time. Lines with multiple timestamps produce one entry each; metadata tags
    /// (`[ar:]`, `[ti:]`, `[offset:]`, …) and untimed lines are skipped. Internal +
    /// static so it can be unit-tested without any network.
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        var parsed: [(ms: Int, text: String)] = []
        for rawLine in lrc.components(separatedBy: "\n") {
            var line = Substring(rawLine)
            var stamps: [Int] = []
            while line.first == "[", let close = line.firstIndex(of: "]") {
                let inner = String(line[line.index(after: line.startIndex)..<close])
                if let ms = parseTimestamp(inner) { stamps.append(ms) }
                line = line[line.index(after: close)...]
            }
            guard !stamps.isEmpty else { continue }
            let text = String(line).trimmingCharacters(in: .whitespaces)
            for ms in stamps { parsed.append((ms, text)) }
        }
        return parsed
            .sorted { $0.ms < $1.ms }
            .map { LyricLine(start: max(0, $0.ms), value: $0.text) }
    }

    /// Parse an LRC timestamp body like `mm:ss.xx`, `mm:ss.xxx`, or `mm:ss` into
    /// milliseconds. Returns nil for non-timestamp tags (so metadata is ignored).
    private static func parseTimestamp(_ body: String) -> Int? {
        let parts = body.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]) else { return nil }
        let secComponents = parts[1].split(separator: ".")
        guard let seconds = Int(secComponents[0]) else { return nil }
        var ms = (minutes * 60 + seconds) * 1000
        if secComponents.count == 2, let frac = Int(secComponents[1]) {
            switch secComponents[1].count {
            case 2: ms += frac * 10      // centiseconds
            case 3: ms += frac           // milliseconds
            case 1: ms += frac * 100
            default: break
            }
        }
        return ms
    }
}
