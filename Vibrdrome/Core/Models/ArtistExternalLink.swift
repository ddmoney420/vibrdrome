import Foundation

struct ArtistExternalLink: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var asset: String?
    var badge: String?
    var urlTemplate: String

    func url(for artistName: String) -> URL? {
        let encoded = artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let resolved = urlTemplate.replacingOccurrences(of: "{artist}", with: encoded)
        return URL(string: resolved)
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
