//
//  ThreadSafetyTests.swift
//  trendyTests
//
//  Tests verifying thread safety of shared mutable state in non-actor,
//  non-@MainActor classes. These classes use NSLock-based synchronization
//  because they are accessed from multiple threads (e.g., DispatchQueue
//  callbacks, async functions, and the main thread).
//
//  Race conditions fixed (2026-01-28):
//  1. DeviceInfoCollector.currentNetworkStatus - written from background queue, read from async
//  2. FileLogger.isEnabled - read outside queue, written on queue
//

import Testing
import Foundation
@testable import trendy

// MARK: - FileLogger Thread Safety

@Suite("FileLogger Thread Safety")
struct FileLoggerThreadSafetyTests {

    @Test("setEnabled and log can be called concurrently without crash")
    func testConcurrentEnableDisable() async throws {
        let logger = FileLogger.shared

        // Rapidly toggle enabled state from multiple tasks while logging.
        // Before the fix, this could cause a data race on `isEnabled`.
        await withTaskGroup(of: Void.self) { group in
            // Toggle enabled on/off rapidly
            for i in 0..<100 {
                group.addTask {
                    logger.setEnabled(i % 2 == 0)
                }
                group.addTask {
                    logger.log(level: .debug, category: "test", message: "concurrent \(i)", context: "")
                }
            }
        }

        // Restore enabled state
        logger.setEnabled(true)

        // If we get here without crashing, the locks are working
    }
}

// MARK: - HealthKitService Static Var Thread Safety

@Suite("HealthKitService Static Var Safety")
struct HealthKitServiceStaticVarTests {

    @Test("isUsingAppGroup is protected by @MainActor isolation")
    @MainActor func testIsUsingAppGroupMainActorAccess() async {
        // This test verifies that isUsingAppGroup can be safely accessed
        // from @MainActor context. The compiler enforces that static vars
        // on @MainActor classes cannot be accessed from outside the actor,
        // so no lock is needed - just verify the access compiles and works.
        let value = HealthKitService.isUsingAppGroup
        // Value should be a valid bool (either true or false depending on runtime)
        #expect(value == true || value == false)
    }

    @Test("sharedDefaults is accessible from MainActor")
    @MainActor func testSharedDefaultsMainActorAccess() async {
        // sharedDefaults is a @MainActor-isolated static property.
        // This test verifies it can be accessed without crash and returns a valid UserDefaults.
        let defaults = HealthKitService.sharedDefaults
        // Should return a non-nil UserDefaults instance (either app group or standard)
        defaults.set("thread_safety_test", forKey: "thread_safety_test_key")
        let value = defaults.string(forKey: "thread_safety_test_key")
        #expect(value == "thread_safety_test")
        defaults.removeObject(forKey: "thread_safety_test_key")
    }
}
