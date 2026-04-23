import Foundation
import Observation
import os.log

private let downloadProgressLog = Logger(subsystem: "com.vibrdrome.app", category: "DownloadProgress")

@Observable
@MainActor
final class DownloadProgress {
    static let shared = DownloadProgress()

    var progressBySongId: [String: Double] = [:]
    var speedBySongId: [String: Double] = [:]

    func update(songId: String, progress: Double) {
        progressBySongId[songId] = progress
    }

    func update(songId: String, progress: Double, speed: Double) {
        progressBySongId[songId] = progress
        speedBySongId[songId] = speed
    }

    func remove(songId: String)  {
        progressBySongId.removeValue(forKey: songId)
        speedBySongId.removeValue(forKey: songId)
    }

    func removeAsync(songId: String) async {
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
        progressBySongId.removeValue(forKey: songId)
        speedBySongId.removeValue(forKey: songId)
    }

    func progress(for songId: String) -> Double {
        progressBySongId[songId] ?? 0
    }

    func speed(for songId: String) -> Double {
        speedBySongId[songId] ?? 0
    }

    func clear() {
        progressBySongId.removeAll()
        playlistSongIds.removeAll()
        speedBySongId.removeAll()
    }

    // MARK: - Playlist Progress

    /// Maps playlistId → songIds for tracking playlist-level download progress
    var playlistSongIds: [String: [String]] = [:]

    func trackPlaylist(playlistId: String, songIds: [String]) {
        playlistSongIds[playlistId] = songIds
    }

    /// Returns 0.0-1.0 progress for a playlist based on how many songs are fully downloaded
    func playlistProgress(playlistId: String) -> Double {
        guard let songIds = playlistSongIds[playlistId], !songIds.isEmpty else { return 0 }
        let completedCount = songIds.filter { progressBySongId[$0] == nil }.count
        // Songs with no progress entry are either not started or already complete
        // We need to check DownloadedSong isComplete for accurate count
        return Double(completedCount) / Double(songIds.count)
    }
}
