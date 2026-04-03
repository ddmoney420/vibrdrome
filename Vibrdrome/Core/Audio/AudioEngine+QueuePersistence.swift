import Foundation
import SwiftData
import os.log

private let queueLog = Logger(subsystem: "com.vibrdrome.app", category: "PlayQueue")

// MARK: - Play Queue Persistence

extension AudioEngine {

    /// Save the current play queue to the server so it can be restored later.
    func savePlayQueue(client: SubsonicClient) {
        let savedQueue = queue
        guard !savedQueue.isEmpty else {
            // Nothing to save — don't overwrite server with stale data
            // (server queue will be stale but local clearSavedQueue handles it)
            return
        }
        let ids = savedQueue.map(\.id)
        let currentId = currentSong?.id
        let position = Int(currentTime * 1000)
        Task {
            do {
                try await client.savePlayQueue(
                    ids: ids, current: currentId, position: position)
            } catch {
                queueLog.error("Failed to save play queue: \(error)")
            }
        }
    }

    /// Restore the play queue, preferring the local save (synchronous, always current)
    /// and falling back to the server if no local data exists.
    func restorePlayQueue(client: SubsonicClient) {
        // Only restore if nothing is currently playing
        guard currentSong == nil, currentRadioStation == nil, queue.isEmpty else { return }

        // Local save is always the most recent snapshot (saved synchronously on background)
        if restoreQueueLocally() { return }

        // No local data — try the server
        Task {
            let playQueue: PlayQueue?
            do {
                playQueue = try await client.getPlayQueue()
            } catch {
                queueLog.error("Failed to restore play queue from server: \(error.localizedDescription)")
                return
            }
            guard let songs = playQueue?.entry, !songs.isEmpty else {
                return
            }

            queue = songs

            if let currentId = playQueue?.current,
               let index = songs.firstIndex(where: { $0.id == currentId }) {
                currentIndex = index
                currentSong = songs[index]
                if let position = playQueue?.position, position > 0 {
                    currentTime = Double(position) / 1000.0
                }
                NowPlayingManager.shared.update(song: songs[index], isPlaying: false)
            }
        }
    }

    // MARK: - Local Queue Persistence

    /// Save the current queue state to SwiftData for offline fallback.
    func saveQueueLocally() {
        let songQueue = queue
        let context = PersistenceController.shared.container.mainContext

        // If the queue is empty, save radio station info if playing, otherwise clear
        if songQueue.isEmpty {
            if let station = currentRadioStation {
                saveRadioStationLocally(station: station, context: context)
            } else {
                clearSavedQueue()
            }
            return
        }

        // Also ensure CachedSong metadata exists for each song in the queue
        for song in songQueue {
            let songId = song.id
            let cachedDescriptor = FetchDescriptor<CachedSong>(
                predicate: #Predicate { $0.id == songId }
            )
            if (try? context.fetch(cachedDescriptor).first) == nil {
                context.insert(CachedSong(from: song))
            }
        }

        // Upsert the SavedQueue record
        let descriptor = FetchDescriptor<SavedQueue>(
            predicate: #Predicate { $0.id == "current" }
        )
        let saved: SavedQueue
        if let existing = try? context.fetch(descriptor).first {
            saved = existing
        } else {
            saved = SavedQueue()
            context.insert(saved)
        }

        saved.songIds = songQueue.map(\.id)
        saved.currentIndex = currentIndex
        saved.currentTime = currentTime
        saved.shuffleEnabled = shuffleEnabled
        saved.isRadioMode = isRadioMode
        saved.radioSeedArtistName = radioSeedArtistName
        switch repeatMode {
        case .off: saved.repeatMode = "off"
        case .all: saved.repeatMode = "all"
        case .one: saved.repeatMode = "one"
        }
        saved.savedAt = Date()

        do {
            try context.save()
            queueLog.info("Saved queue locally (\(songQueue.count) songs, radio=\(self.isRadioMode))")
        } catch {
            queueLog.error("Failed to save queue locally: \(error)")
        }
    }

