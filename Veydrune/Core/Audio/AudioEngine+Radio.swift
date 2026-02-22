import Foundation
import os.log

private let radioLog = Logger(subsystem: "com.veydrune.app", category: "Radio")

// MARK: - Artist Radio

extension AudioEngine {

    /// Start radio seeded from an artist name
    func startRadio(artistName: String) {
        stopRadioMode()
        isRadioMode = true
        radioSeedArtistName = artistName
        clearRadioSkippedIds()

        setRadioRefillTask(Task { [weak self] in
            guard let self else { return }
            let client = AppState.shared.subsonicClient

            var songs = (try? await client.getTopSongs(artist: artistName, count: 40)) ?? []

            if songs.isEmpty {
                songs = await self.sampleArtistAlbums(
                    artistName: artistName, client: client
                )
            }

            if songs.isEmpty {
                songs = (try? await client.getRandomSongs(size: 30)) ?? []
            }

            guard !Task.isCancelled else { return }
            let unique = self.deduplicateRadioSongs(songs, against: [])
            guard let first = unique.first else {
                self.isRadioMode = false
                self.radioSeedArtistName = nil
                return
            }
            self.play(song: first, from: unique)
        })
    }

    /// Start radio seeded from a specific song
    func startRadioFromSong(_ song: Song) {
        if let artistName = song.artist {
            startRadio(artistName: artistName)
        } else {
            stopRadioMode()
            isRadioMode = true
            radioSeedArtistName = nil
            clearRadioSkippedIds()
            setRadioRefillTask(Task { [weak self] in
                guard let self else { return }
                let client = AppState.shared.subsonicClient
                var songs = (try? await client.getSimilarSongs(
                    id: song.id, count: 30
                )) ?? []
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
