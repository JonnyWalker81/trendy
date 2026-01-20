//
//  HealthKitService+EventFactory.swift
//  trendy
//
//  Event creation, duplicate checking, and EventType management
//

import Foundation
import HealthKit
import SwiftData

// MARK: - Event Creation

extension HealthKitService {

    /// Create an event for a HealthKit sample
    /// - Parameters:
    ///   - isBulkImport: If true, skips notifications and immediate sync (for historical data import)
    /// - Throws: HealthKitError.eventSaveFailed if saving to SwiftData fails
    @MainActor
    func createEvent(
        eventType: EventType,
        category: HealthDataCategory,
        timestamp: Date,
        endDate: Date?,
        notes: String,
        properties: [String: PropertyValue],
        healthKitSampleId: String,
        isAllDay: Bool = false,
        isBulkImport: Bool = false
    ) async throws {
        let event = Event(
            timestamp: timestamp,
            eventType: eventType,
            notes: notes,
            sourceType: .healthKit,
            isAllDay: isAllDay,
            endDate: endDate,
            healthKitSampleId: healthKitSampleId,
            healthKitCategory: category.rawValue,
            properties: properties
        )

        modelContext.insert(event)

        do {
            try modelContext.save()
            Log.healthKit.info("Created event", context: .with { ctx in
                ctx.add("category", category.displayName)
                ctx.add("isBulkImport", isBulkImport)
            })

            // Skip notifications and sync during bulk import to avoid flooding
            guard !isBulkImport else { return }

            // Send notification if configured
            await sendNotificationIfEnabled(for: category, eventTypeName: eventType.name, details: notes)

            // Sync to backend (SyncEngine handles offline queueing)
            await eventStore.syncEventToBackend(event)

        } catch {
            Log.healthKit.error("Failed to save event", error: error, context: .with { ctx in
                ctx.add("category", category.displayName)
            })
            throw HealthKitError.eventSaveFailed(error)
        }
    }

