//
//  CircuitBreakerTests.swift
//  trendyTests
//
//  Unit tests for SyncEngine circuit breaker behavior.
//  Tests rate limit handling, exponential backoff, and sync blocking.
//
//  Requirements tested:
//  - CB-01: Circuit breaker trips after 3 consecutive rate limit errors
//  - CB-02: Circuit breaker resets after backoff period expires
//  - CB-03: Sync blocked while circuit breaker tripped
//  - CB-04: Exponential backoff timing (30s -> 60s -> 120s -> max 300s)
//  - CB-05: Rate limit counter resets on successful sync
//

import Testing
import Foundation
@testable import trendy

// MARK: - Test Helpers

/// Helper to create fresh test dependencies for each test, with optional initial cursor
private func makeTestDependencies(initialCursor: Int64 = 0) -> (mockNetwork: MockNetworkClient, mockStore: MockDataStore, factory: MockDataStoreFactory, engine: SyncEngine) {
    cleanupSyncEngineUserDefaults()
    // Set cursor BEFORE creating SyncEngine, because SyncEngine reads cursor in init()
    if initialCursor != 0 {
        UserDefaults.standard.set(Int(initialCursor), forKey: "sync_engine_cursor_\(AppEnvironment.current.rawValue)")
    }
    let mockNetwork = MockNetworkClient()
    let mockStore = MockDataStore()
    let factory = MockDataStoreFactory(mockStore: mockStore)
    let engine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)
    return (mockNetwork, mockStore, factory, engine)
}

/// Helper to configure mock for successful health check and skip bootstrap
/// NOTE: Cursor must be set via makeTestDependencies(initialCursor:) since SyncEngine reads it at init time.
private func configureForFlush(mockNetwork: MockNetworkClient, mockStore: MockDataStore) {
    // Health check passes (required before any sync operations)
    mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]

    // Configure empty change feed to skip pullChanges processing
    mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)
}

/// Helper to create and seed a pending event mutation
private func seedEventMutation(mockStore: MockDataStore, eventId: String) {
    let request = APIModelFixture.makeCreateEventRequest(id: eventId, eventTypeId: "type-1")
    let payload = try! JSONEncoder().encode(request)
    _ = mockStore.seedPendingMutation(entityType: .event, entityId: eventId, operation: .create, payload: payload)
}

/// Helper to trip the circuit breaker by causing 3 consecutive rate limit errors.
///
/// Because all seeded mutations fit in a single batch (batch size = 50),
/// each performSync() cycle makes exactly 1 batch call. The circuit breaker
/// threshold check runs at the TOP of the batch loop, so:
///   - Syncs 1-3: batch call -> 429 -> counter increments (1, 2, 3)
///   - Sync 4: loop starts -> counter >= 3 -> tripCircuitBreaker() called
///
/// The mutation stays in the queue after a rate-limit failure, so we only
/// seed once. We need 4 health check responses (one per sync) and 3 batch
/// responses (the 4th sync trips before making a batch call).
private func tripCircuitBreaker(mockNetwork: MockNetworkClient, mockStore: MockDataStore, engine: SyncEngine) async {
    // NOTE: Cursor must already be set to non-zero via makeTestDependencies(initialCursor:)

    // Configure empty change feed
    mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

    // 4 health check responses (one per sync cycle)
    mockNetwork.getEventTypesResponses.append(contentsOf: [
        .success([APIModelFixture.makeAPIEventType()]),
        .success([APIModelFixture.makeAPIEventType()]),
        .success([APIModelFixture.makeAPIEventType()]),
        .success([APIModelFixture.makeAPIEventType()])
    ])

    // 3 rate limit failures (one per sync cycle; 4th sync trips before calling batch)
    mockNetwork.createEventsBatchResponses.append(contentsOf: [
        .failure(APIError.httpError(429)),
        .failure(APIError.httpError(429)),
        .failure(APIError.httpError(429))
    ])

    // Seed 1 mutation - it stays in queue after each rate limit failure
    seedEventMutation(mockStore: mockStore, eventId: "evt-trip-\(UUID().uuidString.prefix(8))")

    // 3 syncs to increment consecutive rate limit counter to 3
    await engine.performSync()
    await engine.performSync()
    await engine.performSync()

    // 4th sync: batch loop detects counter >= threshold, trips circuit breaker
    await engine.performSync()
}

// MARK: - Circuit Breaker - Trip Behavior

@Suite("Circuit Breaker - Trip Behavior")
struct CircuitBreakerTripTests {

