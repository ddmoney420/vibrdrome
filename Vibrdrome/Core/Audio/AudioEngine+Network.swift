import Foundation
import Network
import SwiftData
import os.log

private let networkLog = Logger(subsystem: "com.vibrdrome.app", category: "Audio")

// MARK: - Network & URL Resolution

extension AudioEngine {

    func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnCellular = path.usesInterfaceType(.cellular)
                self?.isNetworkConstrained = path.isConstrained || path.isExpensive
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "com.vibrdrome.network"))
    }

    var adaptiveBitrateEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.adaptiveBitrateEnabled)
    }

    var currentMaxBitRate: Int? {
        let defaults = UserDefaults.standard
        let key = isOnCellular ? UserDefaultsKeys.cellularMaxBitRate : UserDefaultsKeys.wifiMaxBitRate
        let value = defaults.integer(forKey: key)

        if adaptiveBitrateEnabled && isOnCellular && isNetworkConstrained {
            // On constrained cellular, cap at 128 kbps
            let base = value > 0 ? value : 320
            return min(base, 128)
        }

        return value > 0 ? value : nil
    }

    func resolveURL(for song: Song) -> URL {
        let modelContext = PersistenceController.shared.container.mainContext
        let songId = song.id
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
        )
        if let download = try? modelContext.fetch(descriptor).first {
            let fileURL = DownloadManager.absoluteURL(for: download.localFilePath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                CacheManager.shared.touchAccess(songId: songId)
                return fileURL
            }
            modelContext.delete(download)
            do {
                try modelContext.save()
            } catch {
                networkLog.error(
                    "Failed to save after cleaning stale download: \(error)"
                )
            }
        }
    
        return AppState.shared.subsonicClient.streamURL(
            id: song.id, maxBitRate: currentMaxBitRate
        )
    }
    
    static func isSongDownloaded(_ song: Song) -> Bool {
        let modelContext = PersistenceController.shared.container.mainContext
        let songId = song.id
        let descriptor = FetchDescriptor<DownloadedSong>(
            predicate: #Predicate { $0.songId == songId && $0.isComplete == true }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0
    }
}
