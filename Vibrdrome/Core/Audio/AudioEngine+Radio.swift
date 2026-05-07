import Foundation
import os.log

private let radioLog = Logger(subsystem: "com.vibrdrome.app", category: "Radio")

// MARK: - Artist Radio

extension AudioEngine {

    /// Start radio seeded from an artist name.
    /// Blends the selected artist's tracks with similar artists for variety.
    func startRadio(artistName: String) {
        stopRadioMode()
        isRadioMode = true
        radioSeedArtistName = artistName
        clearRadioSkippedIds()

        setRadioRefillTask(Task { [weak self] in
            guard let self else { return }
            let client = AppState.shared.subsonicClient

            // Fetch the selected artist's top songs
            var artistSongs = (try? await client.getTopSongs(artist: artistName, count: 25)) ?? []

            if artistSongs.isEmpty {
                artistSongs = await self.sampleArtistAlbums(
                    artistName: artistName, client: client
                )
            }

            guard !Task.isCancelled else { return }

            // Fetch similar artist tracks using the first song as a seed
            var similarSongs: [Song] = []
            if let seedSong = artistSongs.first {
                similarSongs = (try? await client.getSimilarSongs(
                    id: seedSong.id, count: 20
                )) ?? []
            }

            // If getSimilarSongs2 returned empty, try genre-based random songs
            if similarSongs.isEmpty, let genre = artistSongs.first?.genre {
                similarSongs = (try? await client.getRandomSongs(
                    size: 20, genre: genre
                )) ?? []
            }

            // Last resort: server-wide random songs
            if similarSongs.isEmpty {
                similarSongs = (try? await client.getRandomSongs(size: 20)) ?? []
            }

            guard !Task.isCancelled else { return }

            // Blend: interleave artist songs with similar/genre songs
            let blended: [Song]
            if !artistSongs.isEmpty && !similarSongs.isEmpty {
                blended = self.interleaveRadioSongs(
                    primary: artistSongs.shuffled(),
                    secondary: similarSongs.shuffled()
                )
            } else if !artistSongs.isEmpty {
                blended = artistSongs.shuffled()
            } else if !similarSongs.isEmpty {
                blended = similarSongs.shuffled()
            } else {
                blended = []
            }

            guard !Task.isCancelled else { return }
            let unique = self.deduplicateRadioSongs(blended, against: [])
            guard let first = unique.first else {
                self.isRadioMode = false
                self.radioSeedArtistName = nil
                return
            }
            self.play(song: first, from: unique)
            radioLog.info("Radio started for \(artistName): \(unique.count) tracks (\(artistSongs.count) artist + \(similarSongs.count) similar)")
        })
    }

    /// Start radio seeded from a specific song. When the song has an artist
    /// tag this falls into artist radio (artist + related artists); otherwise
    /// it uses song-level similarity. Use `startSongSimilarityMix(_:)` when
    /// the caller specifically wants "songs like this one" regardless of
    /// whether the artist tag is present.
    func startRadioFromSong(_ song: Song) {
        if let artistName = song.artist {
            startRadio(artistName: artistName)
        } else {
            startSongSimilarityMix(song)
        }
    }

    /// Play a mix of songs similar to the given track, independent of the
    /// artist-radio path. Uses `getSimilarSongs` directly so the result is a
    /// song-level similarity queue, matching what "Instant Mix" / "Radio Mix"
    /// means in Apple Music / Spotify.
    func startSongSimilarityMix(_ song: Song) {
        stopRadioMode()
        isRadioMode = true
        radioSeedArtistName = nil
        clearRadioSkippedIds()
        setRadioRefillTask(Task { [weak self] in
            guard let self else { return }
            let client = AppState.shared.subsonicClient
            var songs = (try? await client.getSimilarSongs(id: song.id, count: 30)) ?? []
            if songs.isEmpty {
                songs = (try? await client.getRandomSongs(size: 20)) ?? []
            }
            guard !Task.isCancelled else { return }
            let unique = self.deduplicateRadioSongs(songs, against: [])
            guard let first = unique.first else {
                self.isRadioMode = false
                return
            }
            self.play(song: first, from: unique)
        })
    }

    /// Skip current track and block it from future radio results
    func skipAndBlock() {
        guard isRadioMode, let song = currentSong else { return }
        insertRadioSkippedId(song.id)
        next()
    }

    /// Stop radio mode without stopping playback
    func stopRadioMode() {
        isRadioMode = false
        radioSeedArtistName = nil
        clearRadioSkippedIds()
        cancelRadioRefillTask()
    }

    /// Called when approaching end of radio queue — refill with more tracks
    func refillRadioIfNeeded() {
        guard isRadioMode, currentIndex >= queue.count - 5 else { return }
        guard !hasActiveRadioRefillTask else { return }

        setRadioRefillTask(Task { [weak self] in
            guard let self else { return }
            let client = AppState.shared.subsonicClient

            var newSongs: [Song] = []
            if let currentId = self.currentSong?.id {
                newSongs = (try? await client.getSimilarSongs(
                    id: currentId, count: 30
                )) ?? []
            }

            if newSongs.isEmpty {
                let genre = self.currentSong?.genre
                newSongs = (try? await client.getRandomSongs(
                    size: 20, genre: genre
                )) ?? []
            }

            guard !Task.isCancelled else { return }
            let unique = self.deduplicateRadioSongs(newSongs, against: self.queue)
            guard !unique.isEmpty else { return }
            self.queue.append(contentsOf: unique)
            if self.activeMode == .gapless { self.prepareLookahead() }
            radioLog.info("Radio refilled with \(unique.count) tracks")
        })
    }

    func deduplicateRadioSongs(
        _ songs: [Song], against existing: [Song]
    ) -> [Song] {
        let existingIds = Set(existing.map(\.id))
        var seen = existingIds.union(getRadioSkippedIds())
        return songs.filter { song in
            guard !seen.contains(song.id) else { return false }
            seen.insert(song.id)
            return true
        }
    }

    /// Interleave primary (selected artist) and secondary (similar artists) songs.
    /// Roughly 2 primary songs per 1 secondary song to keep the selected artist dominant.
    func interleaveRadioSongs(primary: [Song], secondary: [Song]) -> [Song] {
        var result: [Song] = []
        var pIdx = 0
        var sIdx = 0
        while pIdx < primary.count || sIdx < secondary.count {
            // Add up to 2 primary songs
            for _ in 0..<2 where pIdx < primary.count {
                result.append(primary[pIdx])
                pIdx += 1
            }
            // Add 1 secondary song
            if sIdx < secondary.count {
                result.append(secondary[sIdx])
                sIdx += 1
            }
        }
        return result
    }

    func sampleArtistAlbums(
        artistName: String, client: SubsonicClient
    ) async -> [Song] {
        guard let searchResult = try? await client.search(
            query: artistName, artistCount: 1, albumCount: 0, songCount: 0
        ), let artist = searchResult.artist?.first else { return [] }
        guard let fullArtist = try? await client.getArtist(id: artist.id),
              let albums = fullArtist.album, !albums.isEmpty else { return [] }

        var allSongs: [Song] = []
        for album in albums.prefix(5) {
            guard let fullAlbum = try? await client.getAlbum(id: album.id),
                  let songs = fullAlbum.song else { continue }
            let sampled = Array(songs.shuffled().prefix(3))
            allSongs.append(contentsOf: sampled)
        }
        return allSongs.shuffled()
    }
}
