import Foundation
import SwiftData

final class DownloadManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = DownloadManager()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.veydrune.downloads"
        )
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private let lock = NSLock()
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    private var _completionHandler: (() -> Void)?
    var completionHandler: (() -> Void)? {
        get { lock.withLock { _completionHandler } }
        set { lock.withLock { _completionHandler = newValue } }
    }

    // MARK: - Public API

    @MainActor
    func download(song: Song, client: SubsonicClient) {
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
            guard let downloads = try? modelContext.fetch(descriptor) else { return }

            for download in downloads {
                let fileURL = Self.absoluteURL(for: download.localFilePath)
                try? FileManager.default.removeItem(at: fileURL)
                modelContext.delete(download)
            }
            try? modelContext.save()

            try? FileManager.default.removeItem(at: Self.downloadsDirectory)
            DownloadProgress.shared.clear()
        }
    }

    // MARK: - Path Helpers

    static func localPath(for song: Song) -> String {
        let artist = song.artist?.sanitizedFileName ?? "Unknown"
        let album = song.album?.sanitizedFileName ?? "Unknown"
        let suffix = song.suffix ?? "mp3"
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
            print("Failed to preserve download: \(error)")
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
                print("Failed to move download to destination: \(error)")
                try? FileManager.default.removeItem(at: safeCopy)
            }

            try? modelContext.save()
            DownloadProgress.shared.remove(songId: songId)
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
            print("Download failed: \(error)")
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
