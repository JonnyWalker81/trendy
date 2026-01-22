//
//  DataStoreFactory.swift
//  trendy
//
//  Factory protocol for creating DataStore instances within actor context.
//  Solves the ModelContext non-Sendable problem for dependency injection.
//

import Foundation
import SwiftData

/// Factory protocol for creating DataStore instances within actor context.
///
/// This pattern solves the ModelContext threading problem:
/// - ModelContainer IS Sendable (can be passed to actor)
/// - ModelContext is NOT Sendable (must be created on the thread/actor where it's used)
///
/// The factory is injected into SyncEngine, then called inside the actor
/// to create a DataStore with a fresh ModelContext bound to that actor's context.
protocol DataStoreFactory: Sendable {
    /// Creates a new DataStore with a fresh ModelContext.
    /// Called within actor isolation context to ensure ModelContext thread safety.
    ///
    /// - Returns: A DataStore instance ready for persistence operations
    func makeDataStore() -> any DataStoreProtocol
}

/// Default factory implementation using ModelContainer.
/// Production code uses this to create real LocalStore instances.
final class DefaultDataStoreFactory: DataStoreFactory, @unchecked Sendable {
    // ModelContainer is Sendable, so this is safe
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func makeDataStore() -> any DataStoreProtocol {
        let context = ModelContext(modelContainer)
        return LocalStore(modelContext: context)
    }
}
