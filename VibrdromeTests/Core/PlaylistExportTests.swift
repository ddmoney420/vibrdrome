import Testing
import Foundation
@testable import Vibrdrome

struct PlaylistExportTests {

    private func makeSong(
        id: String = "1",
        title: String = "Test Song",
        artist: String? = "Test Artist",
        suffix: String? = "flac"
    ) -> Song {
        Song(
            id: id, parent: nil, title: title,
            album: nil, artist: artist, albumArtist: nil, albumId: nil, artistId: nil,
            track: nil, year: nil, genre: nil, coverArt: nil,
            size: nil, contentType: nil, suffix: suffix,
            duration: 180, bitRate: nil, path: nil,
            discNumber: nil, created: nil, starred: nil, userRating: nil,
            bpm: nil, replayGain: nil, musicBrainzId: nil
        )
    }

    // MARK: - exportPath

    #if os(macOS)
    @Test func exportPathUsesPlaylistAndArtistTitle() {
        let song = makeSong(title: "My Song", artist: "My Artist", suffix: "mp3")
        let path = PlaylistExportManager.exportPath(song: song, playlistName: "My Playlist", suffix: "mp3")
        #expect(path == "My Playlist/My Artist - My Song.mp3")
    }

    @Test func exportPathSanitizesIllegalChars() {
        let song = makeSong(title: "Song: Live", artist: "Artist/Band", suffix: "flac")
        let path = PlaylistExportManager.exportPath(song: song, playlistName: "Rock/Pop", suffix: "flac")
        #expect(!path.contains("/") || path.components(separatedBy: "/").count == 2)
        #expect(!path.contains(":"))
    }

    @Test func exportPathFallsBackToIdWhenTitleEmpty() {
        let song = makeSong(id: "abc123", title: "", artist: "Artist", suffix: "mp3")
        let path = PlaylistExportManager.exportPath(song: song, playlistName: "Playlist", suffix: "mp3")
        #expect(path.contains("abc123"))
    }

    @Test func exportPathUsesUnknownArtistWhenNil() {
        let song = makeSong(title: "Track", artist: nil, suffix: "flac")
        let path = PlaylistExportManager.exportPath(song: song, playlistName: "Playlist", suffix: "flac")
        #expect(path.contains("Unknown Artist"))
    }
    #endif

    // MARK: - finalSuffix

    #if os(macOS)
    @Test func finalSuffixUsesTranscodeFormatWhenSet() {
        #expect(PlaylistExportManager.finalSuffix(originalSuffix: "flac", transcodeFormat: "mp3") == "mp3")
        #expect(PlaylistExportManager.finalSuffix(originalSuffix: "flac", transcodeFormat: "aac") == "aac")
    }

    @Test func finalSuffixFallsBackToOriginalWhenNoTranscode() {
        #expect(PlaylistExportManager.finalSuffix(originalSuffix: "flac", transcodeFormat: nil) == "flac")
        #expect(PlaylistExportManager.finalSuffix(originalSuffix: "mp3", transcodeFormat: nil) == "mp3")
    }
    #endif

    // MARK: - PlaylistExportSyncMode

    @Test func syncModeRoundTrip() {
        #expect(PlaylistExportSyncMode(rawValue: "addOnly") == .addOnly)
        #expect(PlaylistExportSyncMode(rawValue: "addAndRemove") == .addAndRemove)
        #expect(PlaylistExportSyncMode(rawValue: "unknown") == nil)
        #expect(PlaylistExportSyncMode.addOnly.rawValue == "addOnly")
        #expect(PlaylistExportSyncMode.addAndRemove.rawValue == "addAndRemove")
    }

    @Test func syncModeDisplayNames() {
        #expect(!PlaylistExportSyncMode.addOnly.displayName.isEmpty)
        #expect(!PlaylistExportSyncMode.addAndRemove.displayName.isEmpty)
        #expect(PlaylistExportSyncMode.addOnly.displayName != PlaylistExportSyncMode.addAndRemove.displayName)
    }

    // MARK: - ExportedPlaylist knownSongPaths encoding

    @Test func knownSongPathsRoundTrip() {
        let export = ExportedPlaylist(
            serverId: "s1",
            playlistId: "p1",
            playlistName: "Test",
            folderBookmarkData: nil,
            syncMode: .addOnly,
            transcodeFormat: nil,
            transcodeBitrate: nil,
            isActive: true
        )
        let paths = ["id1": "Playlist/Artist - Song.mp3", "id2": "Playlist/Artist - Other.flac"]
        export.knownSongPaths = paths
        #expect(export.knownSongPaths["id1"] == "Playlist/Artist - Song.mp3")
        #expect(export.knownSongPaths["id2"] == "Playlist/Artist - Other.flac")
    }

    // MARK: - needsResync

    @Test func needsResyncWhenFormatsDiffer() {
        let export = ExportedPlaylist(
            serverId: "s1",
            playlistId: "p1",
            playlistName: "Test",
            folderBookmarkData: nil,
            syncMode: .addOnly,
            transcodeFormat: "mp3",
            transcodeBitrate: nil,
            isActive: true
        )
        export.appliedTranscodeFormat = nil
        #expect(export.needsResync == true)
    }

    @Test func noResyncWhenFormatsMatch() {
        let export = ExportedPlaylist(
            serverId: "s1",
            playlistId: "p1",
            playlistName: "Test",
            folderBookmarkData: nil,
            syncMode: .addOnly,
            transcodeFormat: "mp3",
            transcodeBitrate: nil,
            isActive: true
        )
        export.appliedTranscodeFormat = "mp3"
        #expect(export.needsResync == false)
    }

    @Test func noResyncWhenBothNil() {
        let export = ExportedPlaylist(
            serverId: "s1",
            playlistId: "p1",
            playlistName: "Test",
            folderBookmarkData: nil,
            syncMode: .addOnly,
            transcodeFormat: nil,
            transcodeBitrate: nil,
            isActive: true
        )
        export.appliedTranscodeFormat = nil
        #expect(export.needsResync == false)
    }
}
