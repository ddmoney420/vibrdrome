import Foundation
import os.log

private let lbLog = Logger(subsystem: "com.vibrdrome.app", category: "ListenBrainz")

/// Lightweight ListenBrainz API client for scrobbling.
actor ListenBrainzClient {
    static let shared = ListenBrainzClient()

    private let baseURL = "https://api.listenbrainz.org/1"

    private var token: String? {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.listenBrainzToken)
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.listenBrainzEnabled)
            && token != nil && !(token?.isEmpty ?? true)
    }

    /// Submit a "now playing" notification
    func submitNowPlaying(song: Song) async {
        guard isEnabled else { return }
        let payload: [String: Any] = [
            "listen_type": "playing_now",
            "payload": [[
                "track_metadata": trackMetadata(for: song),
            ]],
        ]
        await submit(payload)
    }

    /// Submit a completed listen (scrobble)
    func submitListen(song: Song, listenedAt: Date = .now) async {
        guard isEnabled else { return }
        let payload: [String: Any] = [
            "listen_type": "single",
            "payload": [[
                "listened_at": Int(listenedAt.timeIntervalSince1970),
                "track_metadata": trackMetadata(for: song),
            ]],
        ]
        await submit(payload)
    }

    private func trackMetadata(for song: Song) -> [String: Any] {
        var meta: [String: Any] = [
            "artist_name": song.artist ?? "Unknown Artist",
            "track_name": song.title,
        ]
        if let album = song.album {
            meta["release_name"] = album
        }
        if let duration = song.duration {
            meta["additional_info"] = [
                "duration_ms": duration * 1000,
                "media_player": "Vibrdrome",
            ]
        }
        return meta
    }

    private func submit(_ payload: [String: Any]) async {
        guard let token, let url = URL(string: "\(baseURL)/submit-listens") else { return }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                lbLog.error("ListenBrainz submit failed: HTTP \(http.statusCode)")
            }
        } catch {
            lbLog.error("ListenBrainz submit error: \(error.localizedDescription)")
        }
    }
}
