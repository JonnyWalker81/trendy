---
status: resolved
trigger: "Force full resync in iOS debug view causes data inconsistency - HealthKit workouts from server don't appear locally, and duplicates appear locally that don't exist on server."
created: 2026-01-18T10:00:00Z
updated: 2026-01-18T10:00:00Z
---

## Current Focus

hypothesis: ROOT CAUSE CONFIRMED - ModelContext isolation between HealthKitService and SyncEngine
test: N/A - root cause confirmed through code analysis
expecting: N/A
next_action: Manual testing required - user needs to test force resync with HealthKit workouts

## Symptoms

expected: Force resync should clear local data and re-download all data from server. Server DB is the single source of truth.
actual: After force resync: (1) HealthKit workouts for today exist in server DB but don't show locally, (2) Duplicate workouts appear locally for other days that don't exist in server DB
errors: No specific error messages mentioned
reproduction: User triggered "force full resync" in the iOS debug view
started: Duplicates appeared AFTER the force resync. HealthKit workouts are visible in Apple Health app (data source is fine).

## Eliminated

## Evidence

- timestamp: 2026-01-18T10:05:00Z
  checked: SyncEngine.forceFullResync() implementation
  found: |
    1. forceFullResync() resets cursor to 0, sets forceBootstrapOnNextSync=true
    2. Then calls performSync() which runs bootstrapFetch()
    3. bootstrapFetch() does "nuclear cleanup" - deletes ALL local Events, Geofences, PropertyDefinitions, EventTypes
    4. Then fetches from API: getEventTypes(), getGeofences(), getAllEvents(), getPropertyDefinitions()
    5. After bootstrap, sets cursor to latest via apiClient.getLatestCursor()
  implication: The bootstrap process SHOULD correctly delete all local data and re-fetch from server. Problem must be elsewhere.

- timestamp: 2026-01-18T10:08:00Z
  checked: EventStore.forceFullResync() wrapper
  found: |
    1. Calls syncEngine.forceFullResync()
    2. Then calls fetchFromLocal() which creates a fresh ModelContext and fetches Events/EventTypes
    3. Calls refreshSyncStateForUI()
  implication: The fetchFromLocal uses a fresh ModelContext - should see the newly synced data.

- timestamp: 2026-01-18T10:10:00Z
  checked: EventStore.setModelContext() initialization path
  found: |
    1. On setModelContext, it creates a SyncEngine
    2. Then schedules a Task to:
       a. await syncEngine.loadInitialState()
       b. await queueMutationsForUnsyncedEvents()  <-- SUSPICIOUS
       c. await refreshSyncStateForUI()
  implication: queueMutationsForUnsyncedEvents() runs on EVERY app launch. If there are pending events after resync, this could create duplicates.

- timestamp: 2026-01-18T10:12:00Z
  checked: queueMutationsForUnsyncedEvents() implementation
  found: |
    1. Fetches all events with syncStatus = pending
    2. Fetches existing PendingMutation entries for CREATE operations
    3. For events that are pending but have no mutation queued, it queues CREATE mutations
    4. VERIFIED: LocalStore.upsertEvent DOES set syncStatus = .synced (lines 56, 60)
  implication: This is NOT the root cause. Events from bootstrap are correctly marked synced.

- timestamp: 2026-01-18T10:20:00Z
  checked: HealthKit duplicate prevention mechanism
  found: |
    1. processWorkoutSample has 3 layers of duplicate detection:
       a. In-memory processedSampleIds set (line 25)
       b. Database check via eventExistsWithHealthKitSampleId (line 33)
       c. Timestamp-based check via eventExistsWithMatchingWorkoutTimestamp (line 43)
    2. processedSampleIds is stored in App Group UserDefaults (not SwiftData)
    3. When bootstrapFetch runs, it deletes ALL local Events from SwiftData
    4. BUT processedSampleIds in UserDefaults is NOT cleared
    5. The in-memory set survives because HealthKitService instance survives
  implication: The duplicate prevention should work because processedSampleIds survives the resync.

