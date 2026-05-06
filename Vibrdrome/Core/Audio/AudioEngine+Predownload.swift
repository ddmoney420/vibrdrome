//
//  AudioEngine+Predownload.swift
//  Vibrdrome
//
//  Created by Bigalmann on 2026-04-15.
//

import AVFoundation
import Foundation
import os.log
import SwiftData

private let predownloadLog = Logger(subsystem: "com.vibrdrome.app", category: "Predownload")

// MARK: - Predownload Management

/// Communication structure for long-running predownload task
struct PredownloadTask {
    let songs: [Song]
    let startIndex: Int
    let needsPrepareLookahead: Bool
}

/// Predownload status enumeration
enum PredownloadStatus: Sendable {
    case idle
    case active
    case stalled
    case waiting
}

/// Actor for managing long-running predownload operations
actor PredownloadManager {
    private var task: Task<Void, Never>?
    private var pendingSongs: [Song] = []
    private var lastSpeeds: [Double] = []
    private var avgSpeed: Double = 0.0
    private var isRunning = false
    private var currentDownloadSong: Song?
    private var lastProgressUpdate: Date?
    private var lastProgressValue: Double = 0.0
    private var stallTimeout: TimeInterval = 30.0 // 30 seconds stall timeout
    private var needsPrepareLookahead: Bool = false
    private var hasCalledPrepareLookahead: Bool = false

    /// Current predownload status
    var status: PredownloadStatus = .idle {
        didSet {
            // Notify AudioEngine of status change
            let tempStatus = status
            Task { @MainActor in
                AudioEngine.shared.predownloadStatus = tempStatus
            }
        }
    }

    /// Stop long-running predownload task
    func stopPredownloadTask() async {
        task?.cancel()
        task = nil
        isRunning = false
        status = .idle
        pendingSongs.removeAll()
        if currentDownloadSong != nil {
            let songId: String = currentDownloadSong!.id
            // Cancel the download (runs async on MainActor)
            Task { @MainActor in
                DownloadManager.shared.cancelDownload(songId: songId)
            }
        }
        currentDownloadSong = nil
        lastProgressUpdate = nil
        lastProgressValue = 0.0
        predownloadLog.debug("Stopped long-running predownload task")
    }

    /// Add songs to predownload queue and start processing
    func startPredownloadTask(_ songs: [Song], needsPrepareLookahead: Bool = false) async {
        guard status != .stalled else {return}
        if isRunning {
            await stopPredownloadTask()
        }
        pendingSongs.append(contentsOf: songs)
        self.needsPrepareLookahead = needsPrepareLookahead
        self.hasCalledPrepareLookahead = false // Reset flag for new batch

        guard !isRunning else {
            predownloadLog.debug("Predownload task already running")
            return
        }

        isRunning = true
        status = .idle

        task = Task {
            await processPredownloadQueue()
            predownloadLog.debug("Predownload task returned")
        }

        predownloadLog.debug("Started long-running predownload task")
    }

    /// Process predownload queue with single download at a time
    private func processPredownloadQueue() async {
        var firstDownload = true

        while !pendingSongs.isEmpty && !Task.isCancelled {
            guard let song = pendingSongs.first else { continue }
            let tempCount = pendingSongs.count
            Task { @MainActor in
                AudioEngine.shared.predownloadsPending = tempCount
            }

            // Check if song is already downloaded before downloading
            let wasAlreadyDownloaded = await isSongAlreadyDownloaded(song)

            status = .waiting
            if !wasAlreadyDownloaded && firstDownload {
                predownloadLog.debug("Sleeping 10 seconds before starting download")
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                guard !Task.isCancelled else {return}
                firstDownload = false
            }
            await downloadSong(song)

            // Call prepareLookahead after first song is downloaded if needed
            if needsPrepareLookahead && !hasCalledPrepareLookahead {
                await MainActor.run {
                    AudioEngine.shared.prepareLookahead()
                }
                hasCalledPrepareLookahead = true
            }

            // Remove completed song from queue
            if let index = pendingSongs.firstIndex(where: { $0.id == song.id }) {
                pendingSongs.remove(at: index)
            }

            let tempCount2 = pendingSongs.count
            Task { @MainActor in
                AudioEngine.shared.predownloadsPending = tempCount2
            }

            status = .waiting
            // Sleep for 20 seconds between downloads, but only if song was actually downloaded and there's a next song
            // Sleep so that network is not overwhelmed
            if !wasAlreadyDownloaded && !pendingSongs.isEmpty && !Task.isCancelled {
                predownloadLog.debug("Sleeping 20 seconds before next download")
                try? await Task.sleep(nanoseconds: 20_000_000_000) // 20 seconds
                guard !Task.isCancelled else {return}
            }
        }

        isRunning = false
        status = .idle
        predownloadLog.debug("Predownload task completed successfully")
    }

    /// Download a single song with progress monitoring
    private func downloadSong(_ song: Song) async {
        // Check if song is already downloaded
        if await isSongAlreadyDownloaded(song) {
            Task { @MainActor in
                CacheManager.shared.touchAccess(songId: song.id)
            }
            return
        }

        currentDownloadSong = song
        status = .active
        lastProgressUpdate = Date()
        lastProgressValue = 0.0

        predownloadLog.debug("Starting download for \(song.title)")

        // Start download using DownloadManager
        let client = await AppState.shared.subsonicClient

        // Start the download (runs async on MainActor)
        Task { @MainActor in
            DownloadManager.shared.download(song: song, client: client, category: AudioEngine.predownloadedCategory)
        }

        // Monitor progress until completion
        await monitorDownloadProgress(songId: song.id)

        predownloadLog.debug("Completed download for song: \(song.title)")

        // Add recently downloaded song to AudioEngine's tracking to avoid immediate re-selection
        Task { @MainActor in
            AudioEngine.shared.addRandomSongPlayed(songId: song.id)
        }

        currentDownloadSong = nil
        lastProgressUpdate = nil
        lastProgressValue = 0.0
    }

    /// Monitor download progress and detect stalls
    private func monitorDownloadProgress(songId: String) async {
        var speed = 0.0
        var hasStarted = false
        let startupTimeout: TimeInterval = 20.0

        while !Task.isCancelled {
            // 1. Batch fetch state
            let (progress, currentSpeed, exists) = await MainActor.run {
                (DownloadProgress.shared.progress(for: songId),
                 DownloadProgress.shared.speed(for: songId),
                 DownloadProgress.shared.progressBySongId[songId] != nil)
            }

            // 2. State Transition: Wait for start, then wait for completion
            if !hasStarted {
                if progress > 0.01 {
                    hasStarted = true
                    lastProgressUpdate = Date()
                    status = .active
                    predownloadLog.debug("Song download started for song: \(songId)")
                } else if Date().timeIntervalSince(lastProgressUpdate ?? Date()) > startupTimeout {
                    status = .stalled
                    predownloadLog.warning("Startup timeout for song: \(songId)")
                }
            } else if !exists || progress >= 1.0 { // Started, now check for completion
                break
            }

            // 3. Stall & Speed Logic (only if started)
            if hasStarted {
                if progress > 0.5 { speed = currentSpeed }
                if progress > lastProgressValue {
                    lastProgressUpdate = Date(); lastProgressValue = progress; status = .active
                } else if Date().timeIntervalSince(lastProgressUpdate ?? Date()) > stallTimeout {
                    status = .stalled
                    predownloadLog.warning("Stalled for song: \(songId)")
                }
            }

            try? await Task.sleep(for: .milliseconds(hasStarted ? 200 : 20))
        }

        // 4. Finalize Averages
        if speed > 0 {
            lastSpeeds = (lastSpeeds + [speed]).suffix(3)
            avgSpeed = lastSpeeds.reduce(0, +) / Double(lastSpeeds.count)
            let finalAvg = avgSpeed
            await MainActor.run { AudioEngine.shared.predownloadSpeed = finalAvg }
        }
    }
    
    /// Check if a song is already downloaded
    private func isSongAlreadyDownloaded(_ song: Song) async -> Bool {
        await MainActor.run {
            AudioEngine.isSongDownloaded(song)
        }
    }
}

