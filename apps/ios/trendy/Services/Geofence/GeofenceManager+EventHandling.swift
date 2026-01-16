//
//  GeofenceManager+EventHandling.swift
//  trendy
//
//  Geofence entry/exit event creation and active event tracking
//

import Foundation
import CoreLocation
import SwiftData

// MARK: - Active Geofence Events

extension GeofenceManager {
    /// Load active geofence events from UserDefaults
    internal func loadActiveGeofenceEvents() {
        if let data = UserDefaults.standard.data(forKey: "activeGeofenceEvents"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            activeGeofenceEvents = decoded
        }
    }

    /// Save active geofence events to UserDefaults
    internal func saveActiveGeofenceEvents() {
        if let encoded = try? JSONEncoder().encode(activeGeofenceEvents) {
            UserDefaults.standard.set(encoded, forKey: "activeGeofenceEvents")
        }
    }

    /// Check if a geofence has an active event (user is currently inside)
    func activeEvent(for geofenceId: String) -> String? {
        return activeGeofenceEvents[geofenceId]
    }
}

// MARK: - Launch and Background Event Handlers

extension GeofenceManager {
    /// Handle normal launch notification - ensures regions are registered
    @objc internal func handleNormalLaunch(_ notification: Notification) {
        Log.geofence.info("Handling normal launch notification")
        ensureRegionsRegistered()
    }

    /// Handle background entry notification from AppDelegate
    @objc internal func handleBackgroundEntry(_ notification: Notification) {
        guard let identifier = notification.userInfo?["identifier"] as? String else {
            Log.geofence.warning("Background entry notification missing identifier")
            return
        }
        Log.geofence.info("Processing background entry event", context: .with { ctx in
            ctx.add("identifier", identifier)
        })
        Task { @MainActor in
            guard let localId = eventStore.lookupLocalGeofenceId(from: identifier) else {
                Log.geofence.warning("Unknown region identifier on background entry", context: .with { ctx in
                    ctx.add("identifier", identifier)
                })
                return
            }
            self.handleGeofenceEntry(geofenceId: localId)
        }
    }

    /// Handle background exit notification from AppDelegate
    @objc internal func handleBackgroundExit(_ notification: Notification) {
        guard let identifier = notification.userInfo?["identifier"] as? String else {
            Log.geofence.warning("Background exit notification missing identifier")
            return
        }
        Log.geofence.info("Processing background exit event", context: .with { ctx in
            ctx.add("identifier", identifier)
        })
        Task { @MainActor in
            guard let localId = eventStore.lookupLocalGeofenceId(from: identifier) else {
                Log.geofence.warning("Unknown region identifier on background exit", context: .with { ctx in
                    ctx.add("identifier", identifier)
                })
                return
            }
            self.handleGeofenceExit(geofenceId: localId)
        }
    }
}

// MARK: - Event Creation/Update

extension GeofenceManager {
    /// Handle geofence entry - create a new event
    internal func handleGeofenceEntry(geofenceId: String) {
        Log.geofence.debug("handleGeofenceEntry called", context: .with { ctx in
            ctx.add("geofenceId", geofenceId)
        })

        let descriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { geofence in geofence.id == geofenceId }
        )
        guard let geofence = try? modelContext.fetch(descriptor).first else {
            Log.geofence.error("Geofence not found in database", context: .with { ctx in
                ctx.add("geofenceId", geofenceId)
            })
            return
        }
        Log.geofence.debug("Found geofence", context: .with { ctx in
            ctx.add("name", geofence.name)
        })

        // Check if already has an active event
        if let existingEventId = activeGeofenceEvents[geofenceId] {
            Log.geofence.warning("Geofence already has an active event", context: .with { ctx in
                ctx.add("name", geofence.name)
                ctx.add("existingEventId", existingEventId)
            })
            return
        }

        // Get the entry event type by ID
        guard let eventTypeEntryID = geofence.eventTypeEntryID else {
            Log.geofence.error("Geofence has no eventTypeEntryID set", context: .with { ctx in
                ctx.add("name", geofence.name)
            })
            return
        }

        Log.geofence.debug("Looking for EventType", context: .with { ctx in
            ctx.add("eventTypeId", eventTypeEntryID)
        })

        // Fetch the EventType by ID
        let eventTypeDescriptor = FetchDescriptor<EventType>(
            predicate: #Predicate { eventType in eventType.id == eventTypeEntryID }
        )

        guard let eventType = try? modelContext.fetch(eventTypeDescriptor).first else {
            Log.geofence.error("EventType not found", context: .with { ctx in
                ctx.add("eventTypeId", eventTypeEntryID)
                ctx.add("geofenceName", geofence.name)
            })
            return
        }

        Log.geofence.debug("Found EventType", context: .with { ctx in
            ctx.add("name", eventType.name)
        })