    /// Check if an event with the given HealthKit sample ID already exists in SwiftData
    /// This provides database-level deduplication as a final safety net
    ///
    /// - Parameters:
    ///   - sampleId: The HealthKit sample UUID to check
    ///   - useFreshContext: If true, creates a fresh ModelContext to see the latest persisted data.
    ///                      Use this during reconciliation flows after bootstrap when modelContext may be stale.
    @MainActor
    func eventExistsWithHealthKitSampleId(_ sampleId: String, useFreshContext: Bool = false) async -> Bool {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.healthKitSampleId == sampleId
            }
        )

        do {
            let context = useFreshContext ? ModelContext(modelContainer) : modelContext
            let existingEvents = try context.fetch(descriptor)
            return !existingEvents.isEmpty
        } catch {
            Log.healthKit.error("Error checking for existing event", error: error)
            // In case of error, assume it doesn't exist to avoid blocking new events
            return false
        }
    }

    /// Check if a workout event with matching timestamps already exists
    /// This handles the case where the same workout has different HealthKit sample IDs
    /// (e.g., synced from multiple devices, or edited in Health app)
    ///
    /// - Parameters:
    ///   - startDate: The workout start timestamp
    ///   - endDate: The workout end timestamp (optional)
    ///   - tolerance: Maximum time difference in seconds to consider a match (default 1.0)
    ///   - useFreshContext: If true, creates a fresh ModelContext to see the latest persisted data.
    ///                      Use this during reconciliation flows after bootstrap when modelContext may be stale.
    @MainActor
    func eventExistsWithMatchingWorkoutTimestamp(
        startDate: Date,
        endDate: Date?,
        tolerance: TimeInterval = 1.0,
        useFreshContext: Bool = false
    ) async -> Bool {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.healthKitCategory == "workout"
            }
        )

        do {
            let context = useFreshContext ? ModelContext(modelContainer) : modelContext
            let events = try context.fetch(descriptor)

            // DIAGNOSTIC: Log search parameters and candidate count
            Log.healthKit.debug("[DEDUP-TIMESTAMP] Checking for workout duplicate", context: .with { ctx in
                ctx.add("startDate", startDate.ISO8601Format())
                ctx.add("endDate", endDate?.ISO8601Format() ?? "nil")
                ctx.add("tolerance", tolerance)
                ctx.add("useFreshContext", useFreshContext)
                ctx.add("candidateCount", events.count)
            })

            let match = events.first { event in
                let startDiff = abs(event.timestamp.timeIntervalSince(startDate))
                let startMatches = startDiff <= tolerance
                let endMatches: Bool
                let endDiff: TimeInterval?
                if let eventEnd = event.endDate, let newEnd = endDate {
                    endDiff = abs(eventEnd.timeIntervalSince(newEnd))
                    endMatches = endDiff! <= tolerance
                } else {
                    endDiff = nil
                    endMatches = (event.endDate == nil && endDate == nil)
                }

                // DIAGNOSTIC: Log close matches (within 5 seconds) for debugging
                if startDiff < 5.0 {
                    Log.healthKit.debug("[DEDUP-TIMESTAMP] Close match found", context: .with { ctx in
                        ctx.add("eventId", event.id)
                        ctx.add("eventTimestamp", event.timestamp.ISO8601Format())
                        ctx.add("eventEndDate", event.endDate?.ISO8601Format() ?? "nil")
                        ctx.add("eventSampleId", event.healthKitSampleId ?? "nil")
                        ctx.add("startDiff", String(format: "%.3f", startDiff))
                        ctx.add("endDiff", endDiff.map { String(format: "%.3f", $0) } ?? "N/A")
                        ctx.add("startMatches", startMatches)
                        ctx.add("endMatches", endMatches)
                        ctx.add("isMatch", startMatches && endMatches)
                    })
                }

                return startMatches && endMatches
            }

            if let matchedEvent = match {
                Log.healthKit.info("[DEDUP-TIMESTAMP] Found matching workout", context: .with { ctx in
                    ctx.add("matchedEventId", matchedEvent.id)
                    ctx.add("matchedSampleId", matchedEvent.healthKitSampleId ?? "nil")
                })
                return true
            } else {
                Log.healthKit.debug("[DEDUP-TIMESTAMP] No matching workout found")
                return false
            }
        } catch {
            Log.data.error("Error checking for duplicate workout by timestamp", error: error)
            return false
        }
    }

    /// Check if a HealthKit event with matching content already exists
    /// This handles the case where HealthKit sample IDs change (e.g., after iOS restore,
    /// device migration, or HealthKit database reset) but the actual event content is identical.
    ///
    /// Matches the backend's content-based deduplication logic in repository/event.go:
    /// - Key: (eventTypeId, timestamp truncated to seconds, healthKitCategory)
    ///
    /// - Parameters:
    ///   - eventTypeId: The event type ID (UUID string)
    ///   - timestamp: The event timestamp
    ///   - healthKitCategory: The HealthKit category (e.g., "water", "mindfulness")
    ///   - tolerance: Maximum time difference in seconds to consider a match (default 1.0)
    ///   - useFreshContext: If true, creates a fresh ModelContext to see the latest persisted data.
    @MainActor
    func eventExistsWithMatchingHealthKitContent(
        eventTypeId: String,
        timestamp: Date,
        healthKitCategory: String,
        tolerance: TimeInterval = 1.0,
        useFreshContext: Bool = false
    ) async -> Bool {
        // Query events with matching healthKitCategory
        let category = healthKitCategory
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.healthKitCategory == category
            }
        )

        do {
            let context = useFreshContext ? ModelContext(modelContainer) : modelContext
            let events = try context.fetch(descriptor)

            // Check for content match: eventTypeId + timestamp (within tolerance)
            let match = events.contains { event in
                guard event.eventType?.id == eventTypeId else { return false }
                return abs(event.timestamp.timeIntervalSince(timestamp)) <= tolerance
            }

            if match {
                Log.healthKit.debug("Content-based duplicate found", context: .with { ctx in
                    ctx.add("eventTypeId", eventTypeId)
                    ctx.add("timestamp", timestamp.ISO8601Format())
                    ctx.add("category", healthKitCategory)
                })
            }

            return match
        } catch {
            Log.healthKit.error("Error checking for content-based duplicate", error: error, context: .with { ctx in
                ctx.add("category", healthKitCategory)
            })
            // In case of error, assume it doesn't exist to avoid blocking new events
            return false
        }
    }

    /// Find an event by its HealthKit sample ID
    /// Returns the actual Event object for updates, not just existence check
    @MainActor
    func findEventByHealthKitSampleId(_ sampleId: String) async -> Event? {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in
                event.healthKitSampleId == sampleId
            }
        )

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            Log.data.error("Error finding HealthKit event", context: .with { ctx in
                ctx.add("sampleId", sampleId)
                ctx.add(error: error)
            })
            return nil
        }
    }

    /// Update an existing HealthKit event with new values
    /// Used when daily aggregated metrics (steps, active energy, sleep) change throughout the day
    /// - Throws: HealthKitError.eventUpdateFailed if saving the update fails
    @MainActor
    func updateHealthKitEvent(
        _ event: Event,
        properties: [String: PropertyValue],
        notes: String,
        isAllDay: Bool? = nil
    ) async throws {
        event.properties = properties
        event.notes = notes
        if let isAllDay = isAllDay {
            event.isAllDay = isAllDay
        }
        event.syncStatus = .pending

        do {
            try modelContext.save()
            Log.data.info("Updated HealthKit event locally", context: .with { ctx in
                ctx.add("category", event.healthKitCategory ?? "unknown")
                ctx.add("sampleId", event.healthKitSampleId ?? "none")
                ctx.add("event_id", event.id)
            })

            // Use UPDATE sync (not CREATE) to ensure backend receives the new values
            // CREATE would return 409 Conflict for existing events and the update would be lost
            await eventStore.syncHealthKitEventUpdate(event)
        } catch {
            Log.data.error("Failed to update HealthKit event", context: .with { ctx in
                ctx.add(error: error)
            })
            throw HealthKitError.eventUpdateFailed(error)
        }
    }
}