extension AudioEngine {

    /// Add song ID to random songs played tracking
    func addRandomSongPlayed(songId: String) {
        randomSongsPlayedIds.append(songId)
        if randomSongsPlayedIds.count > Self.maxRandomSongsPlayed {
            randomSongsPlayedIds.removeFirst(randomSongsPlayedIds.count - Self.maxRandomSongsPlayed)
        }
    }

    /// Reset random songs played tracking
    func resetRandomSongsPlayed() {
        randomSongsPlayedIds.removeAll()
    }

    /// Get a random downloaded song, avoiding duplicates from last maxRandomSongsPlayed returned songs
    /// and from songs recently played in the current queue session.
    @MainActor
    func getRandomDownloadedSong() -> Song? {
        let modelContext = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.isComplete == true }
        )

        guard let songs = try? modelContext.fetch(descriptor), !songs.isEmpty else {
            predownloadLog.info("No downloaded songs available")
            return nil
        }

        // Merge the in-memory dedup list with songs actually played in this session
        // (recentlyPlayed returns up to 20 most-recent tracks from the queue history).
        // This prevents repeats even after an app restart when randomSongsPlayedIds is empty.
        let recentlyPlayedIds = Set(recentlyPlayed.map(\.id))
        if !recentlyPlayedIds.isEmpty {
            for id in recentlyPlayedIds where !randomSongsPlayedIds.contains(id) {
                addRandomSongPlayed(songId: id)
            }
        }
        // Also exclude the currently playing song
        if let currentId = currentSong?.id, !randomSongsPlayedIds.contains(currentId) {
            addRandomSongPlayed(songId: currentId)
        }

        let ids = songs.map { $0.songId }

        // If we have fewer than maxRandomSongsPlayed songs total, just return a random one
        if ids.count <= Self.maxRandomSongsPlayed {
            let randomSong = songs.randomElement()
            if let song = randomSong {
                addRandomSongPlayed(songId: song.songId)
                return song.toSong()
            }
            return nil
        }

        // Filter out recently played and previously returned songs
        let availableSongIds = ids.filter { songId in
            !randomSongsPlayedIds.contains(songId)
        }

        // If all downloaded songs are in the last maxRandomSongsPlayed, reset tracking and return random
        if availableSongIds.isEmpty {
            predownloadLog.debug("All downloaded songs in last \(Self.maxRandomSongsPlayed), resetting tracking")
            resetRandomSongsPlayed()
            let randomSong = songs.randomElement()
            if let song = randomSong {
                addRandomSongPlayed(songId: song.songId)
                return song.toSong()
            }
            return nil
        }

        // Find songs with available IDs
        let availableSongs = songs.filter { song in
            availableSongIds.contains(song.songId)
        }

        // Return random song from available songs
        let randomSong = availableSongs.randomElement()
        if let song = randomSong {
            addRandomSongPlayed(songId: song.songId)
            return song.toSong()
        }

        return nil
    }

    /// This method will monitor the currentTime and also check if the songe is 30 seconds from the end
    /// If it is it will validate that the next song is downloaded
    /// If not insert a downloaded song
    @MainActor
    func checkPredownloadedSongNearEnd() {
        // Only act when there is a real, finite duration and we're close to the end
        guard duration > 0,
              currentTime > 0,
              duration - currentTime <= 30,
              duration - currentTime > 25 else { return }  // 25 due to cross fade

        // Skip in contexts where there is no meaningful "next song"
        guard currentRadioStation == nil,
              repeatMode != .one else { return }

        let preloadCount = UserDefaults.standard.integer(forKey: UserDefaultsKeys.preloadSongs)
        guard preloadCount > 0 else {
            return
        }

        // Guard against running more than once per track
        guard nearEndCheckSongId != currentSong?.id else { return }

        // Find out what the next song will be
        guard let nextIdx = nextSongIndex(), nextIdx < queue.count else { return }
        let nextSong = queue[nextIdx]

        // Nothing to do if the next song is already downloaded
        guard !AudioEngine.isSongDownloaded(nextSong) else { return }

        // Mark as handled before the async work so we don't re-enter
        nearEndCheckSongId = currentSong?.id

        // Insert a random downloaded song right after the current track
        guard let fallback = getRandomDownloadedSong() else {
            predownloadLog.info("checkPredownloadedSongNearEnd: no downloaded songs available to insert")
            return
        }

        let insertAt = currentIndex + 1
        insertSongNext(for: fallback, at: insertAt)
        predownloadLog.info("checkPredownloadedSongNearEnd: inserted \"\(fallback.title)\" before \"\(nextSong.title)\" (next song not downloaded)")

        // Rebuild the lookahead so gapless mode picks up the newly inserted item
        if activeMode == .gapless {
            prepareLookahead()
        }
    }

    /// Start predownload for current song if needed
    /// - Parameters: startIndex - index of first song to play, queue - current song queue
    @MainActor
    func startPredownloadIfNeeded(startIndex: Int, queue: [Song]) {
        guard startIndex < queue.count, UserDefaults.standard.integer(forKey: UserDefaultsKeys.preloadSongs) != 0,
                !isOnCellular || UserDefaults.standard.bool(forKey: UserDefaultsKeys.downloadOverCellular) else {
            predownloadLog.debug("startPredownloadIfNeeded: No next song to predownload or preload off or on Cellular")
            return
        }

        guard let nextIndex = nextSongIndex() else {
            predownloadLog.debug("startPredownloadIfNeeded: No next song to predownload")
            return
        }
        let nextSong = queue[nextIndex]

        // Get downloaded random song
        if predownloadStatus == .stalled {
            if !AudioEngine.isSongDownloaded(nextSong) {
                if let randomSong = getRandomDownloadedSong() {
                    insertSongNext(for: randomSong, at: nextIndex)
                    predownloadLog.info("Inserted random song: \(randomSong.title)")
                    prepareLookahead()
                }
            } else {
                predownloadLog.info("Download stalled but \(nextSong.title) is already downloaded")
            }
        } else {
            performPredownload(song: nextSong, queue: queue, needsPrepareLookahead: true)
        }
    }

    /// Perform actual predownload of songs using smart shuffle
    /// - Parameters: song - starting song to predownload, queue - current song queue, needsPrepareLookahead - whether prepareLookahead should be called
    @MainActor
    private func performPredownload(song: Song, queue: [Song], needsPrepareLookahead: Bool) {
        // Get number of songs to preload from settings
        let preloadCount = UserDefaults.standard.integer(forKey: UserDefaultsKeys.preloadSongs)
        guard preloadCount > 0 else {
            return
        }

        // Get next songs to predownload
        let songsToDownload = nextSongs(count: preloadCount)

        guard !songsToDownload.isEmpty else {
            predownloadLog.debug("performPredownload: No songs to download")
            return
        }

        // Start predownload manager with songs
        Task {
            await predownloadManager.startPredownloadTask(songsToDownload, needsPrepareLookahead: needsPrepareLookahead)
        }
    }
}