    @Test("Circuit breaker trips after 3 consecutive rate limit errors (CB-01)")
    func circuitBreakerTripsAfter3RateLimits() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Trip the circuit breaker
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)

        // Verify circuit breaker is tripped
        let isTripped = await engine.isCircuitBreakerTripped
        #expect(isTripped == true, "Circuit breaker should be tripped after 3 rate limit errors")
    }

    @Test("Circuit breaker does NOT trip after 2 rate limit errors")
    func circuitBreakerDoesNotTripAfter2RateLimits() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        // Seed 1 mutation - it stays in queue after rate limit failures
        seedEventMutation(mockStore: mockStore, eventId: "evt-1")

        // Sync 1: batch call -> 429 -> counter=1
        mockNetwork.getEventTypesResponses.append(.success([APIModelFixture.makeAPIEventType()]))
        mockNetwork.createEventsBatchResponses.append(.failure(APIError.httpError(429)))
        await engine.performSync()

        // Sync 2: batch call -> 429 -> counter=2
        mockNetwork.getEventTypesResponses.append(.success([APIModelFixture.makeAPIEventType()]))
        mockNetwork.createEventsBatchResponses.append(.failure(APIError.httpError(429)))
        await engine.performSync()

        // Sync 3: batch call -> success -> counter resets to 0
        mockNetwork.getEventTypesResponses.append(.success([APIModelFixture.makeAPIEventType()]))
        mockNetwork.createEventsBatchResponses.append(
            .success(APIModelFixture.makeBatchCreateEventsResponse(
                created: [APIModelFixture.makeAPIEvent(id: "evt-1")],
                total: 1,
                success: 1
            ))
        )
        await engine.performSync()

        // Verify circuit breaker is NOT tripped (only 2 consecutive errors before success)
        let isTripped = await engine.isCircuitBreakerTripped
        #expect(isTripped == false, "Circuit breaker should NOT be tripped with only 2 rate limit errors")
    }

    @Test("Circuit breaker trips on exactly 3 consecutive rate limits")
    func circuitBreakerTripsOnExactly3() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Trip the circuit breaker (uses 3 rate limits + 1 detection sync)
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)

        // Verify circuit breaker is tripped
        let isTripped = await engine.isCircuitBreakerTripped
        #expect(isTripped == true, "Circuit breaker should trip after exactly 3 consecutive rate limit errors")

        // Verify backoff remaining is in expected range (25-35s for first trip)
        let backoffRemaining = await engine.circuitBreakerBackoffRemaining
        #expect(backoffRemaining > 25 && backoffRemaining <= 35, "First backoff should be ~30s, got \(backoffRemaining)")
    }
}

// MARK: - Circuit Breaker - Reset Behavior

@Suite("Circuit Breaker - Reset Behavior")
struct CircuitBreakerResetTests {