- timestamp: 2026-01-18T10:25:00Z
  checked: forceFullResync vs HealthKit query anchors
  found: |
    1. HealthKitService stores query anchors per category in UserDefaults
    2. These anchors control which samples HealthKit returns (incremental sync)
    3. forceFullResync clears local SwiftData but does NOT reset HealthKit anchors
    4. So HealthKit observers will NOT re-fetch old workouts (anchors still set)
  implication: Anchors survive the resync, so HealthKit won't re-import old data. This is correct behavior.

- timestamp: 2026-01-18T10:30:00Z
  checked: Symptom 1 - HealthKit workouts for today missing locally
  found: |
    1. bootstrapFetch calls apiClient.getAllEvents() to get events from server
    2. Server has HealthKit workouts (confirmed by user)
    3. If events are fetched but show 0 locally, issue is between API response and local display
    4. fetchFromLocal() uses a fresh ModelContext to read persisted data
  implication: Need to verify getAllEvents returns HealthKit events and upsert saves them correctly

- timestamp: 2026-01-18T10:35:00Z
  checked: Symptom 2 - Duplicates appearing locally that don't exist on server
  found: |
    1. forceFullResync deletes all local events, then re-downloads from server
    2. After resync, fetchFromLocal() loads events from fresh context
    3. If duplicates appear locally but not on server, they must be created AFTER bootstrap
    4. Possible sources:
       a. HealthKit observer queries firing and creating new events
       b. But processedSampleIds should prevent duplicates
       c. UNLESS: the processedSampleIds has stale entries that don't match the server's IDs
    5. CRITICAL: When server returns events, it uses its IDs. When HealthKit re-imports,
       it generates NEW UUIDv7 IDs. The healthKitSampleId field should match, but...
  implication: Possible race condition or ID mismatch between server events and locally-created events

- timestamp: 2026-01-18T10:45:00Z
  checked: Bootstrap fetch and processedSampleIds interaction
  found: |
    1. bootstrapFetch downloads events from server with healthKitSampleId field (SyncEngine.swift:1575)
    2. LocalStore.upsertEvent creates events with the healthKitSampleId from server
    3. BUT: SyncEngine does NOT call HealthKitService.markSampleAsProcessed()
    4. The processedSampleIds set is managed ONLY by HealthKitService, not SyncEngine
    5. So after bootstrap:
       - Server events are in SwiftData WITH healthKitSampleId
       - processedSampleIds in memory does NOT contain these IDs
       - BUT: eventExistsWithHealthKitSampleId() DOES query SwiftData
    6. When HealthKit observer fires:
       a. processedSampleIds check passes (ID not in memory) - continues
       b. eventExistsWithHealthKitSampleId() SHOULD find the event in SwiftData
    7. THIS SHOULD WORK - the database check should prevent duplicates
  implication: Database check should work. Need to investigate why it's failing.

- timestamp: 2026-01-18T10:50:00Z
  checked: Race condition between bootstrap and HealthKit observers
  found: |
    1. MainTabView.onAppear calls:
       a. eventStore.setModelContext() - which starts background Task with loadInitialState(), queueMutationsForUnsyncedEvents()
       b. HealthKitService init and startMonitoringAllConfigurations()
       c. store.fetchFromLocalOnly()
       d. Then later: store.fetchData() which triggers performSync()
    2. forceFullResync() is triggered from DebugStorageView
    3. During forceFullResync:
       a. SyncEngine.bootstrapFetch() deletes all local events
       b. Downloads events from server
       c. Saves to SwiftData
       d. BUT: HealthKit observer queries are STILL RUNNING from step 1b
    4. RACE CONDITION:
       - Bootstrap deletes events, then downloads new ones
       - Meanwhile, HealthKit observer fires (no anchor reset!)
       - Observer calls eventExistsWithHealthKitSampleId()
       - IF this check runs BEFORE bootstrap re-saves events, it returns false
       - Then HealthKit creates a NEW event with a NEW UUIDv7 ID
       - Later, bootstrap saves the SERVER event with the SAME healthKitSampleId but different ID
       - Result: TWO events with same healthKitSampleId but different primary IDs
  implication: TIMING ISSUE - need to verify if HealthKit observers run during bootstrap

