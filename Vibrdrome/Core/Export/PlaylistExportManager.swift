#if os(macOS)
import AppKit
import Foundation
import SwiftData
import os.log

private let exportLog = Logger(subsystem: "com.vibrdrome.app", category: "PlaylistExport")

@MainActor
final class PlaylistExportManager: ObservableObject {
    static let shared = PlaylistExportManager()

    @Published var syncingPlaylistIds: Set<String> = []

    private var syncTasksByKey: [String: Task<Void, Never>] = [:]

    // MARK: - Folder Picker

    func pickFolder() async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Choose Export Folder"
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    // MARK: - Bookmark Resolution

    func resolveBookmark(_ data: Data) throws -> (URL, Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    // MARK: - Export Path

    nonisolated static func exportPath(song: Song, playlistName: String, suffix: String) -> String {
        let playlist = playlistName.sanitizedFileName
        let artist = (song.artist ?? "Unknown Artist").sanitizedFileName
        let title = song.title.sanitizedFileName
        let safeName = title.isEmpty ? song.id : title
        return "\(playlist)/\(artist) - \(safeName).\(suffix)"
    }

    // Returns the final on-disk suffix after optional transcoding.
    nonisolated static func finalSuffix(originalSuffix: String, transcodeFormat: String?) -> String {
        transcodeFormat ?? originalSuffix
    }

    // MARK: - Sync

    func sync(export: ExportedPlaylist, client: SubsonicClient) async {
        guard !syncingPlaylistIds.contains(export.compositeKey) else { return }
        guard let bookmarkData = export.folderBookmarkData else {
            export.lastSyncError = "No export folder configured."
            try? PersistenceController.shared.container.mainContext.save()
            return
        }

        let task = Task<Void, Never> {
            await performSync(export: export, bookmarkData: bookmarkData, client: client)
        }
        syncTasksByKey[export.compositeKey] = task
        syncingPlaylistIds.insert(export.compositeKey)
        await task.value
        syncingPlaylistIds.remove(export.compositeKey)
        syncTasksByKey.removeValue(forKey: export.compositeKey)
    }

    private func performSync(export: ExportedPlaylist, bookmarkData: Data, client: SubsonicClient) async {
        guard let folderURL = resolveAccessibleFolder(export: export, bookmarkData: bookmarkData) else { return }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        let newSongs: [Song]
        do {
            let playlist = try await client.getPlaylist(id: export.playlistId)
            newSongs = playlist.entry ?? []
        } catch {
            export.lastSyncError = "Failed to fetch playlist: \(error.localizedDescription)"
            try? PersistenceController.shared.container.mainContext.save()
            exportLog.error("Failed to fetch playlist \(export.playlistId): \(error)")
            return
        }

        let formatChanged = export.transcodeFormat != export.appliedTranscodeFormat
        let effectiveKnownIds: [String] = formatChanged ? [] : export.knownSongIds
        let effectiveKnownPaths: [String: String] = formatChanged ? [:] : export.knownSongPaths
        if formatChanged {
            exportLog.info("Transcode format changed for \(export.playlistName), forcing full re-sync")
        }

        let newSongIds = newSongs.map(\.id)
        let addedIds = Set(newSongIds).subtracting(Set(effectiveKnownIds))
        let removedIds = Set(effectiveKnownIds).subtracting(Set(newSongIds))

        let (downloadedPaths, failedSongs) = await downloadAddedSongs(
            newSongs.filter { addedIds.contains($0.id) },
            folderURL: folderURL,
            export: export,
            client: client
        )

        if export.syncModeEnum == .addAndRemove {
            removeDeletedFiles(removedIds: removedIds, knownPaths: effectiveKnownPaths, folderURL: folderURL)
        }

        let diff = SyncDiff(
            downloadedPaths: downloadedPaths,
            removedIds: removedIds,
            failedSongs: failedSongs,
            formatChanged: formatChanged
        )
        saveUpdatedState(
            export: export,
            effectiveKnownIds: effectiveKnownIds,
            effectiveKnownPaths: effectiveKnownPaths,
            diff: diff
        )
    }

    private func resolveAccessibleFolder(export: ExportedPlaylist, bookmarkData: Data) -> URL? {
        let (folderURL, isStale): (URL, Bool)
        do {
            (folderURL, isStale) = try resolveBookmark(bookmarkData)
        } catch {
            export.lastSyncError = "Folder access lost. Please re-select the export folder."
            export.isActive = false
            try? PersistenceController.shared.container.mainContext.save()
            exportLog.error("Bookmark resolution failed for \(export.playlistName): \(error)")
            return nil
        }
        guard folderURL.startAccessingSecurityScopedResource() else {
            export.lastSyncError = "Could not access the export folder."
            try? PersistenceController.shared.container.mainContext.save()
            return nil
        }
        if isStale, let newData = try? self.bookmarkData(for: folderURL) {
            export.folderBookmarkData = newData
        }
        return folderURL
    }

    private func downloadAddedSongs(
        _ songs: [Song],
        folderURL: URL,
        export: ExportedPlaylist,
        client: SubsonicClient
    ) async -> ([String: String], [(id: String, title: String)]) {
        var downloadedPaths: [String: String] = [:]
        var failedSongs: [(id: String, title: String)] = []

        let playlistName = export.playlistName
        let transcodeFormat = export.transcodeFormat
        let transcodeBitrate = export.transcodeBitrate

        await withTaskGroup(of: (String, String?, String).self) { group in
            var songQueue = songs
            var inFlight = 0

            func launchNext() {
                guard !songQueue.isEmpty else { return }
                let song = songQueue.removeFirst()
                inFlight += 1
                let songId = song.id
                let songTitle = song.title
                let originalSuffix = song.suffix ?? "mp3"
                let finalSuffix = PlaylistExportManager.finalSuffix(
                    originalSuffix: originalSuffix, transcodeFormat: transcodeFormat)
                // downloadSong writes the original then transcodes in-place, so the
                // download destination uses the original suffix; the stored path
                // uses the final suffix so re-syncs can detect the file correctly.
                let downloadRelativePath = PlaylistExportManager.exportPath(
                    song: song, playlistName: playlistName, suffix: originalSuffix)
                let finalRelativePath = PlaylistExportManager.exportPath(
                    song: song, playlistName: playlistName, suffix: finalSuffix)
                let target = DownloadTarget(
                    downloadURL: folderURL.appendingPathComponent(downloadRelativePath),
                    finalURL: folderURL.appendingPathComponent(finalRelativePath)
                )
                group.addTask {
                    do {
                        try await PlaylistExportManager.shared.downloadSong(
                            song: song, target: target,
                            transcodeFormat: transcodeFormat,
                            transcodeBitrate: transcodeBitrate,
                            client: client
                        )
                        return (songId, finalRelativePath, songTitle)
                    } catch {
                        exportLog.error("Failed to download \(songTitle): \(error)")
                        return (songId, nil, songTitle)
                    }
                }
            }

            for _ in 0..<min(3, songQueue.count) { launchNext() }
            for await (songId, path, songTitle) in group {
                inFlight -= 1
                if let path {
                    downloadedPaths[songId] = path
                } else {
                    failedSongs.append((id: songId, title: songTitle))
                }
                launchNext()
                _ = inFlight
            }
        }

        return (downloadedPaths, failedSongs)
    }

    private func removeDeletedFiles(removedIds: Set<String>, knownPaths: [String: String], folderURL: URL) {
        for songId in removedIds {
            guard let relativePath = knownPaths[songId] else { continue }
            let fileURL = folderURL.appendingPathComponent(relativePath)
            try? FileManager.default.removeItem(at: fileURL)
            exportLog.info("Removed \(relativePath) from export")
        }
    }

    private struct SyncDiff {
        var downloadedPaths: [String: String]
        var removedIds: Set<String>
        var failedSongs: [(id: String, title: String)]
        var formatChanged: Bool
    }

    private func saveUpdatedState(
        export: ExportedPlaylist,
        effectiveKnownIds: [String],
        effectiveKnownPaths: [String: String],
        diff: SyncDiff
    ) {
        var updatedPaths = effectiveKnownPaths
        for removedId in diff.removedIds { updatedPaths.removeValue(forKey: removedId) }
        for (id, path) in diff.downloadedPaths { updatedPaths[id] = path }

        var updatedIds = effectiveKnownIds.filter { !diff.removedIds.contains($0) }
        for id in diff.downloadedPaths.keys where !updatedIds.contains(id) { updatedIds.append(id) }

        export.knownSongIds = updatedIds
        export.knownSongPaths = updatedPaths
        export.lastSyncedAt = Date()
        export.failedSongIds = diff.failedSongs.map(\.id)
        export.failedSongTitles = diff.failedSongs.map(\.title)
        export.lastSyncError = diff.failedSongs.isEmpty ? nil : "\(diff.failedSongs.count) song(s) failed to download."
        if diff.failedSongs.isEmpty {
            export.appliedTranscodeFormat = export.transcodeFormat
        }

        do {
            try PersistenceController.shared.container.mainContext.save()
        } catch {
            exportLog.error("Failed to save export state: \(error)")
        }
    }

    private struct DownloadTarget {
        let downloadURL: URL
        let finalURL: URL
    }

    private func downloadSong(
        song: Song,
        target: DownloadTarget,
        transcodeFormat: String?,
        transcodeBitrate: Int?,
        client: SubsonicClient
    ) async throws {
        // Skip if the final on-disk file already exists (handles transcoded re-syncs correctly).
        if FileManager.default.fileExists(atPath: target.finalURL.path) {
            return
        }

        let sourceURL = client.downloadURL(id: song.id)
        let (tempURL, _) = try await URLSession.shared.download(from: sourceURL)

        let dir = target.downloadURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: target.downloadURL.path) {
            try FileManager.default.removeItem(at: target.downloadURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: target.downloadURL)

        if let format = transcodeFormat {
            try await transcodeFile(at: target.downloadURL, toFormat: format, bitrate: transcodeBitrate)
        }

        // The file is now at finalURL (transcode replaced downloadURL in-place, or they are the same).
        // Embed tags from cache and cover art from server/cache.
        await embedTagsAndArt(in: target.finalURL, song: song, client: client)
    }

    // MARK: - Tag and Cover Art Embedding

    private func embedTagsAndArt(in fileURL: URL, song: Song, client: SubsonicClient) async {
        guard let ffmpegPath = await resolveFfmpegPath() else { return }

        let artData: Data? = await fetchCoverArt(for: song, client: client)
        let cached = cachedSong(id: song.id)

        var (args, artTempURL) = buildTagArgs(
            song: song, cached: cached, ffmpegPath: ffmpegPath, fileURL: fileURL, artData: artData
        )
        defer { artTempURL.map { try? FileManager.default.removeItem(at: $0) } }
        guard !args.isEmpty else { return }

        let tempOut = fileURL.deletingPathExtension()
            .appendingPathExtension("_tagged")
            .appendingPathExtension(fileURL.pathExtension)

        args.append(tempOut.path)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    try? FileManager.default.removeItem(at: fileURL)
                    try? FileManager.default.moveItem(at: tempOut, to: fileURL)
                } else {
                    try? FileManager.default.removeItem(at: tempOut)
                    exportLog.warning("Tag embedding failed for \(fileURL.lastPathComponent), keeping untagged file")
                }
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                try? FileManager.default.removeItem(at: tempOut)
                continuation.resume()
            }
        }
    }

    private func buildTagArgs(
        song: Song,
        cached: CachedSong?,
        ffmpegPath: String,
        fileURL: URL,
        artData: Data?
    ) -> ([String], URL?) {
        let title = cached?.title ?? song.title
        let artist = cached?.artist ?? song.artist
        let albumArtist = cached?.albumArtist ?? song.albumArtist
        let album = cached?.albumName ?? song.album
        let track = cached?.track ?? song.track
        let disc = cached?.discNumber ?? song.discNumber
        let year = cached?.year ?? song.year
        let genre = cached?.genre ?? song.genre
        let comment = cached?.comment ?? song.comment
        let format = fileURL.pathExtension.lowercased()

        var artTempURL: URL?
        if let data = artData {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            try? data.write(to: tmp)
            artTempURL = tmp
        }

        var args: [String]
        if let artURL = artTempURL {
            args = ["-i", fileURL.path, "-i", artURL.path,
                    "-map", "0:a", "-map", "1:0",
                    "-map_metadata", "0",
                    "-c:a", "copy", "-c:v", "copy", "-y"]
            switch format {
            case "mp3":
                args += ["-id3v2_version", "3"]
            case "aac", "m4a":
                args += ["-disposition:v", "attached_pic"]
            default:
                break
            }
        } else {
            args = ["-i", fileURL.path, "-map", "0",
                    "-map_metadata", "0",
                    "-c", "copy", "-y"]
            if format == "mp3" { args += ["-id3v2_version", "3"] }
        }

        func meta(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            args += ["-metadata", "\(key)=\(value)"]
        }

        meta("title", title)
        meta("artist", artist)
        meta("album_artist", albumArtist)
        meta("album", album)
        meta("genre", genre)
        meta("comment", comment)
        if let track { meta("track", "\(track)") }
        if let disc { meta("disc", "\(disc)") }
        if let year { meta("date", "\(year)") }

        return (args, artTempURL)
    }

    private func fetchCoverArt(for song: Song, client: SubsonicClient) async -> Data? {
        guard let coverArtId = song.coverArt else { return nil }

        // Request JPEG explicitly — strip any webp param added by supportsWebP,
        // as ffmpeg requires a raster format it can decode as a video stream.
        var components = URLComponents(
            url: client.coverArtURL(id: coverArtId),
            resolvingAgainstBaseURL: false
        )
        var queryItems = (components?.queryItems ?? []).filter { $0.name != "format" }
        queryItems.append(URLQueryItem(name: "format", value: "jpeg"))
        components?.queryItems = queryItems
        guard let artURL = components?.url else { return nil }

        return try? await URLSession.shared.data(from: artURL).0
    }

    private func cachedSong(id: String) -> CachedSong? {
        let context = PersistenceController.shared.container.mainContext
        var descriptor = FetchDescriptor<CachedSong>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Transcoding

    func transcodeFile(at fileURL: URL, toFormat format: String, bitrate: Int?) async throws {
        let ffmpegPath = await resolveFfmpegPath()
        guard let ffmpegPath else {
            throw ExportError.ffmpegNotFound
        }

        // Always write to a temp path — ffmpeg refuses input == output, which happens
        // when the source suffix already matches the target format (e.g. mp3 → mp3).
        let tempOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(format)
        let finalOutputURL = fileURL.deletingPathExtension().appendingPathExtension(format)

        var args = ["-i", fileURL.path, "-map", "0", "-map_metadata", "0", "-c:v", "copy", "-y"]
        if let bitrate {
            args += ["-b:a", "\(bitrate)k"]
        }
        switch format {
        case "mp3":
            args += ["-id3v2_version", "3"]
        case "aac", "m4a":
            args += ["-disposition:v", "attached_pic"]
        default:
            break
        }
        args.append(tempOutputURL.path)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    try? FileManager.default.removeItem(at: fileURL)
                    try? FileManager.default.moveItem(at: tempOutputURL, to: finalOutputURL)
                    continuation.resume()
                } else {
                    try? FileManager.default.removeItem(at: tempOutputURL)
                    continuation.resume(throwing: ExportError.transcodeFailed(status: proc.terminationStatus))
                }
            }
            do {
                try process.run()
            } catch {
                try? FileManager.default.removeItem(at: tempOutputURL)
                continuation.resume(throwing: error)
            }
        }
    }

    private func resolveFfmpegPath() async -> String? {
        let stored = UserDefaults.standard.string(forKey: UserDefaultsKeys.exportFfmpegPath) ?? ""
        if !stored.isEmpty && FileManager.default.fileExists(atPath: stored) {
            return stored
        }
        let defaults = ["/usr/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg", "/usr/bin/ffmpeg"]
        for path in defaults where FileManager.default.fileExists(atPath: path) {
            return path
        }
        // Try `which ffmpeg`
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = ["ffmpeg"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: path.isEmpty ? nil : path)
            }
            try? process.run()
        }
    }

    // MARK: - Bulk Sync

    func syncAllActive(client: SubsonicClient) async {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<ExportedPlaylist>(
            predicate: #Predicate { $0.isActive == true }
        )
        guard let exports = try? context.fetch(descriptor) else { return }
        for export in exports {
            await sync(export: export, client: client)
        }
    }

    // MARK: - Cancel

    func cancelSync(for compositeKey: String) {
        syncTasksByKey[compositeKey]?.cancel()
        syncTasksByKey.removeValue(forKey: compositeKey)
        syncingPlaylistIds.remove(compositeKey)
    }

    func removeExport(_ export: ExportedPlaylist) {
        cancelSync(for: export.compositeKey)
        let context = PersistenceController.shared.container.mainContext
        context.delete(export)
        try? context.save()
    }

    // MARK: - ffmpeg Test

    func testFfmpeg(path: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["-version"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus == 0)
            }
            guard (try? process.run()) != nil else {
                continuation.resume(returning: false)
                return
            }
        }
    }
}

enum ExportError: LocalizedError {
    case ffmpegNotFound
    case transcodeFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            "ffmpeg not found. Configure the path in Settings → Playlist Export."
        case .transcodeFailed(let status):
            "Transcoding failed with exit code \(status)."
        }
    }
}
#endif
