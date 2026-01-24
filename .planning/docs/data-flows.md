# Data Flows

This document describes the data flows in the SyncEngine for key operations: creating events, running sync cycles, and performing bootstrap fetches.

## Overview

The SyncEngine coordinates data flow between:
- **EventStore**: User-facing data operations
- **DataStore**: Local SwiftData persistence
- **NetworkClient**: Backend API communication
- **Backend**: Go API server with Supabase

**Source:** `apps/ios/trendy/Services/Sync/SyncEngine.swift`

## Create Event Flow

When a user creates an event, it is saved locally and queued for sync.

```mermaid
sequenceDiagram
    participant U as User
    participant ES as EventStore
    participant DS as DataStore
    participant SE as SyncEngine
    participant NC as NetworkClient
    participant BE as Backend

    U->>ES: createEvent(eventType, timestamp, notes)

    rect rgb(230, 245, 255)
        Note over ES,DS: Local Save Phase
        ES->>DS: save(event)
        ES->>DS: insertPendingMutation(CREATE, event.id, payload)
        DS->>DS: Persist to SwiftData
    end

    ES->>SE: performSync()

    rect rgb(255, 245, 230)
        Note over SE,BE: Sync Phase
        SE->>SE: Check circuit breaker
        SE->>SE: performHealthCheck()
        SE->>DS: fetchPendingMutations()
        DS-->>SE: [PendingMutation]

        alt Batch create (event CREATE mutations)
            SE->>NC: createEventsBatch([events])
            NC->>BE: POST /events/batch
            BE-->>NC: BatchCreateEventsResponse
            NC-->>SE: Success
            SE->>DS: markEventSynced(id)
            SE->>DS: deletePendingMutation(mutation)
        else Individual create
            SE->>NC: createEventWithIdempotency(request, key)
            NC->>BE: POST /events
            BE-->>NC: 201 Created
            NC-->>SE: APIEvent
            SE->>DS: markEventSynced(id)
            SE->>DS: deletePendingMutation(mutation)
        end
    end

    SE->>SE: updateState(.idle)
```

### Key Points

- Events are saved locally **immediately** (optimistic UI)
- A `PendingMutation` with operation `CREATE` is queued
- `performSync()` can be triggered immediately or batched
- Batch API is used for event CREATEs (50 per batch)
- Idempotency keys prevent duplicate creation on retry

## Sync Cycle Flow (performSync)

The main synchronization cycle consists of three phases: health check, push, and pull.

```mermaid
sequenceDiagram
    participant T as Trigger
    participant SE as SyncEngine
    participant DS as DataStore
    participant NC as NetworkClient
    participant BE as Backend

    T->>SE: performSync()

    alt Already syncing
        SE-->>T: Skip (single-flight)
    else Not syncing
        SE->>SE: isSyncing = true
    end

    rect rgb(255, 240, 240)
        Note over SE,NC: Health Check
        SE->>NC: getEventTypes()
        NC->>BE: GET /event-types
        alt Health check passes
            BE-->>NC: 200 OK
            NC-->>SE: [APIEventType]
        else Health check fails
            BE-->>NC: Error / Captive Portal
            NC-->>SE: Error
            SE->>SE: Skip sync, return
        end
    end

    SE->>SE: state = .syncing(0, total)

    rect rgb(255, 250, 230)
        Note over SE,DS: Capture Pending Deletes
        SE->>DS: fetchPendingMutations()
        DS-->>SE: [PendingMutation]
        SE->>SE: pendingDeleteIds = Set(deletes.map(.entityId))
    end

    rect rgb(230, 255, 230)
        Note over SE,BE: Push Phase (flushPendingMutations)
        SE->>SE: syncEventCreateBatches()
        loop For each batch of 50
            SE->>NC: createEventsBatch(batch)
            NC->>BE: POST /events/batch
            BE-->>NC: BatchResponse
            SE->>SE: state = .syncing(syncedCount, total)
        end
        SE->>SE: syncOtherMutations()
        loop For each non-event-CREATE mutation
            SE->>NC: create/update/delete API call
            NC->>BE: API request
            BE-->>NC: Response
            SE->>DS: Delete mutation on success
        end
    end

    SE->>SE: state = .pulling

    rect rgb(230, 230, 255)
        Note over SE,BE: Pull Phase (pullChanges)
        loop While hasMore
            SE->>NC: getChanges(since: cursor, limit: 100)
            NC->>BE: GET /changes?cursor=X&limit=100
            BE-->>NC: ChangeFeedResponse
            SE->>SE: applyChanges(changes)
            SE->>SE: Check pendingDeleteIds (resurrection prevention)
            SE->>DS: upsert/delete entities
            SE->>SE: cursor = nextCursor
        end
    end

    SE->>SE: state = .idle
    SE->>SE: lastSyncTime = Date()
```

### Resurrection Prevention

Before applying CREATE/UPDATE changes from the backend, the SyncEngine checks if the entity has a pending DELETE:

```swift
if pendingDeleteIds.contains(change.entityId) {
    Log.sync.debug("Skipping resurrection of pending-delete entity")
    return
}
```

This prevents a race condition where:
1. User deletes an event locally
2. Backend's change feed still has the CREATE entry
3. Without check, the event would be re-created

## Bootstrap Fetch Flow

When the cursor is 0 (first sync) or `forceBootstrapOnNextSync` is true, a full data fetch is performed.

