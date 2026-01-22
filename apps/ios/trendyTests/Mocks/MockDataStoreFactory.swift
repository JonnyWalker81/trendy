//
//  MockDataStoreFactory.swift
//  trendyTests
//
//  Factory that returns a pre-configured MockDataStore for testing.
//  Conforms to DataStoreFactory so it can be injected into SyncEngine.
//

import Foundation
@testable import trendy

/// Factory that returns a pre-configured MockDataStore for testing.
/// Conforms to DataStoreFactory so it can be injected into SyncEngine.
///
/// Usage:
/// ```swift
/// let mockStore = MockDataStore()
/// let factory = MockDataStoreFactory(mockStore: mockStore)
/// let syncEngine = SyncEngine(networkClient: mockNetwork, dataStoreFactory: factory)
/// ```
final class MockDataStoreFactory: DataStoreFactory, @unchecked Sendable {
    /// The mock store instance returned by makeDataStore()
    private let mockStore: MockDataStore

    /// Whether makeDataStore() has been called
    private(set) var makeDataStoreCalled = false

    /// Number of times makeDataStore() was called
    private(set) var makeDataStoreCallCount = 0

    init(mockStore: MockDataStore) {
        self.mockStore = mockStore
    }

    /// Returns the mock store instance.
    /// Note: Unlike production factory which creates fresh ModelContext,
    /// this returns the same mock instance for test verification.
    func makeDataStore() -> any DataStoreProtocol {
        makeDataStoreCalled = true
        makeDataStoreCallCount += 1
        return mockStore
    }

    /// Reset call tracking state
    func reset() {
        makeDataStoreCalled = false
        makeDataStoreCallCount = 0
    }
}
