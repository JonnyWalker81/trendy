//
//  MockNetworkClientTests.swift
//  trendyTests
//
//  Tests for MockNetworkClient behavior and spy pattern.
//

import Testing
@testable import trendy

@Test("MockNetworkClient tracks method calls")
func test_tracksMethodCalls() async throws {
    let mock = MockNetworkClient()
    mock.eventTypesToReturn = [APIModelFixture.makeAPIEventType()]

    _ = try await mock.getEventTypes()

    #expect(mock.getEventTypesCalls.count == 1)
    #expect(mock.getEventTypesCalls.first?.timestamp != nil)
}

@Test("MockNetworkClient returns configured response")
func test_returnsConfiguredResponse() async throws {
    let mock = MockNetworkClient()
    let expected = APIModelFixture.makeAPIEventType(id: "custom-id", name: "Custom")
    mock.eventTypesToReturn = [expected]

    let types = try await mock.getEventTypes()

    #expect(types.count == 1)
    #expect(types.first?.id == "custom-id")
    #expect(types.first?.name == "Custom")
}

@Test("MockNetworkClient throws configured error")
func test_throwsConfiguredError() async throws {
    let mock = MockNetworkClient()
    mock.errorToThrow = APIError.httpError(500)

    await #expect(throws: APIError.self) {
        try await mock.getEventTypes()
    }

    // Call was still recorded
    #expect(mock.getEventTypesCalls.count == 1)
}

@Test("MockNetworkClient response queue enables sequential testing")
func test_responseQueueSequentialBehavior() async throws {
    let mock = MockNetworkClient()
    mock.getEventTypesResponses = [
        .failure(APIError.httpError(500)),
        .failure(APIError.httpError(500)),
        .success([APIModelFixture.makeAPIEventType()])
    ]

    // First two calls throw
    await #expect(throws: APIError.self) {
        try await mock.getEventTypes()
    }
    await #expect(throws: APIError.self) {
        try await mock.getEventTypes()
    }

    // Third call succeeds
    let types = try await mock.getEventTypes()
    #expect(types.count == 1)

    // All three calls recorded
    #expect(mock.getEventTypesCalls.count == 3)
}

@Test("MockNetworkClient reset clears all state")
func test_resetClearsState() async throws {
    let mock = MockNetworkClient()
    mock.eventTypesToReturn = [APIModelFixture.makeAPIEventType()]
    mock.errorToThrow = APIError.httpError(500)
    _ = try? await mock.getEventTypes()

    mock.reset()

    #expect(mock.getEventTypesCalls.isEmpty)
    #expect(mock.eventTypesToReturn.isEmpty)
    #expect(mock.errorToThrow == nil)
}

@Test("MockNetworkClient records create call arguments")
func test_recordsCreateCallArguments() async throws {
    let mock = MockNetworkClient()
    mock.eventsToReturn = [APIModelFixture.makeAPIEvent()]

    let request = APIModelFixture.makeCreateEventRequest(
        eventTypeId: "type-123",
        notes: "Test notes"
    )
    _ = try await mock.createEvent(request)

    #expect(mock.createEventCalls.count == 1)
    #expect(mock.createEventCalls.first?.request.eventTypeId == "type-123")
    #expect(mock.createEventCalls.first?.request.notes == "Test notes")
}

@Test("MockNetworkClient handles batch create with default response")
func test_handlesBatchCreate() async throws {
    let mock = MockNetworkClient()

    let requests = [
        APIModelFixture.makeCreateEventRequest(id: "evt-1", eventTypeId: "type-1"),
        APIModelFixture.makeCreateEventRequest(id: "evt-2", eventTypeId: "type-1")
    ]

    let response = try await mock.createEventsBatch(requests)

    #expect(response.success == 2)
    #expect(response.failed == 0)
    #expect(response.created.count == 2)
    #expect(mock.createEventsBatchCalls.count == 1)
}

@Test("MockNetworkClient tracks geofence operations")
func test_tracksGeofenceOperations() async throws {
    let mock = MockNetworkClient()

    let createRequest = CreateGeofenceRequest(
        name: "Home",
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 100.0,
        eventTypeEntryId: nil,
        eventTypeExitId: nil,
        isActive: true,
        notifyOnEntry: true,
        notifyOnExit: false
    )

    let geofence = try await mock.createGeofence(createRequest)

    #expect(mock.createGeofenceCalls.count == 1)
    #expect(mock.createGeofenceCalls.first?.request.name == "Home")
    #expect(geofence.name == "Home")
    #expect(geofence.latitude == 37.7749)
}

@Test("MockNetworkClient change feed with cursor tracking")
func test_changeFeedCursorTracking() async throws {
    let mock = MockNetworkClient()
    mock.changeFeedResponseToReturn = ChangeFeedResponse(
        changes: [],
        nextCursor: 100,
        hasMore: false
    )

    let response = try await mock.getChanges(since: 50, limit: 100)

    #expect(mock.getChangesCalls.count == 1)
    #expect(mock.getChangesCalls.first?.cursor == 50)
    #expect(mock.getChangesCalls.first?.limit == 100)
    #expect(response.nextCursor == 100)
}

@Test("MockNetworkClient totalCallCount aggregates all calls")
func test_totalCallCountAggregation() async throws {
    let mock = MockNetworkClient()
    mock.eventTypesToReturn = [APIModelFixture.makeAPIEventType()]
    mock.eventsToReturn = [APIModelFixture.makeAPIEvent()]

    _ = try await mock.getEventTypes()
    _ = try await mock.getEvents(limit: 10, offset: 0)
    _ = try await mock.getLatestCursor()

    #expect(mock.totalCallCount == 3)
}
