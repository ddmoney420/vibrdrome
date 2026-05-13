#if os(iOS)
import BackgroundTasks
import Foundation
import os.log

private let bgSyncLog = Logger(subsystem: "com.vibrdrome.app", category: "BackgroundSync")

/// Manages background library sync via BGTaskScheduler on iOS.
/// Registers and schedules both app refresh and processing tasks.
@MainActor
final class BackgroundSyncScheduler {
    static let shared = BackgroundSyncScheduler()

    /// Task identifier for lightweight app refresh (incremental sync).
    /// `nonisolated` so `registerTasks()` (itself nonisolated, called from App.init())
    /// can read these without hopping to the main actor.
    nonisolated static let refreshTaskId = "com.vibrdrome.app.libraryRefresh"
    /// Task identifier for longer processing task (full sync).
    nonisolated static let processingTaskId = "com.vibrdrome.app.librarySync"

    private init() {}

    /// Register background task handlers. MUST be called synchronously from `App.init()`
    /// before the app finishes launching. If iOS launches the app specifically to handle
    /// a background task, registration must already be in place or the handler is missing
    /// and the task fails silently.
    ///
    /// `nonisolated` so it can run on whatever thread initializes the SwiftUI `App` struct
    /// without an `await` hop; `BGTaskScheduler.register` is thread-safe.
    nonisolated func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskId,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            // BGTask subclasses are not Sendable; transferring them into a MainActor Task
            // is safe here because the system invokes the handler exactly once and we do
            // not touch the task from any other isolation domain.
            nonisolated(unsafe) let unsafeTask = refreshTask
            Task { @MainActor in
                await self.handleRefreshTask(unsafeTask)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingTaskId,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            nonisolated(unsafe) let unsafeTask = processingTask
            Task { @MainActor in
                await self.handleProcessingTask(unsafeTask)
            }
        }

        bgSyncLog.info("Registered background sync tasks")
    }

    /// Schedule the next background refresh. Call after each sync completes.
    func scheduleRefresh() {
        guard AppState.shared.isConfigured else { return }
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.backgroundSyncEnabled) else {
            bgSyncLog.info("Background sync disabled, not scheduling refresh")
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        // Earliest: 1 hour from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)

        do {
            try BGTaskScheduler.shared.submit(request)
            bgSyncLog.info("Scheduled background refresh for ~1 hour from now")
        } catch {
            bgSyncLog.error("Failed to schedule background refresh: \(error)")
        }
    }

    /// Schedule a longer background processing task for full sync.
    func scheduleFullSync() {
        guard AppState.shared.isConfigured else { return }
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.backgroundSyncEnabled) else { return }

        let request = BGProcessingTaskRequest(identifier: Self.processingTaskId)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // Earliest: 24 hours from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 86400)

        do {
            try BGTaskScheduler.shared.submit(request)
            bgSyncLog.info("Scheduled background full sync for ~24 hours from now")
        } catch {
            bgSyncLog.error("Failed to schedule background full sync: \(error)")
        }
    }

    /// Cancel all pending background sync tasks.
    func cancelAll() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskId)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.processingTaskId)
        bgSyncLog.info("Cancelled all background sync tasks")
    }

    // MARK: - Task Handlers

    private func handleRefreshTask(_ task: BGAppRefreshTask) async {
        bgSyncLog.info("Background refresh task started")

        // Schedule the next refresh before doing work
        scheduleRefresh()

        let appState = AppState.shared
        guard appState.isConfigured else {
            bgSyncLog.info("App not configured, completing background refresh")
            task.setTaskCompleted(success: true)
            return
        }

        // Create a cancellation handler
        let syncTask = Task {
            await appState.librarySyncManager.incrementalSync(
                client: appState.subsonicClient,
                ndClient: appState.navidromeClient,
                container: PersistenceController.shared.container
            )
        }

        task.expirationHandler = {
            syncTask.cancel()
            bgSyncLog.warning("Background refresh task expired")
        }

        await syncTask.value
        task.setTaskCompleted(success: appState.librarySyncManager.syncError == nil)
        bgSyncLog.info("Background refresh task completed")
    }

    private func handleProcessingTask(_ task: BGProcessingTask) async {
        bgSyncLog.info("Background processing task started")

        // Schedule the next full sync
        scheduleFullSync()

        let appState = AppState.shared
        guard appState.isConfigured else {
            task.setTaskCompleted(success: true)
            return
        }

        let syncTask = Task {
            await appState.librarySyncManager.sync(
                client: appState.subsonicClient,
                ndClient: appState.navidromeClient,
                container: PersistenceController.shared.container
            )
        }

        task.expirationHandler = {
            syncTask.cancel()
            bgSyncLog.warning("Background processing task expired")
        }

        await syncTask.value
        task.setTaskCompleted(success: appState.librarySyncManager.syncError == nil)
        bgSyncLog.info("Background processing task completed")
    }
}
#endif