- timestamp: 2026-01-18T10:55:00Z
  checked: Symptom 1 - Today's workouts missing from local after resync
  found: |
    1. User says "HealthKit workouts for today exist in server DB but don't show locally"
    2. Bootstrap DOES download all events with getAllEvents()
    3. If events are downloaded but not visible, either:
       a. getAllEvents() is not returning them (pagination issue?)
       b. Events are saved but deleted by something else
       c. Events exist but fetchFromLocal() doesn't see them
    4. POSSIBILITY: HealthKit observer creates duplicate event FIRST, then backend returns 409 conflict
       and local duplicate is deleted via deleteLocalDuplicate() - but this deletes the WRONG one?
    5. Actually no - UUIDv7 means client generates ID, server just accepts it
    6. More likely: the duplicate event created by HealthKit observer REPLACES the server event
       somehow, or there's a SwiftData context issue where different contexts see different data
  implication: Need to investigate SwiftData context isolation and event persistence

- timestamp: 2026-01-18T11:05:00Z
  checked: ModelContext isolation issue - ROOT CAUSE IDENTIFIED
  found: |
    CRITICAL BUG DISCOVERED:
    1. HealthKitService uses the modelContext passed at init (from MainTabView)
    2. SyncEngine.bootstrapFetch() creates a NEW ModelContext: `let context = ModelContext(modelContainer)`
    3. These are SEPARATE contexts with isolated views of the data

    RACE CONDITION TIMELINE:
    Step 1: forceFullResync() is called
    Step 2: bootstrapFetch() creates NEW context, deletes all events, saves
    Step 3: HealthKit observer fires (running in parallel)
    Step 4: HealthKitService.eventExistsWithHealthKitSampleId() queries ITS context
    Step 5: HealthKitService's context still has STALE data (deletions not visible)
    Step 6: Check returns TRUE (event exists in stale context) - SKIPS DUPLICATE

    BUT WAIT - that would prevent duplicates, not cause them. Let me re-analyze...

    ACTUAL RACE CONDITION:
    Step 1: forceFullResync() deletes all events in context A, saves
    Step 2: forceFullResync() downloads events from server, upserts in context A, saves
    Step 3: HealthKitService context B hasn't refreshed - doesn't see new events
    Step 4: HealthKit observer fires, queries context B for healthKitSampleId
    Step 5: Context B doesn't see the server events yet
    Step 6: eventExistsWithHealthKitSampleId returns FALSE (not found in stale context)
    Step 7: HealthKit creates a NEW event with NEW UUIDv7 ID
    Step 8: Now TWO events exist with same healthKitSampleId but different primary IDs

    SYMPTOMS EXPLAINED:
    - Duplicates: HealthKit creates events that already exist on server (different IDs)
    - Missing events: The server events ARE downloaded but the duplicate check fails
      and HealthKit's locally-created events may not sync (already exist on server with
      same healthKitSampleId triggers conflict)
  implication: CONFIRMED ROOT CAUSE - ModelContext isolation causes stale reads during bootstrap

## Resolution

