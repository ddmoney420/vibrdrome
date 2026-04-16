import Foundation
import Network
import SwiftData
import os.log

private let downloadLog = Logger(subsystem: "com.vibrdrome.app", category: "Downloads")

final class DownloadManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = DownloadManager()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.vibrdrome.downloads"
        )
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.httpMaximumConnectionsPerHost = 3
        // Security hardening: disable cookies and credential caching
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private let lock = NSLock()
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    private let networkMonitor = NWPathMonitor()
    private var _isOnCellular = false
    var isOnCellular: Bool {
        lock.withLock { _isOnCellular }
    }
    private var _completionHandler: (() -> Void)?
    var completionHandler: (() -> Void)? {
        get { lock.withLock { _completionHandler } }
        set { lock.withLock { _completionHandler = newValue } }
    }

    override init() {
        super.init()
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.withLock { self._isOnCellular = path.usesInterfaceType(.cellular) }
        }
        networkMonitor.start(queue: DispatchQueue(label: "com.vibrdrome.download.network"))
    }

    // MARK: - Resume Incomplete Downloads

    /// Check the background URLSession for pending tasks and reconnect them to the
    /// progress tracking system. Truly orphaned incomplete DownloadedSong records
    /// (those with no matching background session task) are deleted.
    func resumeIncompleteDownloads() {
        // Force lazy session init so we can query pending tasks
        _ = session

        session.getAllTasks { [weak self] tasks in
            guard let self else { return }

            // Build a set of songIds that have active background session tasks
            var activeSongIds = Set<String>()
            for task in tasks {
                guard let songId = task.taskDescription,
                      task.state == .running || task.state == .suspended else { continue }
                activeSongIds.insert(songId)

                // Reconnect the task to activeDownloads tracking
                if let downloadTask = task as? URLSessionDownloadTask {
                    self.lock.withLock {
                        self.activeDownloads[songId] = downloadTask
                    }
                    // Resume suspended tasks
                    if task.state == .suspended {
                        downloadTask.resume()
                    }
                }
            }

            downloadLog.info("Found \(activeSongIds.count) active background download tasks")

            // On the main actor, reconcile SwiftData records with active tasks
            Task { @MainActor in
                let modelContext = PersistenceController.shared.container.mainContext
                let descriptor = FetchDescriptor<DownloadedSong>(
                    predicate: #Predicate { $0.isComplete == false }
                )
                guard let incompleteRecords = try? modelContext.fetch(descriptor) else { return }

                var deletedCount = 0
                var reconnectedCount = 0
                for record in incompleteRecords {
                    if activeSongIds.contains(record.songId) {
                        // This record has an active background task — reconnect progress tracking
                        DownloadProgress.shared.update(songId: record.songId, progress: 0)
                        reconnectedCount += 1
                    } else {
                        // Truly orphaned — no background task exists, delete the record
                        modelContext.delete(record)
                        deletedCount += 1
                    }
                }

                if deletedCount > 0 || reconnectedCount > 0 {
                    do {
                        try modelContext.save()
                    } catch {
                        downloadLog.error("Failed to save after incomplete download cleanup: \(error)")
                    }
                    downloadLog.info(
                        "Incomplete downloads: \(reconnectedCount) resumed, \(deletedCount) orphaned records removed"
                    )
                }
            }
        }
    }

    // MARK: - Public API

    @MainActor
    func download(song: Song, client: SubsonicClient) {
        // Block downloads over cellular if setting is off
        if isOnCellular && !UserDefaults.standard.bool(forKey: UserDefaultsKeys.downloadOverCellular) {
            return
        }

        // Prevent duplicate downloads
        let alreadyActive = lock.withLock { activeDownloads[song.id] != nil }
        guard !alreadyActive else { return }

        let url = client.downloadURL(id: song.id)
        let task = session.downloadTask(with: url)
        task.taskDescription = song.id
        lock.withLock { activeDownloads[song.id] = task }
        task.resume()

        let localPath = Self.localPath(for: song)
        let modelContext = PersistenceController.shared.container.mainContext
        let songId = song.id
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.songId == songId }
        )
        if (try? modelContext.fetch(descriptor).first) != nil {
            return
        }
        let download = DownloadedSong(from: song, localFilePath: localPath)
        modelContext.insert(download)
        try? modelContext.save()
    }

    @MainActor
    func downloadAlbum(songs: [Song], client: SubsonicClient) {
        for song in songs {
            download(song: song, client: client)
        }
    }

    /// Download an entire playlist for offline use with max 3 concurrent downloads
    @MainActor
    func downloadPlaylist(playlist: Playlist, songs: [Song], client: SubsonicClient) {
        guard let serverId = AppState.shared.activeServerId else { return }

        // Save OfflinePlaylist metadata
        let modelContext = PersistenceController.shared.container.mainContext
        let playlistId = playlist.id
        let key = "\(serverId)_\(playlistId)"
        let descriptor = FetchDescriptor<OfflinePlaylist>(
            predicate: #Predicate { $0.compositeKey == key }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            // Update existing
            existing.songIds = songs.map(\.id)
            existing.playlistName = playlist.name
            existing.coverArtId = playlist.coverArt
            existing.totalSongs = songs.count
            existing.cachedAt = Date()
        } else {
            let offline = OfflinePlaylist(
                serverId: serverId,
                playlistId: playlist.id,
                playlistName: playlist.name,
                coverArtId: playlist.coverArt,
                songIds: songs.map(\.id)
            )
            modelContext.insert(offline)
        }

        // Ensure all songs have CachedSong metadata
        for song in songs {
            let songId = song.id
            let cachedDescriptor = FetchDescriptor<CachedSong>(
                predicate: #Predicate { $0.id == songId }
            )
            if (try? modelContext.fetch(cachedDescriptor).first) == nil {
                modelContext.insert(CachedSong(from: song))
            }
        }

        try? modelContext.save()

        // Download all songs concurrently (DownloadManager handles dedup)
        for song in songs {
            download(song: song, client: client)
        }

        // Track playlist-level progress
        DownloadProgress.shared.trackPlaylist(
            playlistId: playlist.id,
            songIds: songs.map(\.id)
        )
    }

    /// Check if a playlist is fully downloaded
    @MainActor
    func isPlaylistDownloaded(playlistId: String) -> Bool {
        guard let serverId = AppState.shared.activeServerId else { return false }
        let modelContext = PersistenceController.shared.container.mainContext
        let key = "\(serverId)_\(playlistId)"
        let descriptor = FetchDescriptor<OfflinePlaylist>(
            predicate: #Predicate { $0.compositeKey == key }
        )
        guard let offline = try? modelContext.fetch(descriptor).first else { return false }

        // Check each song is downloaded
        for songId in offline.songIds {
            let downloadDescriptor = FetchDescriptor<DownloadedSong>(
                predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
            )
            if (try? modelContext.fetch(downloadDescriptor).first) == nil {
                return false
            }
        }
        return true
    }

    /// Remove offline playlist metadata (does not delete song files — they may be in other playlists)
    @MainActor
    func removeOfflinePlaylist(playlistId: String) {
        guard let serverId = AppState.shared.activeServerId else { return }
        let modelContext = PersistenceController.shared.container.mainContext
        let key = "\(serverId)_\(playlistId)"
        let descriptor = FetchDescriptor<OfflinePlaylist>(
            predicate: #Predicate { $0.compositeKey == key }
        )
        if let offline = try? modelContext.fetch(descriptor).first {
            modelContext.delete(offline)
            try? modelContext.save()
        }
    }

    func cancelDownload(songId: String) {
        lock.withLock {
            activeDownloads[songId]?.cancel()
            activeDownloads.removeValue(forKey: songId)
        }
        Task { @MainActor in
            DownloadProgress.shared.remove(songId: songId)
            // Clean up the incomplete SwiftData record
            let modelContext = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<DownloadedSong>(
                predicate: #Predicate { $0.songId == songId && $0.isComplete == false }
            )
            if let download = try? modelContext.fetch(descriptor).first {
                modelContext.delete(download)
                try? modelContext.save()
            }
        }
    }

    func isDownloading(songId: String) -> Bool {
        lock.withLock { activeDownloads[songId] != nil }
    }

    func deleteDownload(songId: String) {
        cancelDownload(songId: songId)

        Task { @MainActor in
            let modelContext = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<DownloadedSong>(
                predicate: #Predicate { $0.songId == songId }
            )
            guard let download = try? modelContext.fetch(descriptor).first else { return }

            let fileURL = Self.absoluteURL(for: download.localFilePath)
            try? FileManager.default.removeItem(at: fileURL)

            // Only remove parent directories if they're empty
            let albumDir = fileURL.deletingLastPathComponent()
            let artistDir = albumDir.deletingLastPathComponent()
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: albumDir.path),
               contents.isEmpty {
                try? FileManager.default.removeItem(at: albumDir)
                if let artistContents = try? FileManager.default.contentsOfDirectory(atPath: artistDir.path),
                   artistContents.isEmpty {
                    try? FileManager.default.removeItem(at: artistDir)
                }
            }

            modelContext.delete(download)
            try? modelContext.save()
            DownloadProgress.shared.remove(songId: songId)
        }
    }

    func deleteAllDownloads() {
        lock.withLock {
            for (_, task) in activeDownloads {
                task.cancel()
            }
            activeDownloads.removeAll()
        }

        Task { @MainActor in
            let modelContext = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<DownloadedSong>()

            do {
                let downloads = try modelContext.fetch(descriptor)

                // Delete files first (less likely to fail)
                for download in downloads {
                    let fileURL = Self.absoluteURL(for: download.localFilePath)
                    try? FileManager.default.removeItem(at: fileURL)
                }

                // Then delete records in batches to avoid SwiftData pressure
                for download in downloads {
                    modelContext.delete(download)
                }
                try modelContext.save()
            } catch {
                downloadLog.error("Failed to delete downloads: \(error)")
                // Try to save whatever deletions succeeded
                try? modelContext.save()
            }

            try? FileManager.default.removeItem(at: Self.downloadsDirectory)
            DownloadProgress.shared.clear()
        }
    }

    // MARK: - Path Helpers

    static func localPath(for song: Song) -> String {
        let artist = song.artist?.sanitizedFileName ?? "Unknown"
        let album = song.album?.sanitizedFileName ?? "Unknown"
        let suffix = (song.suffix ?? "mp3").sanitizedFileName
        let title = song.title.sanitizedFileName
        let safeName = title.isEmpty ? song.id : title
        // D4: Include discNumber to prevent path collisions on multi-disc albums
        let disc = song.discNumber ?? 1
        let track = song.track ?? 0
        let filename = "\(disc)-\(track) - \(safeName).\(suffix)"
        return "\(artist)/\(album)/\(filename)"
    }

    static var downloadsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Downloads")
    }

    static func absoluteURL(for relativePath: String) -> URL {
        downloadsDirectory.appendingPathComponent(relativePath)
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let songId = downloadTask.taskDescription else { return }

        // D3: Always clean up activeDownloads, even on failure
        defer {
            lock.lock()
            activeDownloads.removeValue(forKey: songId)
            lock.unlock()
        }

        // CRITICAL: Move file synchronously before delegate returns,
        // because URLSession deletes the temp file after this method returns.
        let tempDir = FileManager.default.temporaryDirectory
        let safeCopy = tempDir.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: safeCopy)
        } catch {
            print("Failed to preserve download for songId: \(songId)")
            return
        }

        Task { @MainActor in
            let modelContext = PersistenceController.shared.container.mainContext
            let descriptor = FetchDescriptor<DownloadedSong>(
                predicate: #Predicate { $0.songId == songId }
            )
            guard let download = try? modelContext.fetch(descriptor).first else {
                try? FileManager.default.removeItem(at: safeCopy)
                return
            }

            let destURL = Self.absoluteURL(for: download.localFilePath)

            try? FileManager.default.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Remove existing file if re-downloading
            try? FileManager.default.removeItem(at: destURL)

            do {
                try FileManager.default.moveItem(at: safeCopy, to: destURL)
                download.isComplete = true
                download.fileSize = Int64(
                    (try? FileManager.default.attributesOfItem(
                        atPath: destURL.path
                    ))?[.size] as? Int ?? 0
                )
            } catch {
                print("Failed to move download to destination for songId: \(songId)")
                try? FileManager.default.removeItem(at: safeCopy)
            }

            try? modelContext.save()
            DownloadProgress.shared.remove(songId: songId)

            // Evict old cache if over limit
            CacheManager.shared.evictIfNeeded()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let songId = downloadTask.taskDescription,
              totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            DownloadProgress.shared.update(songId: songId, progress: progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error else { return }
        guard let songId = task.taskDescription else { return }

        lock.lock()
        activeDownloads.removeValue(forKey: songId)
        lock.unlock()

        let isCancelled = (error as NSError).code == NSURLErrorCancelled
        if !isCancelled {
            print("Download failed for songId: \(songId)")
        }

        // Clean up incomplete SwiftData record for failed (non-cancelled) downloads
        // Cancelled downloads are cleaned up in cancelDownload()
        if !isCancelled {
            Task { @MainActor in
                let modelContext = PersistenceController.shared.container.mainContext
                let descriptor = FetchDescriptor<DownloadedSong>(
                    predicate: #Predicate { $0.songId == songId && $0.isComplete == false }
                )
                if let download = try? modelContext.fetch(descriptor).first {
                    modelContext.delete(download)
                    try? modelContext.save()
                }
                DownloadProgress.shared.remove(songId: songId)
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = self.completionHandler
        self.completionHandler = nil
        DispatchQueue.main.async {
            handler?()
        }
    }
}