    /// Remove any saved queue record so stale data doesn't persist.
    func clearSavedQueue() {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<SavedQueue>(
            predicate: #Predicate { $0.id == "current" }
        )
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
            do {
                try context.save()
                queueLog.info("Cleared stale saved queue")
            } catch {
                queueLog.error("Failed to clear saved queue: \(error)")
            }
        }
    }

    /// Restore the queue from the local SwiftData store using CachedSong records.
    /// Returns true if a queue or radio station was successfully restored.
    @discardableResult
    func restoreQueueLocally() -> Bool {
        guard currentSong == nil, currentRadioStation == nil, queue.isEmpty else { return false }

        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<SavedQueue>(
            predicate: #Predicate { $0.id == "current" }
        )
        guard let saved = try? context.fetch(descriptor).first else {
            queueLog.info("No locally saved queue to restore")
            return false
        }

        // Check for saved radio station (internet radio — empty queue)
        if saved.songIds.isEmpty {
            if let stationName = saved.radioStationName,
               let stationUrl = saved.radioStationStreamUrl {
                let station = InternetRadioStation(
                    id: "restored",
                    name: stationName,
                    streamUrl: stationUrl,
                    homePageUrl: nil,
                    coverArt: nil
                )
                currentRadioStation = station
                queueLog.info("Restored radio station locally: \(stationName)")
                return true
            }
            queueLog.info("No locally saved queue to restore")
            return false
        }

        // Fetch CachedSong records for each saved ID, preserving order
        var songs: [Song] = []
        for songId in saved.songIds {
            let songDescriptor = FetchDescriptor<CachedSong>(
                predicate: #Predicate { $0.id == songId }
            )
            if let cached = try? context.fetch(songDescriptor).first {
                songs.append(cached.toSong())
            }
        }

        guard !songs.isEmpty else {
            queueLog.warning("No cached songs found for locally saved queue")
            return false
        }

        queue = songs
        currentIndex = min(saved.currentIndex, songs.count - 1)
        currentSong = songs[currentIndex]
        currentTime = saved.currentTime
        shuffleEnabled = saved.shuffleEnabled
        isRadioMode = saved.isRadioMode
        radioSeedArtistName = saved.radioSeedArtistName
        switch saved.repeatMode {
        case "all": repeatMode = .all
        case "one": repeatMode = .one
        default: repeatMode = .off
        }

        NowPlayingManager.shared.update(song: songs[currentIndex], isPlaying: false)
        queueLog.info("Restored queue locally (\(songs.count) songs, radio=\(saved.isRadioMode))")
        return true
    }

    /// Save radio station info when the queue is empty (internet radio mode).
    private func saveRadioStationLocally(
        station: InternetRadioStation,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<SavedQueue>(
            predicate: #Predicate { $0.id == "current" }
        )
        let saved: SavedQueue
        if let existing = try? context.fetch(descriptor).first {
            saved = existing
        } else {
            saved = SavedQueue()
            context.insert(saved)
        }

        saved.songIds = []
        saved.currentIndex = 0
        saved.currentTime = 0
        saved.radioStationName = station.name
        saved.radioStationStreamUrl = station.streamUrl
        saved.isRadioMode = false
        saved.radioSeedArtistName = nil
        saved.savedAt = Date()

        do {
            try context.save()
            queueLog.info("Saved radio station locally: \(station.name)")
        } catch {
            queueLog.error("Failed to save radio station locally: \(error)")
        }
    }

    /// Create an auto-bookmark on the server if the current track has been playing long enough.
    func createBookmarkIfNeeded(client: SubsonicClient) {
        guard let song = currentSong,
              currentTime > 30 else { return }
        let position = Int(currentTime * 1000)
        Task {
            do {
                try await client.createBookmark(
                    id: song.id, position: position, comment: "Auto-bookmark")
            } catch {
                queueLog.error("Failed to create auto-bookmark: \(error)")
            }
        }
    }

    /// Sync UI state with actual player state when returning to foreground.
    func refreshPlaybackState() {
        if currentSong != nil {
            if let player = activePlayer,
               let item = player.currentItem,
               item.status == .readyToPlay {
                currentTime = player.currentTime().seconds
                if item.duration.isNumeric {
                    duration = item.duration.seconds
                }
            }
        }
    }
}
