import Foundation

// MARK: - Queue Management

extension AudioEngine {

    var upNext: [Song] {
        guard !queue.isEmpty, currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    /// Songs actually played before the current track (most recent first, max 20).
    var recentlyPlayed: [Song] {
        Array(playHistory.reversed().prefix(20))
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
