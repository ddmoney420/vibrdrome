import Testing
import Foundation
@testable import Vibrdrome

/// Tests for CachedSong ↔ Song conversion used by local queue persistence.
struct CachedSongConversionTests {

    // MARK: - Song → CachedSong → Song Round-Trip

    @Test func roundTripPreservesId() {
        let song = makeSong(id: "test123")
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.id == "test123")
    }

    @Test func roundTripPreservesTitle() {
        let song = makeSong(title: "Test Track")
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.title == "Test Track")
    }

    @Test func roundTripPreservesArtist() {
        let song = makeSong(artist: "Test Artist")
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.artist == "Test Artist")
    }

    @Test func roundTripPreservesAlbum() {
        let song = makeSong(album: "Test Album")
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.album == "Test Album")
    }

    @Test func roundTripPreservesAlbumId() {
        let song = makeSong(albumId: "album42")
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.albumId == "album42")
    }

    @Test func roundTripPreservesTrackNumber() {
        let song = makeSong(track: 7)
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.track == 7)
    }

    @Test func roundTripPreservesDiscNumber() {
        let song = makeSong(discNumber: 2)
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.discNumber == 2)
    }

    @Test func roundTripPreservesDuration() {
        let song = makeSong(duration: 240)
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.duration == 240)
    }

    @Test func roundTripPreservesYear() {
        let song = makeSong(year: 2024)
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.year == 2024)
    }

    @Test func roundTripPreservesGenre() {
        let song = makeSong(genre: "Rock")
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.genre == "Rock")
    }

    @Test func roundTripPreservesBitRate() {
        let song = makeSong(bitRate: 320)
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.bitRate == 320)
    }

    @Test func roundTripPreservesSuffix() {
        let song = makeSong(suffix: "flac")
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.suffix == "flac")
    }

    @Test func roundTripPreservesContentType() {
        let song = makeSong(contentType: "audio/flac")
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.contentType == "audio/flac")
    }

    @Test func roundTripPreservesSize() {
        let song = makeSong(size: 5_000_000)
        let cached = CachedSong(from: song)
        let restored = cached.toSong()
        #expect(restored.size == 5_000_000)
    }

    // MARK: - Starred Conversion

    @Test func starredSongPreservesStarredFlag() {
        let song = makeSong(starred: "2024-01-01T00:00:00Z")
        let cached = CachedSong(from: song)
        #expect(cached.isStarred == true)
        let restored = cached.toSong()
        #expect(restored.starred == "true")
    }

    @Test func unstarredSongPreservesUnstarred() {
        let song = makeSong(starred: nil)
        let cached = CachedSong(from: song)
        #expect(cached.isStarred == false)
        let restored = cached.toSong()
        #expect(restored.starred == nil)
    }

    // MARK: - Nil Fields

    @Test func nilOptionalFieldsRoundTrip() {
        let song = Song(
            id: "minimal", parent: nil, title: "Minimal",
            album: nil, artist: nil, albumArtist: nil, albumId: nil, artistId: nil,
            track: nil, year: nil, genre: nil, coverArt: nil,
            size: nil, contentType: nil, suffix: nil, duration: nil,
            bitRate: nil, path: nil, discNumber: nil, created: nil,
            starred: nil, userRating: nil, bpm: nil, replayGain: nil, musicBrainzId: nil
        )
        let cached = CachedSong(from: song)
        let restored = cached.toSong()

        #expect(restored.id == "minimal")
        #expect(restored.title == "Minimal")
        #expect(restored.artist == nil)
        #expect(restored.album == nil)
        #expect(restored.albumId == nil)
        #expect(restored.track == nil)
        #expect(restored.year == nil)
        #expect(restored.genre == nil)
        #expect(restored.duration == nil)
        #expect(restored.bitRate == nil)
        #expect(restored.suffix == nil)
        #expect(restored.contentType == nil)
        #expect(restored.size == nil)
    }

    // MARK: - Helpers

    private func makeSong(
        id: String = "test",
        title: String = "Test",
        artist: String? = nil,
        album: String? = nil,
        albumId: String? = nil,
        track: Int? = nil,
        year: Int? = nil,
        genre: String? = nil,
        duration: Int? = nil,
        bitRate: Int? = nil,
        suffix: String? = nil,
        contentType: String? = nil,
        size: Int? = nil,
        discNumber: Int? = nil,
        starred: String? = nil
    ) -> Song {
        Song(
            id: id, parent: nil, title: title,
            album: album, artist: artist, albumArtist: nil, albumId: albumId, artistId: nil,
            track: track, year: year, genre: genre, coverArt: nil,
            size: size, contentType: contentType, suffix: suffix,
            duration: duration, bitRate: bitRate, path: nil,
            discNumber: discNumber, created: nil, starred: starred, userRating: nil,
            bpm: nil, replayGain: nil, musicBrainzId: nil
        )
    }
}
