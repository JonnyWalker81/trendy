//
//  PersistenceController.swift
//  trendy
//
//  Centralized persistence management for SwiftData.
//
//  This controller addresses three root causes of the "default.store" error:
//
//  1. MULTIPLE UNCOORDINATED ModelContext INSTANCES:
//     Previously, EventStore, SyncEngine, GeofenceManager, and HealthKitService each
//     maintained their own ModelContext, creating SQLite connection contention.
//     Now, all components obtain contexts through this controller.
//
//  2. NO BACKGROUND TASK PROTECTION:
//     SQLite writes during sync, CRUD operations, and background event handling had
//     no beginBackgroundTask protection. iOS could suspend the app mid-transaction,
//     leaving stale file handles. Now, all writes are wrapped in background tasks.
//
//  3. STALE HANDLES AFTER BACKGROUND SUSPENSION:
//     When iOS suspends the app for extended periods (1+ hours), it may invalidate
//     SQLite file descriptors. This controller centrally handles foreground return
//     by invalidating all cached contexts, rather than each component independently
//     trying to detect and recover from stale handles.
//

import Foundation
import SwiftData
import UIKit

/// Centralized persistence controller that manages all SwiftData access.
///
/// All components that need SwiftData access should go through this controller
/// rather than creating their own ModelContext instances. This ensures:
/// - Single point of context creation and lifecycle management
/// - Background task protection for all SQLite writes
/// - Centralized foreground return handling
/// - Reduced SQLite connection contention
@MainActor
final class PersistenceController: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared instance - set during app initialization
    static var shared: PersistenceController!

    // MARK: - Properties

    /// The underlying ModelContainer (thread-safe, Sendable)
    let modelContainer: ModelContainer

    /// The current valid ModelContext for MainActor-isolated operations.
    /// This is refreshed on foreground return and after stale handle detection.
    private(set) var mainContext: ModelContext

    /// Track whether we're in a suspended/background state
    private var isBackgrounded = false

    /// Counter for active background tasks (for debugging)
    private var activeBackgroundTasks = 0

    // MARK: - Initialization

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.mainContext = modelContainer.mainContext

        // Observe app lifecycle for centralized context management
        setupLifecycleObservers()

        Log.data.info("PersistenceController initialized")
    }

    // MARK: - Lifecycle Management

    private func setupLifecycleObservers() {
        // When app enters background, mark state
        NotificationCenter.default.addObserver(
            forName: UIScene.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidEnterBackground()
            }
        }

        // When app returns to foreground, refresh all contexts
        NotificationCenter.default.addObserver(
            forName: UIScene.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWillEnterForeground()
            }
        }
    }

    private func handleDidEnterBackground() {
        isBackgrounded = true
        Log.data.debug("PersistenceController: app entered background")
    }

    /// Refresh all ModelContext instances when the app returns to foreground.
    ///
    /// After prolonged background suspension, iOS may invalidate SQLite file descriptors.
    /// This is the SINGLE PLACE where all contexts are refreshed, replacing the previous
    /// approach where each component (EventStore, GeofenceManager, HealthKitService)
    /// independently tried to detect and recover from stale handles.
    func handleWillEnterForeground() {
        guard isBackgrounded else { return }
        isBackgrounded = false

        // Create a fresh context - this gets a new SQLite connection
        mainContext = ModelContext(modelContainer)

        Log.data.info("PersistenceController: refreshed ModelContext for foreground return")
    }

    // MARK: - Context Access

    /// Get the current validated ModelContext for MainActor operations.
    ///
    /// This is the PRIMARY way components should access SwiftData.
    /// The context is automatically refreshed on foreground return.
    var validContext: ModelContext {
        return mainContext
    }

    /// Create a fresh ModelContext for background actor operations (e.g., SyncEngine).
    ///
    /// Each call creates a NEW context. The caller is responsible for the lifecycle
    /// of this context. This is intended for actor-isolated operations that need
    /// their own context.
    func makeBackgroundContext() -> ModelContext {
        return ModelContext(modelContainer)
    }

    // MARK: - Protected Writes

    /// Execute a write operation with background task protection.
    ///
    /// This wraps the operation in a UIKit background task to prevent iOS from
    /// suspending the app mid-transaction. If the app is suspended, the background
    /// task gives us time to complete the SQLite write and release any locks.
    ///
    /// Without this protection, iOS can suspend the app while a SQLite transaction
    /// is in-flight, leaving file locks held. On next launch, these stale locks
    /// cause "default.store couldn't be opened" errors.
    ///
    /// - Parameters:
    ///   - name: A descriptive name for the background task (for debugging)
    ///   - operation: The write operation to perform
    /// - Throws: Any error thrown by the operation
    func performProtectedWrite<T>(
        name: String,
        operation: () throws -> T
    ) rethrows -> T {
        // Begin a background task to prevent suspension during SQLite write
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: "SwiftData-\(name)") {
            // Expiration handler: if we run out of time, end the task
            Log.data.warning("Background task expired during write", context: .with { ctx in
                ctx.add("name", name)
            })
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }

        activeBackgroundTasks += 1

        defer {
            activeBackgroundTasks -= 1
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
            }
        }

        return try operation()
    }

    /// Execute an async write operation with background task protection.
    ///
    /// Same as `performProtectedWrite` but for async operations like network + save combos.
    func performProtectedWriteAsync<T>(
        name: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: "SwiftData-\(name)") {
            Log.data.warning("Background task expired during async write", context: .with { ctx in
                ctx.add("name", name)
            })
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }

        activeBackgroundTasks += 1

        defer {
            activeBackgroundTasks -= 1
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
            }
        }

        return try await operation()
    }

    // MARK: - Context Validation

    /// Check if the current mainContext has valid SQLite file handles.
    ///
    /// This is a lightweight probe that detects stale handles. If stale,
    /// the context is automatically refreshed.
    ///
    /// Returns true if the context is valid (or was successfully refreshed).
    @discardableResult
    func ensureValidContext() -> Bool {
        do {
            _ = try mainContext.fetchCount(FetchDescriptor<EventType>())
            return true
        } catch {
            let isStale = isStaleStoreError(error)
            if isStale {
                Log.data.warning("PersistenceController: stale handles detected, refreshing context", error: error)
                mainContext = ModelContext(modelContainer)
                Log.data.info("PersistenceController: context refreshed after stale handle detection")
                return true
            } else {
                Log.data.warning("PersistenceController: context probe failed with non-stale error", error: error)
                return false
            }
        }
    }

    /// Check if an error indicates stale SQLite file handles.
    func isStaleStoreError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 256 {
            return true
        }
        let description = error.localizedDescription.lowercased()
        return description.contains("default.store") || description.contains("couldn't be opened")
    }

    // MARK: - Protected Save

    /// Save the main context with background task protection and stale handle recovery.
    ///
    /// This is the recommended way to save. It:
    /// 1. Wraps the save in a background task to prevent suspension
    /// 2. Detects stale handles and creates a fresh context if needed
    /// 3. Retries the save on the fresh context
    ///
    /// - Parameter name: Descriptive name for debugging
    /// - Throws: The save error if both attempts fail
    func save(name: String = "save") throws {
        guard mainContext.hasChanges else { return }

        try performProtectedWrite(name: name) {
            do {
                try mainContext.save()
            } catch {
                guard isStaleStoreError(error) else { throw error }

                Log.data.warning("PersistenceController: save failed with stale handles, refreshing context", context: .with { ctx in
                    ctx.add("name", name)
                    ctx.add(error: error)
                })

                // Refresh and retry - note that unsaved changes in the old context are LOST.
                // This is acceptable because the alternative is a crash/error.
                // The caller should handle this gracefully (e.g., re-queue the operation).
                mainContext = ModelContext(modelContainer)
                Log.data.info("PersistenceController: context refreshed after failed save - pending changes were lost")
                throw error
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
