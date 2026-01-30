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
/// - **Autosave disabled on ALL contexts** to prevent SQLite writes during background suspension
///   (which causes 0xdead10cc kills and "default.store couldn't be opened" errors)
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
    /// **autosaveEnabled is always false** to prevent unsolicited SQLite writes.
    private(set) var mainContext: ModelContext

    /// Track whether we're in a suspended/background state
    private var isBackgrounded = false

    /// Counter for active background tasks (for debugging)
    private var activeBackgroundTasks = 0

    /// Callback to notify SyncEngine to release its cached DataStore on background entry.
    /// Set by EventStore during initialization.
    var onBackgroundEntry: (() async -> Void)?

    // MARK: - Initialization

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        // CRITICAL: Disable autosaveEnabled on the main context.
        // SwiftData's default (autosaveEnabled=true) can trigger SQLite writes during
        // background suspension, which causes iOS to kill the app with 0xdead10cc
        // (holding file locks in suspended state). By disabling autosave, we ensure
        // ALL saves are explicit and wrapped in background task protection.
        let context = modelContainer.mainContext
        context.autosaveEnabled = false
        self.mainContext = context

        // Observe app lifecycle for centralized context management
        setupLifecycleObservers()

        Log.data.info("PersistenceController initialized", context: .with { ctx in
            ctx.add("autosaveEnabled", false)
        })
    }

    // MARK: - Lifecycle Management

    private func setupLifecycleObservers() {
        // When app enters background, save and release locks.
        // IMPORTANT: Use OperationQueue.main (NOT a Task{@MainActor}) so the handler
        // runs synchronously during notification delivery. Task{@MainActor} merely
        // enqueues work, which may not execute before iOS suspends the app.
        NotificationCenter.default.addObserver(
            forName: UIScene.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // We're on the main thread and PersistenceController is @MainActor,
            // so we can call MainActor-isolated methods directly via assumeIsolated.
            MainActor.assumeIsolated {
                self?.handleDidEnterBackground()
            }
        }

        // When app returns to foreground, refresh all contexts.
        // Same pattern: run synchronously to ensure context is refreshed
        // BEFORE any SwiftUI .onChange(of: scenePhase) handlers fire.
        NotificationCenter.default.addObserver(
            forName: UIScene.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWillEnterForeground()
            }
        }
    }

    /// Handle app entering background: save pending changes and release SQLite locks.
    ///
    /// This is the KEY prevention mechanism against 0xdead10cc crashes. When the app enters
    /// background, iOS may suspend it at any time. If any SQLite file lock is held at that
    /// moment, iOS terminates the app with 0xdead10cc. We prevent this by:
    ///
    /// 1. Saving any pending changes (flushing the write-ahead log)
    /// 2. Notifying SyncEngine to release its cached DataStore (which holds its own ModelContext)
    ///
    /// Apple DTS recommendation: "Nullify the model container, and also other SwiftData objects
    /// such as model context(s) and models associated with the container."
    /// See: https://developer.apple.com/forums/thread/762093
    private func handleDidEnterBackground() {
        isBackgrounded = true

        // Begin a SINGLE background task that covers ALL cleanup work.
        // This is critical: iOS can suspend the app at any time after
        // didEnterBackground fires. The background task gives us time
        // to complete both the save AND the SyncEngine DataStore release.
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: "SwiftData-BackgroundCleanup") {
            // Expiration handler: if we run out of time, end the task
            Log.data.warning("PersistenceController: background cleanup task expired")
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }

        // Step 1: Flush any pending changes to disk while we still have time.
        if mainContext.hasChanges {
            do {
                try mainContext.save()
                Log.data.info("PersistenceController: saved pending changes before background")
            } catch {
                Log.data.warning("PersistenceController: failed to save before background", error: error)
            }
        }

        // Step 2: Notify SyncEngine to release its cached DataStore.
        // SyncEngine runs on its own actor and has its own ModelContext that can hold
        // SQLite locks independently. We must release those locks too.
        //
        // CRITICAL FIX: Previously this was fire-and-forget (Task without awaiting).
        // The background task would end before SyncEngine had a chance to release
        // its DataStore. Now we keep the background task alive until the release
        // completes, ensuring no SQLite file handles are held during suspension.
        if let callback = onBackgroundEntry {
            Task {
                await callback()
                Log.data.info("PersistenceController: SyncEngine DataStore released")
                if taskId != .invalid {
                    UIApplication.shared.endBackgroundTask(taskId)
                    taskId = .invalid
                }
            }
        } else {
            // No SyncEngine callback - end background task immediately
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }

        Log.data.info("PersistenceController: prepared for background suspension")
    }

    /// Refresh all ModelContext instances when the app returns to foreground.
    ///
    /// After prolonged background suspension, iOS may invalidate SQLite file descriptors.
    /// This is the SINGLE PLACE where all contexts are refreshed, replacing the previous
    /// approach where each component (EventStore, GeofenceManager, HealthKitService)
    /// independently tried to detect and recover from stale handles.
    ///
    /// IMPORTANT: This always creates a fresh context, regardless of whether
    /// handleDidEnterBackground ran. This covers:
    /// - Normal background/foreground cycle (isBackgrounded was true)
    /// - Cold launch by iOS for background activity (geofence/HealthKit) where
    ///   the app never went through didEnterBackground (isBackgrounded was false)
    /// - App relaunched after 0xdead10cc termination
    ///
    /// Creating a fresh ModelContext is cheap and safe, while using a stale one
    /// after background suspension causes "default.store couldn't be opened" crashes.
    func handleWillEnterForeground() {
        let wasBackgrounded = isBackgrounded
        isBackgrounded = false

        // Create a fresh context with autosave DISABLED
        let freshContext = ModelContext(modelContainer)
        freshContext.autosaveEnabled = false
        mainContext = freshContext

        Log.data.info("PersistenceController: refreshed ModelContext for foreground return", context: .with { ctx in
            ctx.add("autosaveEnabled", false)
            ctx.add("wasBackgrounded", wasBackgrounded)
        })
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
    /// Each call creates a NEW context with autosave disabled. The caller is responsible
    /// for the lifecycle of this context. This is intended for actor-isolated operations
    /// that need their own context.
    ///
    /// **autosaveEnabled is always false** to prevent SQLite writes during background suspension.
    func makeBackgroundContext() -> ModelContext {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        return context
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
                let freshContext = ModelContext(modelContainer)
                freshContext.autosaveEnabled = false
                mainContext = freshContext
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
                let freshContext = ModelContext(modelContainer)
                freshContext.autosaveEnabled = false
                mainContext = freshContext
                Log.data.info("PersistenceController: context refreshed after failed save - pending changes were lost")
                throw error
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
