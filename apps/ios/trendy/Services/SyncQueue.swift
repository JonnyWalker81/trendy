//
//  SyncQueue.swift
//  trendy
//
//  Manages offline operations queue and synchronization
//

import Foundation
import SwiftData
import Network

/// Service for managing offline operation queue
@Observable
class SyncQueue {
    private(set) var isSyncing = false
    private(set) var pendingCount = 0
    private(set) var hasPendingOperations = false

    private let apiClient: APIClient
    private let modelContext: ModelContext
    private let monitor = NWPathMonitor()
    private var isOnline = false

    /// Initialize SyncQueue with dependencies
    /// - Parameters:
    ///   - modelContext: SwiftData context for queue operations
    ///   - apiClient: API client for backend communication
    init(modelContext: ModelContext, apiClient: APIClient) {
        self.modelContext = modelContext
        self.apiClient = apiClient

        // Monitor network connectivity
        monitor.pathUpdateHandler = { [weak self] path in
            let wasOffline = !(self?.isOnline ?? false)
            self?.isOnline = (path.status == .satisfied)

            // If we just came online and have pending operations, sync
            if wasOffline && (self?.isOnline ?? false) {
                Task {
                    await self?.syncPendingOperations()
                }
            }
        }

        let queue = DispatchQueue(label: "com.trendy.network-monitor")
        monitor.start(queue: queue)

        // Check initial queue count
        updatePendingCount()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Queue Operations

    /// Add operation to queue
    func enqueue(
        type: OperationType,
        entityId: UUID,
        payload: Encodable
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let payloadData = try encoder.encode(payload)

        let operation = QueuedOperation(
            operationType: type.rawValue,
            entityId: entityId,
            payload: payloadData
        )

        modelContext.insert(operation)
        try modelContext.save()

        updatePendingCount()

        // Try to sync immediately if online
        if isOnline {
            Task {
                await syncPendingOperations()
            }
        }
    }

    /// Update pending operation count
    private func updatePendingCount() {
        let descriptor = FetchDescriptor<QueuedOperation>()
        if let count = try? modelContext.fetchCount(descriptor) {
            Task { @MainActor in
                self.pendingCount = count
                self.hasPendingOperations = count > 0
            }
        }
    }

    // MARK: - Synchronization

    /// Sync all pending operations
    func syncPendingOperations() async {
        guard !isSyncing else {
            print("Sync already in progress")
            return
        }

        guard isOnline else {
            print("Cannot sync: offline")
            return
        }

        await MainActor.run {
            self.isSyncing = true
        }

        defer {
            Task { @MainActor in
                self.isSyncing = false
                self.updatePendingCount()
            }
        }

        do {
            // Fetch all pending operations sorted by creation date
            var descriptor = FetchDescriptor<QueuedOperation>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
            descriptor.fetchLimit = 100 // Process in batches

            let operations = try modelContext.fetch(descriptor)

            print("Processing \(operations.count) queued operations")

            for operation in operations {
                do {
                    try await processOperation(operation)
                    // Success - remove from queue
                    modelContext.delete(operation)
                } catch {
                    // Failed - update attempt count and error
                    operation.attempts += 1
                    operation.lastError = error.localizedDescription

                    // Remove after 5 failed attempts
                    if operation.attempts >= 5 {
                        print("Removing operation after 5 failed attempts: \(operation.operationType)")
                        modelContext.delete(operation)
                    }
                }
            }

            try modelContext.save()
        } catch {
            print("Sync error: \(error.localizedDescription)")
        }
    }

    /// Process a single queued operation
    private func processOperation(_ operation: QueuedOperation) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        switch operation.operationType {
        case OperationType.createEvent.rawValue:
            let request = try decoder.decode(CreateEventRequest.self, from: operation.payload)
            let _ = try await apiClient.createEvent(request)

        case OperationType.updateEvent.rawValue:
            let request = try decoder.decode(UpdateEventRequest.self, from: operation.payload)
            // We need the backend ID, which should be stored somewhere
            // For now, we'll skip updates in the queue (events are created fresh)
            print("Skipping update operation: \(operation.id)")

        case OperationType.deleteEvent.rawValue:
            let backendId = String(decoding: operation.payload, as: UTF8.self)
            try await apiClient.deleteEvent(id: backendId)

        case OperationType.createEventType.rawValue:
            let request = try decoder.decode(CreateEventTypeRequest.self, from: operation.payload)
            let _ = try await apiClient.createEventType(request)

        case OperationType.updateEventType.rawValue:
            let queuedUpdate = try decoder.decode(QueuedEventTypeUpdate.self, from: operation.payload)
            _ = try await apiClient.updateEventType(id: queuedUpdate.backendId, queuedUpdate.request)

        case OperationType.deleteEventType.rawValue:
            let backendId = String(decoding: operation.payload, as: UTF8.self)
            try await apiClient.deleteEventType(id: backendId)

        case OperationType.createGeofence.rawValue:
            let request = try decoder.decode(CreateGeofenceRequest.self, from: operation.payload)
            // ID is already included in the request - same ID used locally and on backend
            let _ = try await apiClient.createGeofence(request)
            Log.sync.info("Queued geofence synced", context: .with { ctx in
                ctx.add("id", operation.entityId.uuidString)
            })

        case OperationType.updateGeofence.rawValue:
            let queuedUpdate = try decoder.decode(QueuedGeofenceUpdate.self, from: operation.payload)
            _ = try await apiClient.updateGeofence(id: queuedUpdate.backendId, queuedUpdate.request)

        case OperationType.deleteGeofence.rawValue:
            let backendId = String(decoding: operation.payload, as: UTF8.self)
            try await apiClient.deleteGeofence(id: backendId)

        default:
            print("Unknown operation type: \(operation.operationType)")
        }
    }

    // MARK: - Manual Sync

    /// Manually trigger sync (for pull-to-refresh)
    func manualSync() async {
        guard isOnline else { return }
        await syncPendingOperations()
    }

    // MARK: - Queue Management

    /// Clear all queued operations (for testing)
    func clearQueue() throws {
        let descriptor = FetchDescriptor<QueuedOperation>()
        let operations = try modelContext.fetch(descriptor)

        for operation in operations {
            modelContext.delete(operation)
        }

        try modelContext.save()
        updatePendingCount()
    }

}