        // Create the event with entry timestamp property
        Log.geofence.debug("Creating new Event for geofence entry")
        let entryTime = Date()
        let entryProperties: [String: PropertyValue] = [
            "Entered At": PropertyValue(type: .date, value: entryTime)
        ]

        // Use geofence ID for linking (now single canonical ID)
        let event = Event(
            timestamp: entryTime,
            eventType: eventType,
            notes: "Auto-logged by geofence: \(geofence.name)",
            sourceType: .geofence,
            geofenceId: geofence.id,  // Uses canonical UUIDv7 string ID
            locationLatitude: geofence.latitude,
            locationLongitude: geofence.longitude,
            locationName: geofence.name,
            properties: entryProperties
        )

        modelContext.insert(event)

        do {
            try modelContext.save()

            // Track this as an active event
            activeGeofenceEvents[geofenceId] = event.id
            saveActiveGeofenceEvents()

            Log.geofence.info("Created geofence entry event", context: .with { ctx in
                ctx.add("geofenceName", geofence.name)
                ctx.add("eventId", event.id)
                ctx.add("eventType", eventType.name)
            })

            // Track for debugging
            lastEventTimestamp = Date()
            lastEventDescription = "Entry: \(geofence.name)"

            // Send notification if enabled
            if geofence.notifyOnEntry, let notificationManager = notificationManager {
                Task {
                    await notificationManager.sendGeofenceEntryNotification(
                        geofenceName: geofence.name,
                        eventTypeName: eventType.name
                    )
                }
            }

            // Sync to backend (SyncEngine handles offline queueing)
            Task { @MainActor in
                await eventStore.syncEventToBackend(event)
            }

        } catch {
            Log.geofence.error("Failed to save geofence entry event", error: error)
            lastError = .entryEventSaveFailed(geofence.name, error)
        }
    }

    /// Handle geofence exit - update the existing event with end date
    internal func handleGeofenceExit(geofenceId: String) {
        let geofenceDescriptor = FetchDescriptor<Geofence>(
            predicate: #Predicate { geofence in geofence.id == geofenceId }
        )
        guard let geofence = try? modelContext.fetch(geofenceDescriptor).first else {
            Log.geofence.error("Geofence not found for exit", context: .with { ctx in
                ctx.add("geofenceId", geofenceId)
            })
            return
        }

        guard let eventId = activeGeofenceEvents[geofenceId] else {
            Log.geofence.warning("No active event found for geofence exit", context: .with { ctx in
                ctx.add("name", geofence.name)
            })
            return
        }

        let eventDescriptor = FetchDescriptor<Event>(
            predicate: #Predicate { event in event.id == eventId }
        )

        guard let event = try? modelContext.fetch(eventDescriptor).first else {
            Log.geofence.error("Event not found for geofence exit", context: .with { ctx in
                ctx.add("eventId", eventId)
            })
            // Clean up orphaned active event
            activeGeofenceEvents.removeValue(forKey: geofenceId)
            saveActiveGeofenceEvents()
            return
        }

        // Update the event with end date and exit properties
        let exitTime = Date()
        event.endDate = exitTime

        // Calculate duration in seconds
        let durationSeconds = exitTime.timeIntervalSince(event.timestamp)

        // Add "Exited At" and "Duration" properties while preserving existing properties
        var updatedProperties = event.properties
        updatedProperties["Exited At"] = PropertyValue(type: .date, value: exitTime)
        updatedProperties["Duration"] = PropertyValue(type: .duration, value: durationSeconds)
        event.properties = updatedProperties

        // Use duration for notification
        let duration = durationSeconds

        do {
            try modelContext.save()

            // Remove from active events
            activeGeofenceEvents.removeValue(forKey: geofenceId)
            saveActiveGeofenceEvents()

            Log.geofence.info("Updated geofence exit event", context: .with { ctx in
                ctx.add("geofenceName", geofence.name)
                ctx.add("eventId", event.id)
                ctx.add("durationSeconds", Int(duration))
            })

            // Track for debugging
            lastEventTimestamp = Date()
            lastEventDescription = "Exit: \(geofence.name)"

            // Send notification if enabled
            if geofence.notifyOnExit, let notificationManager = notificationManager, let eventType = event.eventType {
                Task {
                    await notificationManager.sendGeofenceExitNotification(
                        geofenceName: geofence.name,
                        eventTypeName: eventType.name,
                        duration: duration
                    )
                }
            }

            // Sync to backend (SyncEngine handles offline queueing)
            Task { @MainActor in
                await eventStore.syncEventToBackend(event)
            }

        } catch {
            Log.geofence.error("Failed to save geofence exit event", error: error)
            lastError = .exitEventSaveFailed(geofence.name, error)
        }
    }

    /// Clear the last error (call after UI has handled it)
    func clearError() {
        lastError = nil
    }
}
