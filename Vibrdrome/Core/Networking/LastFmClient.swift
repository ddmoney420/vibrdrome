import CryptoKit
import Foundation
import os.log

private let lastFmLog = Logger(subsystem: "com.vibrdrome.app", category: "LastFm")

/// Lightweight Last.fm API client for scrobbling.
actor LastFmClient {
    static let shared = LastFmClient()

    private let baseURL = "https://ws.audioscrobbler.com/2.0/"

    private var apiKey: String? {
        let key = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastFmApiKey)
        return (key?.isEmpty ?? true) ? nil : key
    }

    private var secret: String? {
        let key = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastFmSecret)
        return (key?.isEmpty ?? true) ? nil : key
    }

    private var sessionKey: String? {
        let key = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastFmSessionKey)
        return (key?.isEmpty ?? true) ? nil : key
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.lastFmEnabled)
            && apiKey != nil && secret != nil && sessionKey != nil
    }

    // MARK: - Public API

    /// Submit a "now playing" notification
    func updateNowPlaying(song: Song) async {
        guard isEnabled else { return }
        var params = baseParams(method: "track.updateNowPlaying", for: song)
        sign(&params)
        await submit(params)
    }

    /// Submit a completed listen (scrobble)
    func scrobble(song: Song, timestamp: Date = .now) async {
        guard isEnabled else { return }
        var params = baseParams(method: "track.scrobble", for: song)
        params["timestamp"] = String(Int(timestamp.timeIntervalSince1970))
        sign(&params)
        await submit(params)
    }

    /// Authenticate with Last.fm using mobile auth flow (username/password).
    /// On success, stores the session key in UserDefaults and returns true.
    func authenticate(username: String, password: String) async -> Bool {
        guard let apiKey, let secret else { return false }
        var params: [String: String] = [
            "method": "auth.getMobileSession",
            "api_key": apiKey,
            "username": username,
            "password": password,
        ]
        // Sign the request
        let sigString = params.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)\($0.value)" }
            .joined() + secret
        params["api_sig"] = md5Hash(sigString)
        params["format"] = "json"

        guard let url = URL(string: baseURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = urlEncode(params).data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                lastFmLog.error("Last.fm auth failed: HTTP \(http.statusCode)")
                return false
            }
            // Parse session key from response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let session = json["session"] as? [String: Any],
               let key = session["key"] as? String {
                UserDefaults.standard.set(key, forKey: UserDefaultsKeys.lastFmSessionKey)
                return true
            }
            return false
        } catch {
            lastFmLog.error("Last.fm auth error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Helpers

    private func baseParams(method: String, for song: Song) -> [String: String] {
        var params: [String: String] = [
            "method": method,
            "api_key": apiKey ?? "",
            "sk": sessionKey ?? "",
            "artist": song.artist ?? "Unknown Artist",
            "track": song.title,
        ]
        if let album = song.album {
            params["album"] = album
        }
        if let albumArtist = song.albumArtist {
            params["albumArtist"] = albumArtist
        }
        if let duration = song.duration {
            params["duration"] = String(duration)
        }
        return params
    }

    /// Compute the api_sig by sorting params, concatenating key+value pairs,
    /// appending the shared secret, and taking the MD5 hash.
    private func sign(_ params: inout [String: String]) {
        guard let secret else { return }
        let sigString = params
            .filter { $0.key != "format" }
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)\($0.value)" }
            .joined() + secret
        params["api_sig"] = md5Hash(sigString)
        params["format"] = "json"
    }

    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func urlEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
    }

    private func submit(_ params: [String: String]) async {
        guard let url = URL(string: baseURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = urlEncode(params).data(using: .utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                lastFmLog.error("Last.fm submit failed: HTTP \(http.statusCode)")
            }
        } catch {
            lastFmLog.error("Last.fm submit error: \(error.localizedDescription)")
        }
    }
}
