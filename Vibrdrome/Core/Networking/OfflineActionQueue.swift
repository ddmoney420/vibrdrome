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

    /// Set rating on a song or album — queues offline if no network
    func setRating(id: String, rating: Int) async throws {
        let client = AppState.shared.subsonicClient
        if isConnected {
            do {
                try await client.setRating(id: id, rating: rating)
                return
            } catch {
                offlineLog.info("setRating failed, queuing for offline sync")
            }
        }
        let serverId = AppState.shared.activeServerId ?? ""
        let action = PendingAction(serverId: serverId, actionType: "setRating", targetId: id)
        action.ratingValue = rating
        let context = PersistenceController.shared.container.mainContext
        context.insert(action)
        do {
            try context.save()
            refreshCounts()
            offlineLog.info("Queued setRating(\(rating)) for \(id)")
        } catch {
            offlineLog.error("Failed to save pending setRating: \(error)")
        }
    }

    /// Queue a ListenBrainz scrobble — submits immediately if online, queues if offline
    func listenBrainzScrobble(song: Song) async {
        if isConnected {
            await ListenBrainzClient.shared.submitListen(song: song)
            return
        }
        enqueueExternalScrobble(actionType: "listenBrainzScrobble", song: song)
    }

    /// Queue a Last.fm scrobble — submits immediately if online, queues if offline
    func lastFmScrobble(song: Song) async {
        if isConnected {
            await LastFmClient.shared.scrobble(song: song)
            return
        }
        enqueueExternalScrobble(actionType: "lastFmScrobble", song: song)
    }

    private func enqueueExternalScrobble(actionType: String, song: Song) {
        let serverId = AppState.shared.activeServerId ?? ""
        let action = PendingAction(
            serverId: serverId,
            actionType: actionType,
            targetId: song.id
        )
        action.songTitle = song.title
        action.songArtist = song.artist
        action.songAlbum = song.album
        action.songAlbumArtist = song.albumArtist
        action.songDuration = song.duration
        let context = PersistenceController.shared.container.mainContext
        context.insert(action)
        do {
            try context.save()
            refreshCounts()
            offlineLog.info("Queued \(actionType) for \(song.title)")
        } catch {
            offlineLog.error("Failed to save pending \(actionType): \(error)")
        }
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

    /// Sync all pending actions to server, with conflict detection and resolution.
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

        // Conflict resolution: collapse contradictory actions on the same target.
        // e.g., star + unstar on the same song → last one wins.
        let resolved = resolveConflicts(actions: actions, context: context)

        var synced = 0

        for action in resolved {
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

    // MARK: - Conflict Resolution

    /// Collapse contradictory actions on the same target.
    /// Uses last-write-wins: the most recent action for each target survives.
    private func resolveConflicts(actions: [PendingAction],
                                  context: ModelContext) -> [PendingAction] {
        // Group by target ID
        var grouped: [String: [PendingAction]] = [:]
        for action in actions {
            grouped[action.targetId, default: []].append(action)
        }

        var resolved: [PendingAction] = []

        for (_, group) in grouped {
            // Separate star/unstar pairs from other action types
            let starActions = group.filter {
                $0.actionType == "star" || $0.actionType == "unstar" ||
                $0.actionType == "starAlbum" || $0.actionType == "unstarAlbum" ||
                $0.actionType == "starArtist" || $0.actionType == "unstarArtist"
            }
            let otherActions = group.filter {
                !($0.actionType == "star" || $0.actionType == "unstar" ||
                  $0.actionType == "starAlbum" || $0.actionType == "unstarAlbum" ||
                  $0.actionType == "starArtist" || $0.actionType == "unstarArtist")
            }

            // Other actions (scrobbles etc.) always go through
            resolved.append(contentsOf: otherActions)

            // For star/unstar, check for contradictions
            if starActions.count > 1 {
                // Multiple star/unstar on same target — keep only the latest
                let sorted = starActions.sorted { $0.createdAt < $1.createdAt }
                let winner = sorted.last!
                offlineLog.info("Conflict resolved (last-write-wins): \(winner.actionType) wins for \(winner.targetId)")

                // Delete the losers
                for action in sorted.dropLast() {
                    context.delete(action)
                }
                resolved.append(winner)
            } else {
                resolved.append(contentsOf: starActions)
            }
        }

        return resolved
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
        case "setRating":
            try await client.setRating(id: action.targetId, rating: action.ratingValue)
        case "scrobble":
            try await client.scrobble(id: action.targetId, submission: action.submission)
        case "listenBrainzScrobble":
            let song = songFromAction(action)
            await ListenBrainzClient.shared.submitListen(song: song, listenedAt: action.createdAt)
        case "lastFmScrobble":
            let song = songFromAction(action)
            await LastFmClient.shared.scrobble(song: song, timestamp: action.createdAt)
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

    /// Reconstruct a minimal Song from queued PendingAction metadata
    private func songFromAction(_ action: PendingAction) -> Song {
        Song(
            id: action.targetId,
            title: action.songTitle ?? "Unknown",
            album: action.songAlbum,
            artist: action.songArtist,
            albumArtist: action.songAlbumArtist,
            duration: action.songDuration
        )
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