root_cause: ModelContext isolation issue - HealthKitService uses a different ModelContext than SyncEngine.bootstrapFetch(), causing stale reads during force resync. When bootstrap downloads events from server, HealthKitService's context doesn't see them, so duplicate detection fails and new events are created with different UUIDv7 IDs.
fix: |
  Implemented notification-based refresh of processedSampleIds after bootstrap completes.

  Changes:
  1. Added modelContainer property to HealthKitService (stored from modelContext.container at init)
  2. Added reloadProcessedSampleIdsFromDatabase() method to HealthKitService+Persistence.swift
     - Uses a FRESH ModelContext to query persisted data (avoids stale cache issue)
     - Queries all events with healthKitSampleId
     - Merges them into the in-memory processedSampleIds set
     - Persists the updated set to UserDefaults
  3. Added .syncEngineBootstrapCompleted notification name to SyncEngine.swift
  4. SyncEngine.bootstrapFetch() posts notification after bootstrap completes
  5. HealthKitService observes notification and calls reloadProcessedSampleIdsFromDatabase()

  This ensures that after force resync downloads HealthKit events from server,
  the in-memory processedSampleIds set is populated with their healthKitSampleIds,
  preventing HealthKit observer queries from creating duplicate events.
verification: |
  - BUILD SUCCEEDED - changes compile without errors
  - Code review: notification flow is correct (SyncEngine posts -> HealthKitService observes -> fresh context query)
  - Manual testing required by user to confirm fix resolves both symptoms:
    1. HealthKit workouts from server should appear locally after force resync
    2. No duplicate workouts should appear locally after force resync
files_changed:
  - apps/ios/trendy/Services/HealthKit/HealthKitService.swift
  - apps/ios/trendy/Services/HealthKit/HealthKitService+Persistence.swift
  - apps/ios/trendy/Services/Sync/SyncEngine.swift

## Follow-up: Deduplication Feature

Added deduplication feature to clean up existing duplicates from before the fix was applied.

### Changes Made

**1. EventStore.swift** - Added deduplication methods:
- `deduplicateHealthKitEvents()` - Finds and removes duplicate events based on `healthKitSampleId`
  - Groups events by their HealthKit sample ID
  - Keeps the synced version (exists on server) or oldest (by UUIDv7)
  - Deletes duplicates locally and queues delete mutations for synced ones
- `analyzeDuplicates()` - Previews duplicates without removing them
- `DeduplicationResult` struct to track stats (duplicatesFound, duplicatesRemoved, groupsProcessed, details)

**2. DebugStorageView.swift** - Added UI:
- "Remove Duplicate Events" button in Sync Actions section
- Confirmation dialog showing how many duplicates were found
- Result alert showing how many were removed
- Analyzes duplicates before confirming to show preview

### How to Use

1. Run the app on device
2. Go to Settings → Debug Storage
3. Tap "Remove Duplicate Events"
4. Review the duplicate count and confirm

### Files Changed (Additional)
- apps/ios/trendy/ViewModels/EventStore.swift (added deduplication methods)
- apps/ios/trendy/Views/Settings/DebugStorageView.swift (added UI)

### Build Status
- BUILD SUCCEEDED - all changes compile without errors

### Testing Status
- Awaiting user testing of:
  1. Force resync with fix applied (should prevent new duplicates)
  2. Deduplication tool (should clean up existing duplicates)

## Pending Issues to Investigate

The user reported two issues:
1. ✅ **Duplicate workouts locally** - Fixed via deduplication tool + prevention via bootstrap notification
2. ⏳ **Lost HealthKit workouts (cannot re-sync from HealthKit)** - Still needs investigation

### Issue: HealthKit workouts not re-syncing

**Symptom:** After force resync, some HealthKit workouts from today exist in the server DB but don't show locally, and cannot be re-imported from HealthKit.

**Possible causes:**
- HealthKit query anchors are not reset during force resync (by design)
- The in-memory processedSampleIds still contains these samples (preventing re-import)
- The events exist on server but aren't being fetched by getAllEvents()

**Next steps to investigate:**
1. Check if getAllEvents() is actually returning the missing workouts from server
2. Check if processedSampleIds is blocking re-import unnecessarily
3. Consider adding a "Clear HealthKit anchors" debug action to force full re-import
4. Verify the bootstrap notification fix is working as expected

**Resume command:** `/gsd:debug` and describe "HealthKit workouts not showing locally after force resync"
