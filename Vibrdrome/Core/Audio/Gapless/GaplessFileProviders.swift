import Foundation
import os.log

/// Serves tracks that are already on disk — offline/downloaded playback, and the offline
/// frame-continuity proofs, which run the real pipeline against real audio with no server.
struct GaplessLocalFileProvider: GaplessFileProviding {
    let filesByTrackID: [String: URL]

    init(filesByTrackID: [String: URL]) {
        self.filesByTrackID = filesByTrackID
    }

    /// Convenience for an album on disk: track IDs are the file names.
    init(albumFiles: [URL]) {
        filesByTrackID = Dictionary(uniqueKeysWithValues: albumFiles.map { ($0.lastPathComponent, $0) })
    }

    func localFile(forTrack trackID: String) async throws -> URL {
        guard let url = filesByTrackID[trackID],
              FileManager.default.fileExists(atPath: url.path) else {
            throw GaplessPreparationError.noLocalFile(trackID: trackID)
        }
        return url
    }
}

/// Resolves a track to a local file, downloading it whole into a gapless cache when it isn't
/// already stored locally.
///
/// **Why this doesn't drive `PredownloadManager` directly.** That actor exists to warm the offline
/// cache politely: it sleeps 10 s before its first download and 20 s between downloads, and it does
/// nothing at all when the user's *Preload songs* setting is 0. Those are correct behaviours for
/// background caching and wrong for a boundary-critical fetch, which must complete before the
/// current track ends regardless of settings. So this provider **consumes** what the download layer
/// has already stored — `existingLocalFile` hits the downloaded/predownloaded cache first, and a
/// file `PredownloadManager` fetched is used as-is with no second download — and only falls back to
/// fetching itself when the bytes aren't there yet.
///
/// The fetch is a whole-file download, not a streaming read, because the decoder needs the complete
/// file to report a true length: a partial file decodes short and would corrupt boundary accounting.
struct GaplessStreamingFileProvider: GaplessFileProviding {
    /// Local file already on disk for this track (downloaded or predownloaded), if any.
    let existingLocalFile: @Sendable (String) async -> URL?
    /// Remote stream URL for the track, resolved at fetch time so credentials/bitrate settings are
    /// current rather than captured when the queue was built.
    let remoteURL: @Sendable (String) async -> URL?
    /// Directory for gapless-owned cache files. Separate from the user's downloads so reaping it
    /// can never delete music the user chose to keep offline.
    let cacheDirectory: URL
    let session: URLSession

    private static let log = Logger(subsystem: "com.vibrdrome.app", category: "GaplessPrefetch")

    init(cacheDirectory: URL,
         session: URLSession = .shared,
         existingLocalFile: @escaping @Sendable (String) async -> URL?,
         remoteURL: @escaping @Sendable (String) async -> URL?) {
        self.cacheDirectory = cacheDirectory
        self.session = session
        self.existingLocalFile = existingLocalFile
        self.remoteURL = remoteURL
    }

    func localFile(forTrack trackID: String) async throws -> URL {
        if let existing = await existingLocalFile(trackID),
           FileManager.default.fileExists(atPath: existing.path) {
            return existing
        }
        if let cached = cachedFile(forTrack: trackID) { return cached }
        guard let remote = await remoteURL(trackID) else {
            throw GaplessPreparationError.noLocalFile(trackID: trackID)
        }
        return try await download(remote, trackID: trackID)
    }

    // MARK: - Cache

    /// An already-fetched cache file for this track, whatever extension it was stored under.
    /// The extension matters: `GaplessTrimPolicy` keys the MP3 trim off it.
    func cachedFile(forTrack trackID: String) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        return contents.first { $0.deletingPathExtension().lastPathComponent == cacheKey(for: trackID) }
    }

    /// Remove cache files for tracks no longer in the window. Only touches this provider's own
    /// directory, never the user's downloads.
    func reapCache(keeping trackIDs: Set<String>) {
        let keep = Set(trackIDs.map(cacheKey(for:)))
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in contents where !keep.contains(url.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Track IDs are server-supplied; percent-encode so they can't escape the cache directory.
    private func cacheKey(for trackID: String) -> String {
        trackID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? trackID
    }

    // MARK: - Fetch

    private func download(_ remote: URL, trackID: String) async throws -> URL {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let (temporaryURL, response) = try await session.download(from: remote)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw GaplessPreparationError.noLocalFile(trackID: trackID)
        }
        let ext = Self.fileExtension(for: response, remote: remote)
        let destination = cacheDirectory
            .appendingPathComponent(cacheKey(for: trackID))
            .appendingPathExtension(ext)
        // Replace rather than merge: a stale partial file would decode to the wrong length.
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            throw GaplessPreparationError.unreadable(trackID: trackID, underlying: error)
        }
        Self.log.debug("gapless cache fetched \(trackID, privacy: .public) as .\(ext, privacy: .public)")
        return destination
    }

    /// The container extension must be right, because the MP3 trim is selected by it. A transcoding
    /// server returns a different type than the stored file, so the response's content type wins
    /// over anything in the request URL.
    static func fileExtension(for response: URLResponse, remote: URL) -> String {
        let mime = (response.mimeType ?? "").lowercased()
        switch mime {
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac": return "m4a"
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/ogg", "audio/opus": return "opus"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        default: break
        }
        if let suggested = response.suggestedFilename,
           !URL(fileURLWithPath: suggested).pathExtension.isEmpty {
            return URL(fileURLWithPath: suggested).pathExtension.lowercased()
        }
        let fromURL = remote.pathExtension.lowercased()
        return fromURL.isEmpty ? "audio" : fromURL
    }
}
