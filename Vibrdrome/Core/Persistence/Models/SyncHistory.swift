import Foundation
import SwiftData

@Model
final class SyncHistory {
    var syncDate: Date = Date()
    /// "full", "incremental", "background"
    var syncType: String = "full"
    var durationSeconds: Double = 0
    var albumsAdded: Int = 0
    var albumsUpdated: Int = 0
    var albumsRemoved: Int = 0
    var artistsAdded: Int = 0
    var artistsUpdated: Int = 0
    var artistsRemoved: Int = 0
    var songsAdded: Int = 0
    var songsUpdated: Int = 0
    var songsRemoved: Int = 0
    var playlistsSynced: Int = 0
    var conflictsDetected: Int = 0
    var conflictsResolved: Int = 0
    var errorMessage: String?
    var succeeded: Bool = true

    init(syncType: String) {
        self.syncType = syncType
        self.syncDate = Date()
    }

    var totalChanges: Int {
        albumsAdded + albumsUpdated + albumsRemoved +
        artistsAdded + artistsUpdated + artistsRemoved +
        songsAdded + songsUpdated + songsRemoved
    }

    var summary: String {
        if !succeeded, let error = errorMessage {
            return "Failed: \(error)"
        }
        if totalChanges == 0 {
            return "No changes"
        }
        var parts: [String] = []
        let added = albumsAdded + artistsAdded + songsAdded
        let updated = albumsUpdated + artistsUpdated + songsUpdated
        let removed = albumsRemoved + artistsRemoved + songsRemoved
        if added > 0 { parts.append("+\(added)") }
        if updated > 0 { parts.append("~\(updated)") }
        if removed > 0 { parts.append("-\(removed)") }
        return parts.joined(separator: " ")
    }
}