    @Test("Circuit breaker resets after manual reset call (CB-02)")
    func circuitBreakerResetsAfterManualReset() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Trip the circuit breaker
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)

        // Verify tripped
        var isTripped = await engine.isCircuitBreakerTripped
        #expect(isTripped == true, "Circuit breaker should be tripped initially")

        // Manually reset (simulates user clicking retry or backoff period expiring)
        await engine.resetCircuitBreaker()

        // Verify no longer tripped
        isTripped = await engine.isCircuitBreakerTripped
        #expect(isTripped == false, "Circuit breaker should be reset after manual reset")

        // Verify backoff remaining is 0
        let backoffRemaining = await engine.circuitBreakerBackoffRemaining
        #expect(backoffRemaining == 0, "Backoff remaining should be 0 after reset")
    }

    @Test("Rate limit counter resets on successful sync (CB-05)")
    func rateLimitCounterResetsOnSuccess() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        // Seed 1 mutation - it stays in queue after rate limit failures
        seedEventMutation(mockStore: mockStore, eventId: "evt-1")

        // Sync 1: batch call -> 429 -> counter=1
        mockNetwork.getEventTypesResponses.append(.success([APIModelFixture.makeAPIEventType()]))
        mockNetwork.createEventsBatchResponses.append(.failure(APIError.httpError(429)))
        await engine.performSync()

        // Sync 2: batch call -> 429 -> counter=2
        mockNetwork.getEventTypesResponses.append(.success([APIModelFixture.makeAPIEventType()]))
        mockNetwork.createEventsBatchResponses.append(.failure(APIError.httpError(429)))
        await engine.performSync()

        // Sync 3: batch call -> success -> counter resets to 0
        mockNetwork.getEventTypesResponses.append(.success([APIModelFixture.makeAPIEventType()]))
        mockNetwork.createEventsBatchResponses.append(
            .success(APIModelFixture.makeBatchCreateEventsResponse(
                created: [APIModelFixture.makeAPIEvent(id: "evt-1")],
                total: 1,
                success: 1
            ))
        )
        await engine.performSync()

        // Counter should have reset to 0 after success
        var isTripped = await engine.isCircuitBreakerTripped
        #expect(isTripped == false, "Should not be tripped after success resets counter")

        // Now seed a new mutation for the second round of failures
        seedEventMutation(mockStore: mockStore, eventId: "evt-2")

        // Sync 4: batch call -> 429 -> counter=1
        mockNetwork.getEventTypesResponses.append(.success([APIModelFixture.makeAPIEventType()]))
        mockNetwork.createEventsBatchResponses.append(.failure(APIError.httpError(429)))
        await engine.performSync()

        // Sync 5: batch call -> 429 -> counter=2
        mockNetwork.getEventTypesResponses.append(.success([APIModelFixture.makeAPIEventType()]))
        mockNetwork.createEventsBatchResponses.append(.failure(APIError.httpError(429)))
        await engine.performSync()

        // Sync 6: batch call -> success -> counter resets to 0
        mockNetwork.getEventTypesResponses.append(.success([APIModelFixture.makeAPIEventType()]))
        mockNetwork.createEventsBatchResponses.append(
            .success(APIModelFixture.makeBatchCreateEventsResponse(
                created: [APIModelFixture.makeAPIEvent(id: "evt-2")],
                total: 1,
                success: 1
            ))
        )
        await engine.performSync()

        // If counter didn't reset, we'd have 4 total failures (2+2) and be tripped
        // Since counter reset on success, we only have 2 consecutive failures each time
        isTripped = await engine.isCircuitBreakerTripped
        #expect(isTripped == false, "Counter should have reset on previous success - only 2 consecutive failures now")
    }

    @Test("Circuit breaker backoff time is within expected range after first trip")
    func backoffTimeInExpectedRange() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Trip the circuit breaker
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)

        // Verify backoff is ~30s (25-35s range to account for timing)
        let backoff = await engine.circuitBreakerBackoffRemaining
        #expect(backoff > 25 && backoff <= 35, "First backoff should be ~30s, got \(backoff)")
    }
}

// MARK: - Circuit Breaker - Sync Blocking

@Suite("Circuit Breaker - Sync Blocking")
struct CircuitBreakerSyncBlockingTests {

    @Test("Sync blocked while circuit breaker tripped (CB-03)")
    func syncBlockedWhileTripped() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Trip the circuit breaker
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)

        // Verify tripped
        let isTripped = await engine.isCircuitBreakerTripped
        #expect(isTripped == true)

        // Record call count before attempting another sync
        let callsBefore = mockNetwork.createEventsBatchCalls.count

        // Attempt another sync (should be blocked)
        // Add health check response for the blocked sync attempt
        mockNetwork.getEventTypesResponses.append(.success([APIModelFixture.makeAPIEventType()]))

        // Seed another mutation
        seedEventMutation(mockStore: mockStore, eventId: "evt-blocked")

        await engine.performSync()

        // Verify no new batch calls were made (sync was blocked)
        let callsAfter = mockNetwork.createEventsBatchCalls.count
        #expect(callsAfter == callsBefore, "No new batch calls should be made while circuit breaker is tripped")
    }

    @Test("Sync allowed after circuit breaker reset")
    func syncAllowedAfterReset() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Trip the circuit breaker
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)

        // Verify tripped
        var isTripped = await engine.isCircuitBreakerTripped
        #expect(isTripped == true)

        // Reset circuit breaker
        await engine.resetCircuitBreaker()
        isTripped = await engine.isCircuitBreakerTripped
        #expect(isTripped == false)

        // Clear mocks and seed new mutation
        mockNetwork.reset()
        mockStore.reset()

        // Configure for successful sync
        mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)

        let createdEvent = APIModelFixture.makeAPIEvent(id: "evt-new")
        mockNetwork.createEventsBatchResponses = [
            .success(APIModelFixture.makeBatchCreateEventsResponse(
                created: [createdEvent],
                total: 1,
                success: 1
            ))
        ]

        seedEventMutation(mockStore: mockStore, eventId: "evt-new")

        await engine.performSync()

        // Verify batch call was made
        #expect(mockNetwork.createEventsBatchCalls.count == 1, "Batch call should be made after circuit breaker reset")
    }
}

