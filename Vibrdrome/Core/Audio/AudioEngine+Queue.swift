import Foundation

// MARK: - Queue Management

extension AudioEngine {

    var upNext: [Song] {
        guard !queue.isEmpty, currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    /// Songs played before the current track (most recent first, max 20).
    /// Uses actual play history if available, falls back to queue position.
    var recentlyPlayed: [Song] {
        if !playHistory.isEmpty {
            return Array(playHistory.reversed().prefix(20))
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

    func addToQueueNext(_ songs: [Song]) {
        let insertAt = min(currentIndex + 1, queue.count)
        queue.insert(contentsOf: songs, at: insertAt)
        if activeMode == .gapless { prepareLookahead() }
    }

    func addToQueue(_ songs: [Song]) {
        queue.append(contentsOf: songs)
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

    /// Pick a random next index, preferring a different artist than the current track.
    func smartShuffleNextIndex() -> Int {
        guard !queue.isEmpty else { return 0 }
        let currentArtist = queue[currentIndex].artist
        // Build list of candidate indices (all except current)
        var candidates = Array(0..<queue.count)
        if candidates.count > 1 {
            candidates.remove(at: currentIndex)
        }
        // Prefer candidates with a different artist
        let differentArtist = candidates.filter { queue[$0].artist != currentArtist }
        if let pick = differentArtist.randomElement() {
            return pick
        }
        // All tracks are by the same artist — just pick any other track
        return candidates.randomElement() ?? currentIndex
    }
}
