import Foundation

/// Where a transport action or an automatic advance should land.
///
/// Pure policy, deliberately separate from the engine: repeat and shuffle semantics are the part
/// most likely to regress, and they are far easier to trust when they can be exhaustively tested
/// without scheduling any audio.
enum GaplessTransportPolicy {

    /// The next index for an *automatic* advance (a track ending on its own).
    ///
    /// Mirrors `AudioEngine.nextSequentialIndex` exactly for the sequential case:
    /// - Repeat Off: advance while another item exists, else `nil` (queue ends).
    /// - Repeat All: advance, wrapping to 0 after the last item.
    /// - Repeat One: the same index — the current track plays again.
    ///
    /// Shuffle replaces only the *sequential* choice; repeat semantics still apply on top, which is
    /// why Repeat One wins over shuffle (the current track repeats) and Repeat Off still ends.
    static func nextIndexOnCompletion(current: Int, count: Int, repeatMode: RepeatMode,
                                      shuffleEnabled: Bool,
                                      shuffleNext: () -> Int?) -> Int? {
        guard count > 0 else { return nil }
        guard repeatMode != .one else { return current }
        if shuffleEnabled {
            // A one-item queue can only replay itself, and only when repeat allows it — this is the
            // shuffle + Repeat All case that previously stuck on the current index.
            guard count > 1 else { return repeatMode == .all ? current : nil }
            if let shuffled = shuffleNext() { return shuffled }
            // No candidate (queue exhausted under the exclusion rules) — fall back to sequential so
            // playback is never stuck.
        }
        switch repeatMode {
        case .one: return current
        case .all: return (current + 1) % count
        case .off:
            let next = current + 1
            return next < count ? next : nil
        }
    }

    /// The destination for a **manual** Next.
    ///
    /// Manual navigation overrides Repeat One — a user pressing Next wants the next track, not the
    /// same one again. Under Repeat Off, manual Next at the end of the queue stops rather than
    /// wrapping, matching the automatic policy.
    static func nextIndexOnManualSkip(current: Int, count: Int, repeatMode: RepeatMode,
                                      shuffleEnabled: Bool,
                                      shuffleNext: () -> Int?) -> Int? {
        guard count > 0 else { return nil }
        // Repeat One is deliberately treated as Repeat All here: the user asked to move on, and
        // stopping at the end of a single-track loop would be surprising.
        let effectiveMode: RepeatMode = repeatMode == .one ? .all : repeatMode
        return nextIndexOnCompletion(current: current, count: count, repeatMode: effectiveMode,
                                     shuffleEnabled: shuffleEnabled, shuffleNext: shuffleNext)
    }

    /// What a Previous press should do.
    ///
    /// Existing production behaviour, preserved exactly (`AudioEngine.previous()`):
    /// - More than `restartThresholdSeconds` into the track → restart the current track.
    /// - Otherwise → go to the previous item; at index 0 there is nowhere back to, so restart.
    /// - Paused within a second of the end → treat as "go back a track" rather than restart, so a
    ///   finished-but-paused track does not trap the user.
    static func previousDestination(currentIndex: Int, count: Int, elapsed: TimeInterval,
                                    duration: TimeInterval, isPlaying: Bool) -> PreviousDestination {
        guard count > 0 else { return .restartCurrent }
        let pausedAtEnd = !isPlaying && elapsed > 0 && duration > 0 && elapsed >= duration - 1
        if !pausedAtEnd && elapsed > restartThresholdSeconds { return .restartCurrent }
        guard currentIndex > 0 else { return .restartCurrent }
        return .item(index: currentIndex - 1)
    }

    /// Read from existing behaviour, not chosen here: `AudioEngine.previous()` restarts the current
    /// track when `currentTime > 3`.
    static let restartThresholdSeconds: TimeInterval = 3

    enum PreviousDestination: Equatable, Sendable {
        case restartCurrent
        case item(index: Int)
    }
}

/// Vibrdrome's shuffle, reproduced so it can be driven deterministically in tests.
///
/// **This is not a shuffled playlist.** The production implementation never reorders the queue: it
/// picks the next index on the fly, preferring an artist different from the last pick, excluding the
/// current track, anything already lined up, and recently played tracks. That has two consequences
/// worth stating plainly, because they differ from the usual "shuffle = permuted order" model:
///
/// - There is **no original unshuffled order to restore**, because the order was never changed.
///   Turning shuffle off simply resumes sequential advance from wherever playback is.
/// - There is **no reshuffle on a Repeat All wrap**, because there is no shuffled sequence to
///   regenerate — each pick is made when it is needed.
///
/// Both are existing user-visible behaviour and are preserved rather than "fixed".
struct GaplessShufflePolicy: Sendable {
    /// Songs to keep out of the running because they were played recently. Production uses the last
    /// 20 played tracks.
    static let recentlyPlayedWindow = 20

    /// One candidate: the queue index plus the artist used for the different-artist preference.
    struct Candidate: Sendable, Equatable {
        let index: Int
        let songID: String
        let artist: String?
    }

    /// Pick the next index.
    ///
    /// - Parameters:
    ///   - candidates: every queue slot, in queue order.
    ///   - currentIndex: the audible slot, always excluded.
    ///   - alreadyPlanned: song IDs already lined up ahead, excluded so the same track is not
    ///     queued twice in a row.
    ///   - recentlyPlayed: song IDs played recently, excluded when that still leaves a choice.
    ///   - lastArtist: artist of the previous pick, used for the different-artist preference.
    ///   - generator: injected so tests can pin the outcome; production passes the system generator.
    static func nextIndex(candidates: [Candidate], currentIndex: Int,
                          alreadyPlanned: Set<String> = [], recentlyPlayed: [String] = [],
                          lastArtist: String? = nil,
                          using generator: inout some RandomNumberGenerator) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let currentSongID = candidates.first { $0.index == currentIndex }?.songID

        var excluded = alreadyPlanned
        if let currentSongID { excluded.insert(currentSongID) }
        let recentWindow = Set(recentlyPlayed.suffix(recentlyPlayedWindow))
        excluded.formUnion(recentWindow)

        var available = candidates.filter { !excluded.contains($0.songID) && $0.index != currentIndex }
        if available.isEmpty {
            // Excluding recently-played left nothing — fall back to the minimal exclusion so
            // playback is never stuck on a small queue. Production does exactly this.
            var minimal = alreadyPlanned
            if let currentSongID { minimal.insert(currentSongID) }
            available = candidates.filter { !minimal.contains($0.songID) && $0.index != currentIndex }
        }
        guard !available.isEmpty else { return nil }

        // Prefer a different artist than the previous pick; fall back to anything available.
        let differentArtist = available.filter { $0.artist != lastArtist }
        let pool = differentArtist.isEmpty ? available : differentArtist
        return pool.randomElement(using: &generator)?.index
    }
}

/// A seedable generator so shuffle tests are deterministic while production stays random.
struct GaplessSeededRandomGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Any non-zero state works; the constant just avoids a zero seed degenerating.
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        // xorshift64*: small, fast, and reproducible across platforms and runs.
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}