// MARK: - Circuit Breaker - Exponential Backoff

@Suite("Circuit Breaker - Exponential Backoff")
struct CircuitBreakerExponentialBackoffTests {

    @Test("Backoff timing follows exponential progression (CB-04)")
    func backoffFollowsExponentialProgression() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Trip 1: 30s (base backoff)
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)
        var backoff = await engine.circuitBreakerBackoffRemaining
        #expect(backoff > 25 && backoff <= 35, "Trip 1: expected ~30s, got \(backoff)")

        // Reset and trip again: 60s (30 * 2)
        await engine.resetCircuitBreaker()
        mockNetwork.reset()
        mockStore.reset()
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)
        backoff = await engine.circuitBreakerBackoffRemaining
        #expect(backoff > 55 && backoff <= 65, "Trip 2: expected ~60s, got \(backoff)")

        // Reset and trip again: 120s (30 * 4)
        await engine.resetCircuitBreaker()
        mockNetwork.reset()
        mockStore.reset()
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)
        backoff = await engine.circuitBreakerBackoffRemaining
        #expect(backoff > 115 && backoff <= 125, "Trip 3: expected ~120s, got \(backoff)")

        // Reset and trip again: 240s (30 * 8)
        await engine.resetCircuitBreaker()
        mockNetwork.reset()
        mockStore.reset()
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)
        backoff = await engine.circuitBreakerBackoffRemaining
        #expect(backoff > 235 && backoff <= 245, "Trip 4: expected ~240s, got \(backoff)")

        // Reset and trip again: 300s (capped at max, multiplier capped at 10)
        await engine.resetCircuitBreaker()
        mockNetwork.reset()
        mockStore.reset()
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)
        backoff = await engine.circuitBreakerBackoffRemaining
        #expect(backoff > 295 && backoff <= 305, "Trip 5: expected ~300s (max cap), got \(backoff)")

        // Verify it stays at max after further trips
        await engine.resetCircuitBreaker()
        mockNetwork.reset()
        mockStore.reset()
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)
        backoff = await engine.circuitBreakerBackoffRemaining
        #expect(backoff > 295 && backoff <= 305, "Trip 6: should stay at ~300s (max cap), got \(backoff)")
    }

    @Test("Backoff multiplier resets to 1.0 after successful sync")
    func backoffMultiplierResetsAfterSuccessfulSync() async throws {
        let (mockNetwork, mockStore, _, engine) = makeTestDependencies(initialCursor: 1000)

        // Trip twice to increase multiplier
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)
        await engine.resetCircuitBreaker()
        mockNetwork.reset()
        mockStore.reset()

        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)
        var backoff = await engine.circuitBreakerBackoffRemaining
        #expect(backoff > 55 && backoff <= 65, "Trip 2: expected ~60s")

        // Reset circuit breaker, then do a successful sync to reset multiplier
        await engine.resetCircuitBreaker()
        mockNetwork.reset()
        mockStore.reset()

        // Configure for a successful sync with a mutation that succeeds
        mockNetwork.changeFeedResponseToReturn = ChangeFeedResponse(changes: [], nextCursor: 1000, hasMore: false)
        mockNetwork.getEventTypesResponses = [.success([APIModelFixture.makeAPIEventType()])]
        let request = APIModelFixture.makeCreateEventRequest(id: "evt-success", eventTypeId: "type-1")
        let payload = try! JSONEncoder().encode(request)
        _ = mockStore.seedPendingMutation(entityType: .event, entityId: "evt-success", operation: .create, payload: payload)
        mockNetwork.createEventsBatchResponses = [
            .success(APIModelFixture.makeBatchCreateEventsResponse(
                created: [APIModelFixture.makeAPIEvent(id: "evt-success")],
                total: 1,
                success: 1
            ))
        ]
        await engine.performSync()

        // After successful sync, multiplier should be reset to 1.0
        // Now trip again and verify backoff is back to base (30s)
        mockNetwork.reset()
        mockStore.reset()
        await tripCircuitBreaker(mockNetwork: mockNetwork, mockStore: mockStore, engine: engine)
        backoff = await engine.circuitBreakerBackoffRemaining

        // After successful sync resets multiplier, next trip should be 30s * 1.0 = 30s
        #expect(backoff > 25 && backoff <= 35, "After successful sync, backoff should be ~30s (multiplier reset to 1.0), got \(backoff)")
    }
}
