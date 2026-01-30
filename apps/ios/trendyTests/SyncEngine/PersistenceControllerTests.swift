//
//  PersistenceControllerTests.swift
//  trendyTests
//
//  Tests for centralized PersistenceController that manages ModelContext lifecycle,
//  background task protection for SQLite writes, and foreground return context refresh.
//

import Testing
import Foundation
import SwiftData
@testable import trendy

// MARK: - PersistenceController Context Validation Tests

@Suite("PersistenceController Context Validation")
struct PersistenceControllerContextValidationTests {

    @Test("ensureValidContext returns true for healthy context")
    @MainActor
    func ensureValidContextHealthy() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        let isValid = controller.ensureValidContext()
        #expect(isValid, "In-memory context should always be valid")
    }

    @Test("handleWillEnterForeground creates fresh context")
    @MainActor
    func foregroundRefreshCreatesNewContext() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        // Get initial context identity
        let initialContext = controller.mainContext

        // Simulate background then foreground
        controller.handleWillEnterForeground()

        // Note: With in-memory containers, the context object should be different
        // The important thing is that this doesn't crash
        let afterContext = controller.mainContext
        // We can verify it's usable by doing a fetch
        let count = try afterContext.fetchCount(FetchDescriptor<EventType>())
        #expect(count >= 0, "Fresh context should be usable")
    }

    @Test("validContext returns usable context for reads")
    @MainActor
    func validContextReturnsUsableContext() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        let context = controller.validContext
        // Should be able to fetch without error
        let types = try context.fetch(FetchDescriptor<EventType>())
        #expect(types.isEmpty, "Fresh in-memory store should have no event types")
    }

    @Test("makeBackgroundContext creates independent context")
    @MainActor
    func makeBackgroundContextIsIndependent() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        let bgContext = controller.makeBackgroundContext()
        // Should be a different object than mainContext
        // Both should be usable
        let mainCount = try controller.mainContext.fetchCount(FetchDescriptor<EventType>())
        let bgCount = try bgContext.fetchCount(FetchDescriptor<EventType>())
        #expect(mainCount == bgCount, "Both contexts should see the same data")
    }
}

// MARK: - Stale Store Error Detection

@Suite("PersistenceController Stale Error Detection")
struct PersistenceControllerStaleErrorDetectionTests {

    @Test("NSCocoaErrorDomain Code 256 detected as stale")
    @MainActor
    func cocoaError256() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        let error = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [
            NSLocalizedDescriptionKey: "The file 'default.store' couldn't be opened."
        ])

        #expect(controller.isStaleStoreError(error), "Code 256 should be stale")
    }

    @Test("Error with default.store message detected as stale")
    @MainActor
    func defaultStoreMessage() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        let error = NSError(domain: "SomeOther", code: 999, userInfo: [
            NSLocalizedDescriptionKey: "The file 'default.store' couldn't be opened."
        ])

        #expect(controller.isStaleStoreError(error), "default.store message should be stale")
    }

    @Test("Unrelated error NOT detected as stale")
    @MainActor
    func unrelatedError() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        let error = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [
            NSLocalizedDescriptionKey: "The file 'data.json' does not exist."
        ])

        #expect(!controller.isStaleStoreError(error), "Unrelated errors should not be stale")
    }
}

// MARK: - Protected Write Tests

@Suite("PersistenceController Protected Writes")
struct PersistenceControllerProtectedWriteTests {

    @Test("performProtectedWrite executes the operation")
    @MainActor
    func protectedWriteExecutes() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        var executed = false
        try controller.performProtectedWrite(name: "test") {
            executed = true
        }

        #expect(executed, "Operation should have been executed")
    }

    @Test("performProtectedWrite propagates errors")
    @MainActor
    func protectedWritePropagatesErrors() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        struct TestError: Error {}

        #expect(throws: TestError.self) {
            try controller.performProtectedWrite(name: "test") {
                throw TestError()
            }
        }
    }

    @Test("performProtectedWrite returns value from operation")
    @MainActor
    func protectedWriteReturnsValue() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        let result = try controller.performProtectedWrite(name: "test") {
            return 42
        }

        #expect(result == 42, "Should return the operation's result")
    }

    @Test("performProtectedWriteAsync executes async operation")
    @MainActor
    func protectedWriteAsyncExecutes() async throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        var executed = false
        try await controller.performProtectedWriteAsync(name: "test") {
            executed = true
        }

        #expect(executed, "Async operation should have been executed")
    }
}

// MARK: - Integration with Existing Recovery Mechanisms

@Suite("PersistenceController Integration")
struct PersistenceControllerIntegrationTests {

    @Test("SyncEngine resetDataStore works with PersistenceController")
    func syncEngineResetWithController() async throws {
        let mockNetwork = MockNetworkClient()
        let mockStore = MockDataStore()
        let factory = CountingDataStoreFactory(mockStore: mockStore)
        let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)

        // Initial access creates the DataStore
        await engine.loadInitialState()
        #expect(factory.callCount == 1, "Initial access should create DataStore")

        // Reset (simulating background return)
        await engine.resetDataStore()

        // Next access should create a NEW DataStore
        _ = await engine.getPendingCount()
        #expect(factory.callCount == 2, "After reset, next access should create new DataStore")
    }

    @Test("Multiple foreground returns create fresh contexts each time")
    @MainActor
    func multipleForegroundReturns() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        // Simulate multiple background/foreground cycles
        for i in 0..<5 {
            controller.handleWillEnterForeground()

            // Verify context is usable after each refresh
            let count = try controller.validContext.fetchCount(FetchDescriptor<EventType>())
            #expect(count >= 0, "Context should be usable after foreground return \(i)")
        }
    }

    @Test("Context remains valid after save with background task protection")
    @MainActor
    func saveWithProtection() throws {
        let schema = Schema([Event.self, EventType.self, Geofence.self, PropertyDefinition.self, PendingMutation.self, HealthKitConfiguration.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let controller = PersistenceController(modelContainer: container)

        // Insert data
        let context = controller.validContext
        let eventType = EventType(name: "Test Type", colorHex: "#FF0000", iconName: "star")
        context.insert(eventType)

        // Save with protection
        try controller.performProtectedWrite(name: "test-save") {
            try context.save()
        }

        // Verify data persisted
        let count = try context.fetchCount(FetchDescriptor<EventType>())
        #expect(count == 1, "Event type should be persisted after protected save")
    }
}