```mermaid
sequenceDiagram
    participant SE as SyncEngine
    participant DS as DataStore
    participant NC as NetworkClient
    participant BE as Backend

    Note over SE: cursor == 0 OR forceBootstrapOnNextSync

    SE->>SE: forceBootstrapOnNextSync = false
    SE->>SE: state = .pulling

    rect rgb(255, 230, 230)
        Note over SE,DS: Nuclear Cleanup (performNuclearCleanup)
        SE->>DS: fetchAllEvents()
        SE->>DS: deleteAllEvents()
        SE->>DS: fetchAllGeofences()
        SE->>DS: deleteAllGeofences()
        SE->>DS: fetchAllPropertyDefinitions()
        SE->>DS: deleteAllPropertyDefinitions()
        SE->>DS: fetchAllEventTypes()
        SE->>DS: deleteAllEventTypes()
        SE->>DS: save()
        Note over DS: Clean slate
    end

    rect rgb(230, 255, 230)
        Note over SE,BE: Fetch EventTypes (fetchEventTypesForBootstrap)
        SE->>NC: getEventTypes()
        NC->>BE: GET /event-types
        BE-->>NC: [APIEventType]
        loop For each eventType
            SE->>DS: upsertEventType(id, configure)
        end
        SE->>DS: save()
    end

    rect rgb(230, 245, 255)
        Note over SE,BE: Fetch Geofences (fetchGeofencesForBootstrap)
        SE->>NC: getGeofences(activeOnly: false)
        NC->>BE: GET /geofences
        BE-->>NC: [APIGeofence]
        loop For each geofence
            SE->>DS: upsertGeofence(id, configure)
        end
        SE->>DS: save()
    end

    rect rgb(255, 245, 230)
        Note over SE,BE: Fetch Events (fetchEventsForBootstrap)
        SE->>NC: getAllEvents(batchSize: 50)
        loop Pagination
            NC->>BE: GET /events?limit=50&offset=X
            BE-->>NC: [APIEvent]
        end
        loop For each event
            SE->>DS: upsertEvent(id, configure)
            SE->>DS: Establish event.eventType relationship
        end
        SE->>DS: save()
    end

    rect rgb(245, 230, 255)
        Note over SE,BE: Fetch PropertyDefinitions (fetchPropertyDefinitionsForBootstrap)
        loop For each eventType
            SE->>NC: getPropertyDefinitions(eventTypeId)
            NC->>BE: GET /event-types/{id}/property-definitions
            BE-->>NC: [APIPropertyDefinition]
            loop For each propDef
                SE->>DS: upsertPropertyDefinition(id, eventTypeId, configure)
            end
        end
        SE->>DS: save()
    end

    SE->>SE: restoreEventTypeRelationships(dataStore)
    SE->>NC: getLatestCursor()
    NC->>BE: GET /changes/cursor
    BE-->>NC: latestCursor
    SE->>SE: cursor = latestCursor
    SE->>SE: Save cursor to UserDefaults

    Note over SE: Post bootstrap notification
    SE->>SE: NotificationCenter.post(.syncEngineBootstrapCompleted)
```

### Refactored Methods (Phase 21)

The bootstrap flow was refactored in Phase 21 to improve maintainability:

| Method | Lines | Purpose |
|--------|-------|---------|
| `performNuclearCleanup` | 39 | Delete all local data |
| `fetchEventTypesForBootstrap` | 32 | Fetch and upsert event types |
| `fetchGeofencesForBootstrap` | 35 | Fetch and upsert geofences |
| `fetchEventsForBootstrap` | 61 | Fetch events with pagination |
| `fetchPropertyDefinitionsForBootstrap` | 56 | Fetch property definitions per type |

### Bootstrap Completion Notification

After bootstrap, a notification is posted so HealthKitService can reload its processed sample IDs:

```swift
await MainActor.run {
    NotificationCenter.default.post(name: .syncEngineBootstrapCompleted, object: nil)
}
```

This prevents duplicate event creation when HealthKit observer queries fire after bootstrap.

## Update and Delete Flows

Updates and deletes follow a similar pattern to creates.

### Update Flow

```mermaid
sequenceDiagram
    participant ES as EventStore
    participant DS as DataStore
    participant SE as SyncEngine
    participant NC as NetworkClient
    participant BE as Backend

    ES->>DS: Update event locally
    ES->>DS: insertPendingMutation(UPDATE, event.id, payload)
    ES->>SE: performSync()

    SE->>NC: updateEvent(id, request)
    NC->>BE: PUT /events/{id}
    BE-->>NC: 200 OK
    SE->>DS: deletePendingMutation(mutation)
```

### Delete Flow

```mermaid
sequenceDiagram
    participant ES as EventStore
    participant DS as DataStore
    participant SE as SyncEngine
    participant NC as NetworkClient
    participant BE as Backend

    ES->>DS: Delete event locally (optional, can keep for offline)
    ES->>DS: insertPendingMutation(DELETE, event.id, payload)
    ES->>SE: performSync()

    Note over SE: Capture pendingDeleteIds for resurrection prevention

    SE->>NC: deleteEvent(id)
    NC->>BE: DELETE /events/{id}
    BE-->>NC: 204 No Content
    SE->>DS: deletePendingMutation(mutation)
```

## Related Documentation

- [Sync State Machine](./sync-state-machine.md) - State diagram and transitions
- [Error Recovery Flows](./error-recovery.md) - Error handling and circuit breaker
- [DI Architecture](./di-architecture.md) - Protocol relationships for testing
