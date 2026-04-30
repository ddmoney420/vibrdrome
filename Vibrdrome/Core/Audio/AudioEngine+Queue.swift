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

    func removeFromQueue(at index: Int) {
        let absoluteIndex = currentIndex + 1 + index
        guard absoluteIndex > currentIndex, absoluteIndex < queue.count else { return }
        queue.remove(at: absoluteIndex)
        if index == 0 && activeMode == .gapless { prepareLookahead() }
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard currentIndex + 1 < queue.count else { return }
        var upNextSlice = Array(queue[(currentIndex + 1)...])
        upNextSlice.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange((currentIndex + 1)..., with: upNextSlice)
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
