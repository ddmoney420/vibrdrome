import Foundation

struct ArtistExternalLink: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var asset: String?
    var badge: String?
    var urlTemplate: String

    /// Schemes permitted for external artist links. Anything else — `javascript:`,
    /// `file:`, `mailto:`, or a custom app scheme — is rejected so neither a tampered
    /// template (#74) nor an attacker-supplied artist name can invoke an arbitrary
    /// system URL handler.
    static let allowedSchemes: Set<String> = ["http", "https"]

    /// True when `urlString` parses and uses an allowed (http/https) scheme. Used by
    /// the settings editor to validate a template before it is saved.
    static func hasAllowedScheme(_ urlString: String) -> Bool {
        guard let scheme = URL(string: urlString)?.scheme?.lowercased() else { return false }
        return allowedSchemes.contains(scheme)
    }

    func url(for artistName: String) -> URL? {
        // Encode the artist name as a strict URL component value (RFC 3986 unreserved
        // set only). `.urlQueryAllowed` lets sub-delimiters like & = ? + pass through,
        // which an attacker-controlled artist name could use to inject extra query
        // structure into the destination (#73).
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = artistName.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let resolved = urlTemplate.replacingOccurrences(of: "{artist}", with: encoded)
        // Reject anything that isn't an http(s) URL before it can reach the system
        // handler at the open site (#74).
        guard let url = URL(string: resolved),
              let scheme = url.scheme?.lowercased(),
              Self.allowedSchemes.contains(scheme) else { return nil }
        return url
    }
}

// MARK: - Defaults

extension ArtistExternalLink {
    static let defaults: [ArtistExternalLink] = [
        ArtistExternalLink(
            id: "musicbrainz",
            label: "MusicBrainz",
            asset: "icon_musicbrainz",
            urlTemplate: "https://musicbrainz.org/search?query={artist}&type=artist"
        ),
        ArtistExternalLink(
            id: "lastfm",
            label: "Last.fm",
            asset: "icon_lastfm",
            urlTemplate: "https://www.last.fm/search/artists?q={artist}"
        ),
        ArtistExternalLink(
            id: "wikipedia",
            label: "Wikipedia",
            asset: "icon_wikipedia",
            urlTemplate: "https://en.wikipedia.org/w/index.php?search={artist}"
        ),
        ArtistExternalLink(
            id: "google",
            label: "Google",
            asset: "icon_google",
            urlTemplate: "https://www.google.com/search?q={artist}"
        )
    ]
}

// MARK: - Manager

@MainActor
@Observable
final class ArtistExternalLinksManager {
    static let shared = ArtistExternalLinksManager()

    private(set) var links: [ArtistExternalLink] = []

    private init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.artistExternalLinks),
              let saved = try? JSONDecoder().decode([ArtistExternalLink].self, from: data) else {
            links = ArtistExternalLink.defaults
            return
        }
        links = saved
    }

    func save() {
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.artistExternalLinks)
        }
    }

    func add(_ link: ArtistExternalLink) {
        links.append(link)
        save()
    }

    func remove(at offsets: IndexSet) {
        links.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        links.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func update(_ link: ArtistExternalLink) {
        guard let idx = links.firstIndex(where: { $0.id == link.id }) else { return }
        links[idx] = link
        save()
    }

    func resetToDefaults() {
        links = ArtistExternalLink.defaults
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.artistExternalLinks)
    }
}
