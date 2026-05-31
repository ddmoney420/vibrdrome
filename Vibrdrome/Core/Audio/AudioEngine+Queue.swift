import Foundation
import os.log

private let queueLog = Logger(subsystem: "com.vibrdrome.app", category: "Audio")

// MARK: - Queue Management

extension AudioEngine {

    var upNext: [Song] {
        guard !queue.isEmpty, currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    /// Songs played before the current track (most recent first, max 20).
    /// When shuffle is enabled, returns from the actual shuffle playback
    /// history rather than linear queue position, which would be meaningless.
    var recentlyPlayed: [Song] {
        if shuffleEnabled {
            return Array(shufflePlayHistory.reversed().prefix(20))
        }
        guard currentIndex > 0 else { return [] }
        return Array(queue[0..<currentIndex].reversed().prefix(20))
    }

    /// Upcoming tracks (queue[currentIndex+1...]) with absolute queue indices
    /// so callers can pass them back to skipToIndex / removeFromQueue.
    var upNextEntries: [(index: Int, song: Song)] {
        guard !queue.isEmpty, currentIndex + 1 < queue.count else { return [] }

        if shuffleEnabled {
            let entries = nextSongIndices(count: 5)
            return (0 ..< entries.count).map { idx in
                (index: entries[idx], song: queue[entries[idx]])
            }
        }
        return (currentIndex + 1 ..< queue.count).map { idx in
            (index: idx, song: queue[idx])
        }
    }

    /// All queue tracks except the currently playing one, with absolute queue indices.
    /// Used by QueueView and SidePanels for full-queue display.
    var queueEntries: [(index: Int, song: Song)] {
        guard !queue.isEmpty else { return [] }
        return queue.enumerated()
            .filter { $0.offset != currentIndex }
            .map { (index: $0.offset, song: $0.element) }
    }

    func addToQueue(_ song: Song) {
        queue.append(song)
        if queue.count == currentIndex + 2 && activeMode == .gapless {
            prepareLookahead()
        }
    }

    func addToQueueNext(_ song: Song) {
        queue.insert(song, at: min(currentIndex + 1, queue.count))
        if activeMode == .gapless { prepareLookahead() }
    }

    func addToQueueNext(_ songs: [Song]) {
        let insertAt = min(currentIndex + 1, queue.count)
        queue.insert(contentsOf: songs, at: insertAt)
        if activeMode == .gapless { prepareLookahead() }
    }

    func addToQueue(_ songs: [Song]) {
        queue.append(contentsOf: songs)
        if activeMode == .gapless { prepareLookahead() }
    }

    /// Remove a track from the queue by its absolute queue index.
    func removeFromQueue(atAbsolute index: Int) {
        guard index >= 0, index < queue.count, index != currentIndex else { return }
        queue.remove(at: index)
        if index < currentIndex { currentIndex -= 1 }
        if activeMode == .gapless { prepareLookahead() }
    }

    /// Reorder tracks within the Up Next section only.
    /// Source/destination are offsets into `upNextEntries`; they get shifted
    /// by currentIndex+1 to land in the real queue array. Tracks before the
    /// current track are untouched.
    func moveInUpNext(from source: IndexSet, to destination: Int) {
        let startIndex = currentIndex + 1
        guard startIndex < queue.count else { return }
        let upNextCount = queue.count - startIndex
        guard destination >= 0, destination <= upNextCount else { return }
        let absoluteSource = IndexSet(source.compactMap { offset in
            let abs = startIndex + offset
            return abs < queue.count ? abs : nil
        })
        guard !absoluteSource.isEmpty else { return }
        let absoluteDestination = startIndex + destination
        queue.move(fromOffsets: absoluteSource, toOffset: absoluteDestination)
        if activeMode == .gapless { prepareLookahead() }
    }

    /// Reorder tracks within the queue display (all tracks except currently playing).
    /// Source/destination are relative to `queueEntries` (the all-except-current array).
    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard queue.count > 1 else { return }
        let savedSong = queue[currentIndex]
        let afterCurrentId: String? = currentIndex + 1 < queue.count
            ? queue[currentIndex + 1].id : nil

        var items = Array(queue)
        items.remove(at: currentIndex)
        items.move(fromOffsets: source, toOffset: destination)

        // Reinsert current song right before the track that was originally after it
        let insertAt: Int
        if let afterId = afterCurrentId,
           let pos = items.firstIndex(where: { $0.id == afterId }) {
            insertAt = pos
        } else {
            insertAt = items.count
        }
        items.insert(savedSong, at: insertAt)

        queue = items
        currentIndex = insertAt
        if activeMode == .gapless { prepareLookahead() }
    }

    func clearQueue() {
        let current = currentIndex < queue.count ? queue[currentIndex] : nil
        queue.removeAll()
        if activeMode == .gapless { clearLookahead() }
        stopRadioMode()
        if let current {
            queue.append(current)
            currentIndex = 0
        } else {
            stop()
        }
    }

    /// Rearrange shuffled queue to avoid consecutive tracks by the same artist.
    /// Used by radio and other features that pre-shuffle song arrays.
    func smartShuffle(_ songs: [Song]) -> [Song] {
        guard songs.count > 1 else { return songs }
        var result = songs.shuffled()
        for idx in 1..<result.count where result[idx].artist == result[idx - 1].artist {
            if let swapIndex = ((idx + 1)..<result.count)
                .first(where: { result[$0].artist != result[idx].artist }) {
                result.swapAt(idx, swapIndex)
            }
        }
        return result
    }

