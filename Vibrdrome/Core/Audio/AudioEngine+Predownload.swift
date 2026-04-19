//
//  AudioEngine+Predownload.swift
//  Vibrdrome
//
//  Created by Al Bastien on 2026-04-15.
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
}

/// Actor for managing long-running predownload operations
actor PredownloadManager {
    private var task: Task<Void, Never>?
    private var pendingSongs: [Song] = []
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
    
    /// Start long-running predownload task
    func startPredownloadTask() async {
        guard !isRunning else {
            predownloadLog.debug("aldebug: Predownload task already running")
            return
        }
        
        isRunning = true
        status = .idle
        predownloadLog.info("aldebug: Starting long-running predownload task")
        
        task = Task {
            await processPredownloadQueue()
        }
    }
    
    /// Stop long-running predownload task
    func stopPredownloadTask() async {
        task?.cancel()
        task = nil
        isRunning = false
        status = .idle
        pendingSongs.removeAll()
        currentDownloadSong = nil
        lastProgressUpdate = nil
        lastProgressValue = 0.0
        predownloadLog.info("aldebug: Stopped long-running predownload task")
    }
    
    /// Add songs to predownload queue
    func addSongs(_ songs: [Song], needsPrepareLookahead: Bool = false) async {
        pendingSongs.append(contentsOf: songs)
        self.needsPrepareLookahead = needsPrepareLookahead
        self.hasCalledPrepareLookahead = false // Reset flag for new batch
        predownloadLog.debug("aldebug: Added \(songs.count) songs to predownload queue, needsPrepareLookahead: \(needsPrepareLookahead)")
    }
    
    /// Process predownload queue with single download at a time
    private func processPredownloadQueue() async {
        while !pendingSongs.isEmpty && !Task.isCancelled {
            guard let song = pendingSongs.first else { continue }
            
            await downloadSong(song)
            
            // Call prepareLookahead after first song is downloaded if needed
            if needsPrepareLookahead && !hasCalledPrepareLookahead {
                await MainActor.run {
                    AudioEngine.shared.prepareLookahead()
                }
                hasCalledPrepareLookahead = true
                predownloadLog.info("aldebug: Called prepareLookahead after first song download")
            }
            
            // Remove completed song from queue
            if let index = pendingSongs.firstIndex(where: { $0.id == song.id }) {
                pendingSongs.remove(at: index)
            }
        }
        
        isRunning = false
        status = .idle
        predownloadLog.info("aldebug: Predownload task completed")
    }
    
    /// Download a single song with progress monitoring
    private func downloadSong(_ song: Song) async {
        // Check if song is already downloaded
        if await isSongAlreadyDownloaded(song) {
            predownloadLog.info("aldebug: Song \(song.title) is already downloaded, skipping")
            return
        }
        
        currentDownloadSong = song
        status = .active
        lastProgressUpdate = Date()
        lastProgressValue = 0.0
        
        predownloadLog.info("aldebug: Starting download for \(song.title)")
        
        // Start download using DownloadManager
        let downloadManager = DownloadManager.shared
        let client = await AppState.shared.subsonicClient
        
        // Start the download (runs async on MainActor)
        Task { @MainActor in
            downloadManager.download(song: song, client: client)
        }
        
        // Monitor progress until completion
        await monitorDownloadProgress(songId: song.id)
        
        predownloadLog.info("aldebug: Completed download for \(song.title)")
        
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
        // Wait for download to actually start
        var downloadStarted = false
        var startupTimeout = false
        let startupTimeoutDuration: TimeInterval = 30.0 // 30 seconds startup timeout
        
        predownloadLog.info("aldebug: Starting monitorDownloadProgress for \(songId)")
        
        while !Task.isCancelled && !downloadStarted {
            let currentProgress = await MainActor.run {
                DownloadProgress.shared.progress(for: songId)
            }
            
            // Download has started when progress > 0
            if currentProgress > 0 {
                downloadStarted = true
                predownloadLog.debug("aldebug: Download started for songId: \(songId)")
            } else if !startupTimeout {
                // Check if startup timeout reached
                let timeSinceStart = Date().timeIntervalSince(lastProgressUpdate ?? Date())
                if timeSinceStart > startupTimeoutDuration {
                    startupTimeout = true
                    status = .stalled
                    predownloadLog.warning("aldebug: Download startup timeout for songId: \(songId), continuing to wait")
                    // Continue waiting - don't return, let's loop continue checking
                } else {
                    // Check every 0.5 seconds for download to start
                    try? await Task.sleep(for: .milliseconds(20))
                }
            } else {
                // Already timed out, check every 0.5 seconds
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        
        // Now monitor the actual download progress
        while !Task.isCancelled {
            // Get current progress from singleton on main actor
            let currentProgress = await MainActor.run {
                DownloadProgress.shared.progress(for: songId)
            }
            
            // Check if download is complete (progress removed from DownloadProgress)
            let isComplete = await MainActor.run {
                DownloadProgress.shared.progressBySongId[songId] == nil
            }
            
            if isComplete {
                predownloadLog.info("aldebug: Download completed for songId: \(songId), final progress: \(currentProgress)")
                return
            }
            
            let currentTime = Date()
            
            // Check for stall
            if let lastUpdate = lastProgressUpdate {
                let timeSinceUpdate = currentTime.timeIntervalSince(lastUpdate)
                
                // Check if progress has changed
                if currentProgress > lastProgressValue {
                    lastProgressUpdate = Date()
                    lastProgressValue = currentProgress
                    status = .active
                } else if timeSinceUpdate > stallTimeout {
                    status = .stalled
                    predownloadLog.warning("aldebug: Download stalled for songId: \(songId)")
                    
                    // Wait a bit more to see if it recovers
                    try? await Task.sleep(for: .seconds(1))
                    
                    // Check progress again
                    let recoveryProgress = await MainActor.run {
                        DownloadProgress.shared.progress(for: songId)
                    }
                    
                    // If still no progress, keep waiting (don't mark as failed)
                    if recoveryProgress <= lastProgressValue {
                        predownloadLog.warning("aldebug: Download still stalled for songId: \(songId), continuing to wait")
                        // Continue waiting - don't return, let the loop continue checking
                    } else {
                        // Recovered, reset status and continue
                        status = .active
                        lastProgressUpdate = Date()
                        lastProgressValue = recoveryProgress
                    }
                }
            }
            
            // Check progress more frequently - every 0.5 seconds
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    
    /// Check if a song is already downloaded
    private func isSongAlreadyDownloaded(_ song: Song) async -> Bool {
        return await MainActor.run {
            AudioEngine.isSongDownloaded(song)
        }
    }
    

        
    /// Get current download information
    func getCurrentDownloadInfo() -> (song: Song?, songId: String?, status: PredownloadStatus) {
        return (currentDownloadSong, currentDownloadSong?.id, status)
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
    func getRandomDownloadedSong() -> Song? {
        let modelContext = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.isComplete == true }
        )
        
        guard let songs = try? modelContext.fetch(descriptor), !songs.isEmpty else {
            predownloadLog.debug("aldebug: No downloaded songs available")
            return nil
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
        
        // Filter out songs from last maxRandomSongsPlayed returned
        let availableSongIds = ids.filter { songId in
            !randomSongsPlayedIds.contains(songId)
        }
        
        // If all downloaded songs are in the last maxRandomSongsPlayed, reset tracking and return random
        if availableSongIds.isEmpty {
            predownloadLog.debug("aldebug: All downloaded songs in last \(Self.maxRandomSongsPlayed), resetting tracking")
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
            predownloadLog.debug("aldebug: Returning random downloaded song: \(song.songTitle)")
            return song.toSong()
        }
        
        return nil
    }
    
    /// Start predownload for current song if needed
    /// - Parameters: startIndex - index of first song to play, queue - current song queue
    func startPredownloadIfNeeded(startIndex: Int, queue: [Song]) {
        guard startIndex < queue.count else {
            predownloadLog.debug("startPredownloadIfNeeded: No next song to predownload")
            return
        }
        
        let startSong = queue[startIndex]
        var nextSong = startSong
        let nextIndex = startIndex + 1
        if (nextIndex < queue.count) {
            nextSong = queue[nextIndex]
        } else {
            predownloadLog.info("aldebug: startPredownloadIfNeeded: Last Song no predownloading \(startSong.title)")
            return
        }
        predownloadLog.info("aldebug: startPredownloadIfNeeded: Starting predownload for \(nextSong.title)")
        
        // Get downloaded random song
        if (predownloadStatus == .stalled) {
            if (!AudioEngine.isSongDownloaded(nextSong)) {
                if let randomSong = getRandomDownloadedSong() {
                    insertSongNext(for: randomSong, at: nextIndex)
                    prepareLookahead()
                }
            } else {
                predownloadLog.info("aldebug: Download stalled but \(nextSong.title) is already downloaded")
            }
        } else {
            performPredownload(song: nextSong, nextIndex: nextIndex, queue: queue, needsPrepareLookahead: true)
        }
    }
       
    /// Perform actual predownload of songs starting from specified index
    /// - Parameters: song - starting song to predownload, nextIndex - index of song in queue, queue - current song queue, needsPrepareLookahead - whether prepareLookahead should be called
    private func performPredownload(song: Song, nextIndex: Int, queue: [Song], needsPrepareLookahead: Bool) {
        predownloadLog.debug("aldebug: performPredownload: Starting predownload for \(song.title) at index \(nextIndex)")
        
        // Get number of songs to preload from settings
        let preloadCount = UserDefaults.standard.integer(forKey: UserDefaultsKeys.preloadSongs)
        guard preloadCount > 0 else {
            predownloadLog.debug("aldebug: performPredownload: Preload songs is set to 0, skipping")
            return
        }
        
        // Calculate songs to download (from nextIndex up to preloadCount)
        let endIndex = min(nextIndex + preloadCount, queue.count)
        let songsToDownload = Array(queue[nextIndex..<endIndex])
        
        guard !songsToDownload.isEmpty else {
            predownloadLog.debug("aldebug: performPredownload: No songs to download")
            return
        }
            
        predownloadLog.info("aldebug: performPredownload: Starting download of \(songsToDownload.count) songs from index \(nextIndex)")
            
        // Start predownload manager with songs
        Task {
            await predownloadManager.addSongs(songsToDownload, needsPrepareLookahead: needsPrepareLookahead)
            await predownloadManager.startPredownloadTask()
        }
    }
}
