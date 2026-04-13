import CryptoKit
import Foundation
import KeychainAccess
import os.log

private let lastFmLog = Logger(subsystem: "com.vibrdrome.app", category: "LastFm")
nonisolated(unsafe) private let lastFmKeychain = Keychain(service: "com.vibrdrome.lastfm")

/// Lightweight Last.fm API client for scrobbling.
actor LastFmClient {
    static let shared = LastFmClient()

    private let baseURL = "https://ws.audioscrobbler.com/2.0/"

    private var apiKey: String? {
        let key = lastFmKeychain["apiKey"]
        return (key?.isEmpty ?? true) ? nil : key
    }

    private var secret: String? {
        let key = lastFmKeychain["secret"]
        return (key?.isEmpty ?? true) ? nil : key
    }

    private var sessionKey: String? {
        let key = lastFmKeychain["sessionKey"]
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
    /// On success, stores the session key in UserDefaults and returns nil.
    /// On failure, returns the error message.
    func authenticate(username: String, password: String) async -> String? {
        guard let apiKey, let secret else { return "API Key or Shared Secret is empty" }
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

        guard let url = URL(string: baseURL) else { return "Invalid API URL" }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = urlEncode(params).data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                lastFmLog.error("Last.fm auth failed: HTTP \(http.statusCode)")
                return "HTTP error \(http.statusCode)"
            }
            // Parse session key from response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let session = json["session"] as? [String: Any],
                   let key = session["key"] as? String {
                    lastFmKeychain["sessionKey"] = key
                    return nil // success
                }
                // Return the error from Last.fm (e.g. invalid API key, wrong credentials)
                let errorMsg = (json["message"] as? String) ?? "Unknown error"
                let errorCode = (json["error"] as? Int) ?? 0
                lastFmLog.error("Last.fm auth rejected: \(errorCode) — \(errorMsg)")
                return errorMsg
            }
            return "Could not parse response"
        } catch {
            lastFmLog.error("Last.fm auth error: \(error.localizedDescription)")
            return error.localizedDescription
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

    /// Characters allowed in application/x-www-form-urlencoded values.
    /// Stricter than `.urlQueryAllowed` — encodes +, &, =, @, etc.
    private static let formAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private func urlEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: Self.formAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(
                withAllowedCharacters: Self.formAllowed
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