    /// Important Note: Smart shuffle relies on monitoring the current playing song to know when to advance the song automatically
    /// Otherwise the same cached songs are returned.  This is need for pre-downloading
    /// Pick a random next index, preferring a different artist than the current track.
    /// Delegates entirely to getNextSmartShuffleSongs so there is one cache and
    /// one source of truth for the upcoming shuffle sequence.
    func smartShuffleNextIndex() -> Int {
        guard !queue.isEmpty else { return 0 }
        guard let next = getNextSmartShuffleSongs(count: 1).first,
              let idx = queue.firstIndex(where: { $0.id == next.id }) else {
            // Fallback: pick any song that isn't the current one
            let candidates = queue.indices.filter { $0 != currentIndex }
            return candidates.randomElement() ?? currentIndex
        }
        return idx
    }

    /// Returns the next `count` songs in shuffle order, preferring different artists
    /// consecutively. Results are cached and keyed to `currentIndex` so repeated
    /// calls for the same position are free. The cache advances automatically when
    /// `currentIndex` moves forward, consuming the head of the sequence.
    func getNextSmartShuffleSongs(count: Int = 5) -> [Song] {
        guard !queue.isEmpty, count > 0 else { return [] }

        // Invalidate or advance the cache whenever the current position changes.
        if cachedSmartShuffleSongId != queue[currentIndex].id {
            let previousId = cachedSmartShuffleSongId

            // If the caller just moved to the song that was at the front of the
            // cached sequence, consume it and keep the rest intact.
            if let first = cachedSmartShuffleSongs.first, first.id == queue[currentIndex].id {
                cachedSmartShuffleSongs.removeFirst()
                queueLog.debug("smartShuffle - advanced cache, \(self.cachedSmartShuffleSongs.count) remaining")
            } else if previousId != nil {
                // Jumped to an unexpected position — flush and rebuild.
                cachedSmartShuffleSongs.removeAll()
                queueLog.debug("smartShuffle - cache flushed (unexpected position change)")
            }

            cachedSmartShuffleSongId = queue[currentIndex].id
        }

        // Top up the cache to `count` songs if needed.
        if cachedSmartShuffleSongs.count < count {
            let needed = count - cachedSmartShuffleSongs.count

            // Build the exclusion set: current song + already-cached upcoming songs
            // + recently played songs (up to 20 tracks behind current index).
            var excludedIds = Set(cachedSmartShuffleSongs.map(\.id))
            excludedIds.insert(queue[currentIndex].id)
            let recentlyPlayedIds = Set(recentlyPlayed.map(\.id))
            excludedIds.formUnion(recentlyPlayedIds)

            var available = queue.indices.filter { !excludedIds.contains(queue[$0].id) }

            // If excluding recently played leaves nothing to pick from, fall back to
            // only excluding the current song and already-queued upcoming tracks so
            // playback is never stuck (e.g. small queues).
            if available.isEmpty {
                let minExcludedIds = Set(cachedSmartShuffleSongs.map(\.id))
                    .union([queue[currentIndex].id])
                available = queue.indices.filter { !minExcludedIds.contains(queue[$0].id) }
            }

            guard !available.isEmpty else {
                // Queue is too small to fill — return whatever we have.
                return Array(cachedSmartShuffleSongs.prefix(count))
            }

            // The "last artist" in the sequence so far — used to avoid consecutive
            // same-artist picks when growing the cache.
            var lastArtist = cachedSmartShuffleSongs.last?.artist ?? queue[currentIndex].artist
            var remaining = available

            for _ in 0..<needed {
                guard !remaining.isEmpty else { break }

                let differentArtist = remaining.filter { queue[$0].artist != lastArtist }
                let chosen = (differentArtist.randomElement() ?? remaining.randomElement())!

                cachedSmartShuffleSongs.append(queue[chosen])
                lastArtist = queue[chosen].artist
                remaining.removeAll { $0 == chosen }
            }

            queueLog.debug("smartShuffle - cache topped up to \(self.cachedSmartShuffleSongs.count) songs")
        }

        return Array(cachedSmartShuffleSongs.prefix(count))
    }

    /// Get next songs up to 5, similar using nextSongIndices
    func nextSongs(count: Int = 5) -> [Song] {
        let songs = nextSongIndices(count: count).map { queue[$0] }
        let titles = songs.map(\.title).joined(separator: ", ")
        queueLog.debug("nextSongs: \(titles)")
        return songs
    }

    /// Get next song indexes up to 5, similar to nextSongIndex but returning multiple indexes
    /// Uses getNextSmartShuffleSongs when shuffle is enabled, sequential indices otherwise
    func nextSongIndices(count: Int = 5) -> [Int] {
        guard !queue.isEmpty else { return [] }
        guard count > 0 else { return [] }

        let actualCount = min(count, 5) // Limit to 5 as requested

        if repeatMode == .all {
            // Gapless loop - return current index repeated
            return Array(repeating: currentIndex, count: actualCount)
        }
        if repeatMode == .one {
            return [] // Handled in handleTrackEnd
        }
        if currentRadioStation != nil {
            return []
        }

        if shuffleEnabled {
            // Use smart shuffle to get songs, then convert to indexes
            let nextSongs = getNextSmartShuffleSongs(count: actualCount)
            return nextSongs.compactMap { song in
                queue.firstIndex(where: { $0.id == song.id })
            }
        } else {
            // Sequential indices
            var indexes: [Int] = []
            var nextIndex = currentIndex + 1

            for _ in 0..<actualCount {
                if nextIndex < queue.count {
                    indexes.append(nextIndex)
                    nextIndex += 1
                } else if repeatMode == .all {
                    // Wrap around to beginning
                    nextIndex = 0
                    if nextIndex < queue.count {
                        indexes.append(nextIndex)
                        nextIndex += 1
                    } else {
                        break
                    }
                } else {
                    break
                }
            }

            queueLog.debug("nextSongIndices: \(indexes)")
            return indexes
        }
    }
}
