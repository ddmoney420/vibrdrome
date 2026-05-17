import Foundation
import SwiftData

enum PlaylistExportSyncMode: String, CaseIterable {
    case addOnly
    case addAndRemove

    var displayName: String {
        switch self {
        case .addOnly: "Add Only"
        case .addAndRemove: "Add & Remove"
        }
    }
}

@Model
final class ExportedPlaylist {
    @Attribute(.unique) var compositeKey: String = ""
    var serverId: String = ""
    var playlistId: String = ""
    var playlistName: String = ""
    var folderBookmarkData: Data?
    var syncModeRaw: String = PlaylistExportSyncMode.addOnly.rawValue
    var transcodeFormat: String?
    var transcodeBitrate: Int?
    var appliedTranscodeFormat: String?
    var lastSyncedAt: Date?
    var knownSongIds: [String] = []
    var knownSongPathsData: Data = Data()
    var isActive: Bool = true
    var lastSyncError: String?
    var failedSongIds: [String] = []
    var failedSongTitles: [String] = []

    var syncModeEnum: PlaylistExportSyncMode {
        get { PlaylistExportSyncMode(rawValue: syncModeRaw) ?? .addOnly }
        set { syncModeRaw = newValue.rawValue }
    }

    var knownSongPaths: [String: String] {
        get { (try? JSONDecoder().decode([String: String].self, from: knownSongPathsData)) ?? [:] }
        set { knownSongPathsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var needsResync: Bool {
        transcodeFormat != appliedTranscodeFormat
    }

    init(serverId: String, playlistId: String, playlistName: String,
         folderBookmarkData: Data?, syncMode: PlaylistExportSyncMode,
         transcodeFormat: String?, transcodeBitrate: Int?, isActive: Bool) {
        self.compositeKey = "\(serverId)_\(playlistId)"
        self.serverId = serverId
        self.playlistId = playlistId
        self.playlistName = playlistName
        self.folderBookmarkData = folderBookmarkData
        self.syncModeRaw = syncMode.rawValue
        self.transcodeFormat = transcodeFormat
        self.transcodeBitrate = transcodeBitrate
        self.isActive = isActive
    }
}