// MARK: - Auto-Create EventType

extension HealthKitService {

    /// Ensures an EventType exists for the category, creating one if needed
    @MainActor
    func ensureEventType(for category: HealthDataCategory) async -> EventType? {
        let settings = HealthKitSettings.shared

        // 1. Check if settings already has a linked EventType (by id)
        if let eventTypeId = settings.eventTypeId(for: category) {
            let eventTypeDescriptor = FetchDescriptor<EventType>(
                predicate: #Predicate { eventType in eventType.id == eventTypeId }
            )
            if let eventType = try? modelContext.fetch(eventTypeDescriptor).first {
                return eventType
            }
            // ID stored but EventType not found locally - might need sync
            Log.healthKit.warning("EventType not found locally", context: .with { ctx in
                ctx.add("eventTypeId", eventTypeId)
                ctx.add("category", category.displayName)
            })
        }

        // 2. Check if an EventType with the default name already exists
        let defaultName = category.defaultEventTypeName
        let existingDescriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { eventType in eventType.name == defaultName }
        )

        if let existing = try? modelContext.fetch(existingDescriptor).first {
            // Link existing EventType to settings using id
            settings.setEventTypeId(existing.id, for: category)
            return existing
        }

        // 3. Create new EventType with defaults (UUIDv7 id is immediately available)
        let newEventType = EventType(
            name: category.defaultEventTypeName,
            colorHex: category.defaultColor,
            iconName: category.defaultIcon
        )
        modelContext.insert(newEventType)

        do {
            try modelContext.save()
        } catch {
            Log.healthKit.error("Failed to create EventType", error: error, context: .with { ctx in
                ctx.add("category", category.displayName)
            })
            return nil
        }

        // 4. Sync to backend (SyncEngine handles offline queueing)
        await eventStore.syncEventTypeToBackend(newEventType)

        // 5. Link new EventType to settings using id (available immediately with UUIDv7)
        settings.setEventTypeId(newEventType.id, for: category)

        Log.healthKit.info("Auto-created EventType", context: .with { ctx in
            ctx.add("name", newEventType.name)
            ctx.add("category", category.rawValue)
        })
        return newEventType
    }
}

// MARK: - Notifications

extension HealthKitService {

    /// Send notification if enabled for this category
    func sendNotificationIfEnabled(for category: HealthDataCategory, eventTypeName: String, details: String?) async {
        // Check if notifications are enabled for this category using HealthKitSettings
        guard HealthKitSettings.shared.notifyOnDetection(for: category) else { return }
        guard let notificationManager = notificationManager else { return }

        await notificationManager.sendNotification(
            title: "\(category.displayName) Detected",
            body: details ?? "Logged: \(eventTypeName)",
            categoryIdentifier: "HEALTHKIT_DETECTION"
        )
    }
}
