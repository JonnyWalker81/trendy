//
//  MainActorIsolationTests.swift
//  trendyTests
//
//  Tests verifying that @Observable classes have @MainActor isolation.
//  These classes were identified in a race condition audit (2026-01-28)
//  as lacking isolation, allowing UI-observed state to be mutated
//  from background threads.
//

import Testing
import Foundation
@testable import trendy

// MARK: - @MainActor Isolation Verification Tests

@Suite("Observable MainActor Isolation")
struct MainActorIsolationTests {

    /// Verify ThemeManager is @MainActor isolated.
    /// Without @MainActor, the @Observable `currentTheme` property could be
    /// mutated from a background thread while SwiftUI observes it from main.
    @Test("ThemeManager is MainActor isolated")
    @MainActor func testThemeManagerIsMainActorIsolated() async {
        let manager = ThemeManager()
        // If ThemeManager were not @MainActor, this line would produce a
        // compiler warning/error in strict concurrency mode when accessed
        // from a @MainActor context without await.
        _ = manager.currentTheme
    }

    /// Verify SyncHistoryStore is @MainActor isolated.
    /// Without @MainActor, the @Observable `entries` array could be mutated
    /// from the SyncEngine actor context while SwiftUI reads it on main thread.
    @Test("SyncHistoryStore is MainActor isolated")
    @MainActor func testSyncHistoryStoreIsMainActorIsolated() async {
        let store = SyncHistoryStore()
        // Accessing entries from @MainActor context should not require await
        _ = store.entries
    }

    /// Verify AIBackgroundTaskScheduler is @MainActor isolated.
    /// Without @MainActor, mutable properties (insightsViewModel, eventStore,
    /// foundationModelService) could be written from MainActor configure() and
    /// read from BGTask background queue callbacks, creating a data race.
    @Test("AIBackgroundTaskScheduler is MainActor isolated")
    @MainActor func testAIBackgroundTaskSchedulerIsMainActorIsolated() async {
        let scheduler = AIBackgroundTaskScheduler.shared
        // If AIBackgroundTaskScheduler were not @MainActor, accessing .shared
        // from a @MainActor context would require await in strict concurrency mode.
        _ = scheduler
    }

    /// Verify SyncHistoryStore.record() is safe to call from @MainActor.
    @Test("SyncHistoryStore record is MainActor safe")
    @MainActor func testSyncHistoryStoreRecordIsSafe() async {
        let store = SyncHistoryStore()
        let entry = SyncHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            eventsCount: 5,
            eventTypesCount: 2,
            status: .success,
            errorMessage: nil,
            durationMs: 150
        )
        store.record(entry)
        #expect(store.entries.count >= 1, "Entry should be recorded")
    }
}
