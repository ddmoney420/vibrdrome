import Foundation
import Network
import SwiftData
import os.log

private let offlineLog = Logger(subsystem: "com.vibrdrome.app", category: "OfflineQueue")

@Observable
@MainActor
final class OfflineActionQueue {
    static let shared = OfflineActionQueue()

    var pendingCount: Int = 0
    var failedCount: Int = 0

    private let networkMonitor = NWPathMonitor()
    private var isConnected = true
    private var isSyncing = false

    private init() {
        startMonitor()
        refreshCounts()
    }

    private func startMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied
                if !wasConnected && self.isConnected {
                    offlineLog.info("Network restored, flushing pending actions")
                    await self.flushPending()
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "com.vibrdrome.offlinequeue"))
    }

    // MARK: - Queue Actions

    /// Star a song, album, or artist — queues offline if no network
    func star(id: String? = nil, albumId: String? = nil, artistId: String? = nil) async throws {
        let client = AppState.shared.subsonicClient
        if isConnected {
            do {
                try await client.star(id: id, albumId: albumId, artistId: artistId)
                return
            } catch {
                // Network failed mid-request — queue it
                offlineLog.info("Star failed, queuing for offline sync")
            }
        }
        let targetId = id ?? albumId ?? artistId ?? ""
        let actionType = id != nil ? "star" : albumId != nil ? "starAlbum" : "starArtist"
        enqueue(actionType: actionType, targetId: targetId)
    }

    /// Unstar a song, album, or artist — queues offline if no network
    func unstar(id: String? = nil, albumId: String? = nil, artistId: String? = nil) async throws {
        let client = AppState.shared.subsonicClient
        if isConnected {
            do {
                try await client.unstar(id: id, albumId: albumId, artistId: artistId)
                return
            } catch {
                offlineLog.info("Unstar failed, queuing for offline sync")
            }
        }
        let targetId = id ?? albumId ?? artistId ?? ""
        let actionType = id != nil ? "unstar" : albumId != nil ? "unstarAlbum" : "unstarArtist"
        enqueue(actionType: actionType, targetId: targetId)
    }

    /// Scrobble a song — queues offline if no network
    func scrobble(id: String, submission: Bool) async throws {
        let client = AppState.shared.subsonicClient
        if isConnected {
            do {
                try await client.scrobble(id: id, submission: submission)
                return
            } catch {
                offlineLog.info("Scrobble failed, queuing for offline sync")
            }
        }
        enqueue(actionType: "scrobble", targetId: id, submission: submission)
    }

    // MARK: - Enqueue

    private func enqueue(actionType: String, targetId: String, submission: Bool = true) {
        let serverId = AppState.shared.activeServerId ?? ""
        let action = PendingAction(
            serverId: serverId,
            actionType: actionType,
            targetId: targetId,
            submission: submission
        )
        let context = PersistenceController.shared.container.mainContext
        context.insert(action)
        do {
            try context.save()
            refreshCounts()
            offlineLog.info("Queued \(actionType) for \(targetId)")
        } catch {
            offlineLog.error("Failed to save pending action: \(error)")
        }
    }

    // MARK: - Flush

    /// Sync all pending actions to server
    func flushPending() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<PendingAction>(
            predicate: #Predicate { $0.status == "pending" },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let actions = try? context.fetch(descriptor), !actions.isEmpty else { return }
        let client = AppState.shared.subsonicClient
        var synced = 0

        for action in actions {
            do {
                try await executeAction(action, client: client)
                context.delete(action)
                synced += 1
            } catch {
                action.retryCount += 1
                if action.retryCount >= 3 {
                    action.status = "failed"
                    offlineLog.warning("Action \(action.actionType) for \(action.targetId) failed after 3 retries")
                }
            }
        }

        do {
            try context.save()
        } catch {
            offlineLog.error("Failed to save after flushing: \(error)")
        }

        refreshCounts()
        if synced > 0 {
            offlineLog.info("Synced \(synced) pending actions")
        }
    }

    private func executeAction(_ action: PendingAction, client: SubsonicClient) async throws {
        switch action.actionType {
        case "star":
            try await client.star(id: action.targetId)
        case "unstar":
            try await client.unstar(id: action.targetId)
        case "starAlbum":
            try await client.star(albumId: action.targetId)
        case "unstarAlbum":
            try await client.unstar(albumId: action.targetId)
        case "starArtist":
            try await client.star(artistId: action.targetId)
        case "unstarArtist":
            try await client.unstar(artistId: action.targetId)
        case "scrobble":
            try await client.scrobble(id: action.targetId, submission: action.submission)
        default:
            offlineLog.warning("Unknown action type: \(action.actionType)")
        }
    }

    // MARK: - Retry / Clear Failed

    /// Retry all failed actions
    func retryFailed() async {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<PendingAction>(
            predicate: #Predicate { $0.status == "failed" }
        )
        guard let actions = try? context.fetch(descriptor) else { return }
        for action in actions {
            action.status = "pending"
            action.retryCount = 0
        }
        do {
            try context.save()
            refreshCounts()
        } catch {
            offlineLog.error("Failed to save retry reset: \(error)")
        }
        await flushPending()
    }

    /// Clear all failed actions
    func clearFailed() {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<PendingAction>(
            predicate: #Predicate { $0.status == "failed" }
        )
        guard let actions = try? context.fetch(descriptor) else { return }
        for action in actions {
            context.delete(action)
        }
        do {
            try context.save()
            refreshCounts()
        } catch {
            offlineLog.error("Failed to save after clearing failed: \(error)")
        }
    }

    // MARK: - Counts

    func refreshCounts() {
        let context = PersistenceController.shared.container.mainContext
        let pendingDesc = FetchDescriptor<PendingAction>(
            predicate: #Predicate { $0.status == "pending" }
        )
        let failedDesc = FetchDescriptor<PendingAction>(
            predicate: #Predicate { $0.status == "failed" }
        )
        pendingCount = (try? context.fetchCount(pendingDesc)) ?? 0
        failedCount = (try? context.fetchCount(failedDesc)) ?? 0
    }

    /// Check if a given target has a pending star action
    func hasPendingStar(targetId: String) -> Bool {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<PendingAction>(
            predicate: #Predicate {
                $0.targetId == targetId && $0.actionType == "star" && $0.status == "pending"
            }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}
