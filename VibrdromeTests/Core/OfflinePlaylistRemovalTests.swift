import Testing
@testable import Vibrdrome

/// Tests for the orphan-detection logic that backs `removeOfflinePlaylist` and
/// `refreshOfflinePlaylist`. Issue #5.
struct OfflinePlaylistRemovalTests {

    // MARK: - Removal

    @Test func removalDeletesAllSongsWhenNoOtherPlaylists() {
        let orphaned = DownloadManager.orphanedSongIds(
            forRemovedPlaylistSongs: ["s1", "s2", "s3"],
            otherPlaylistSongLists: []
        )
        #expect(Set(orphaned) == ["s1", "s2", "s3"])
    }

    @Test func removalPreservesSongsSharedWithOtherPlaylist() {
        let orphaned = DownloadManager.orphanedSongIds(
            forRemovedPlaylistSongs: ["s1", "s2", "s3"],
            otherPlaylistSongLists: [["s2"]]
        )
        #expect(Set(orphaned) == ["s1", "s3"])
    }

    @Test func removalPreservesSongsAcrossMultipleOtherPlaylists() {
        let orphaned = DownloadManager.orphanedSongIds(
            forRemovedPlaylistSongs: ["s1", "s2", "s3", "s4"],
            otherPlaylistSongLists: [["s1", "s2"], ["s3"]]
        )
        #expect(Set(orphaned) == ["s4"])
    }

    @Test func removalReturnsEmptyWhenAllSongsShared() {
        let orphaned = DownloadManager.orphanedSongIds(
            forRemovedPlaylistSongs: ["s1", "s2"],
            otherPlaylistSongLists: [["s1", "s2", "s3"]]
        )
        #expect(orphaned.isEmpty)
    }

    @Test func removalHandlesEmptyRemovedList() {
        let orphaned = DownloadManager.orphanedSongIds(
            forRemovedPlaylistSongs: [],
            otherPlaylistSongLists: [["s1"]]
        )
        #expect(orphaned.isEmpty)
    }

    // MARK: - Refresh

    @Test func refreshOrphansSongsDroppedFromNewContent() {
        // Playlist used to contain s1, s2, s3; rotated to s4, s5
        let orphaned = DownloadManager.orphanedSongIds(
            forRefreshOldSongs: ["s1", "s2", "s3"],
            newSongs: ["s4", "s5"],
            otherPlaylistSongLists: []
        )
        #expect(Set(orphaned) == ["s1", "s2", "s3"])
    }

    @Test func refreshKeepsSongsStillInNewContent() {
        // Playlist contained s1, s2, s3; refreshed to s2, s3, s4 (s2/s3 retained)
        let orphaned = DownloadManager.orphanedSongIds(
            forRefreshOldSongs: ["s1", "s2", "s3"],
            newSongs: ["s2", "s3", "s4"],
            otherPlaylistSongLists: []
        )
        #expect(Set(orphaned) == ["s1"])
    }

    @Test func refreshKeepsSongsSharedWithOtherPlaylist() {
        // Old: s1, s2, s3; new: s4 (none shared); other playlist still has s1
        let orphaned = DownloadManager.orphanedSongIds(
            forRefreshOldSongs: ["s1", "s2", "s3"],
            newSongs: ["s4"],
            otherPlaylistSongLists: [["s1"]]
        )
        #expect(Set(orphaned) == ["s2", "s3"])
    }

    @Test func refreshReturnsEmptyWhenContentUnchanged() {
        let orphaned = DownloadManager.orphanedSongIds(
            forRefreshOldSongs: ["s1", "s2", "s3"],
            newSongs: ["s1", "s2", "s3"],
            otherPlaylistSongLists: []
        )
        #expect(orphaned.isEmpty)
    }

    @Test func refreshHandlesEmptyOldSongs() {
        // First-time download path: no old snapshot, nothing to orphan
        let orphaned = DownloadManager.orphanedSongIds(
            forRefreshOldSongs: [],
            newSongs: ["s1", "s2"],
            otherPlaylistSongLists: []
        )
        #expect(orphaned.isEmpty)
    }

    @Test func refreshHandlesEmptyNewSongs() {
        // Server returned empty playlist on refresh; everything from old snapshot
        // becomes orphaned (subject to other-playlist sharing)
        let orphaned = DownloadManager.orphanedSongIds(
            forRefreshOldSongs: ["s1", "s2"],
            newSongs: [],
            otherPlaylistSongLists: [["s2"]]
        )
        #expect(Set(orphaned) == ["s1"])
    }
}
