---
phase: 05-sync-engine
verified: 2026-01-16T16:00:00Z
status: gaps_found
score: 2/4 must-haves verified
gaps:
  - truth: "Pending mutations survive app restart"
    status: failed
    reason: "Mutation queueing is async AFTER local save - force quit between save and queueMutation loses the mutation. SyncEngine doesn't load pendingCount on init so banner never shows on restart."
    artifacts:
      - path: "apps/ios/trendy/ViewModels/EventStore.swift"
        issue: "recordEvent() saves locally (line 499), then AFTER save queues mutation async (lines 524-529). Force quit between these operations loses the mutation."
      - path: "apps/ios/trendy/Services/Sync/SyncEngine.swift"
        issue: "init() does not load existing PendingMutation count - pendingCount starts at 0 and only updates after queueMutation or sync operations"
    missing:
      - "Transactional save: mutation queue entry must be persisted IN SAME transaction as entity save (or before)"
      - "Load pendingCount from SwiftData in SyncEngine.init() or on first access"
      - "Automatic sync on app launch to process any pending mutations"
  - truth: "Offline changes automatically sync when network returns"
    status: partial
    reason: "Delete mutations queued but deleted events reappear after app restart due to missing persistence and in-session-only resurrection prevention"
    artifacts:
      - path: "apps/ios/trendy/ViewModels/EventStore.swift"
        issue: "deleteEvent() queues delete mutation correctly (lines 625-636), but if app is killed before sync completes, the mutation may be lost due to same async timing issue as creates"
      - path: "apps/ios/trendy/Services/Sync/SyncEngine.swift"
        issue: "pendingDeleteIds is in-memory Set<String> (line 68) - cleared on restart. Resurrection prevention only works within session."
    missing:
      - "Persist pendingDeleteIds in UserDefaults or SwiftData to survive restarts"
      - "Load pendingDeleteIds on SyncEngine init"
      - "Or: alternative approach - check PendingMutation table for delete operations during pullChanges"
---

# Phase 5: Sync Engine Verification Report

**Phase Goal:** Reliable offline-first sync that never loses data
**Verified:** 2026-01-16
**Status:** gaps_found
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can create/edit/delete events while offline without errors | VERIFIED | recordEvent(), updateEvent(), deleteEvent() all work offline - events saved locally with syncStatus: .pending |
| 2 | Offline changes automatically sync when network returns | PARTIAL | handleNetworkRestored() calls performSync(), but delete mutations have resurrection bug |
| 3 | Pending mutations persist across app restarts | FAILED | Human testing: Create event offline, kill app, relaunch - no pending banner, mutation lost |
| 4 | User can see sync state (pending count, last sync time) | VERIFIED | currentSyncState, currentPendingCount, currentLastSyncTime properties wired to SyncStatusBanner |

**Score:** 2/4 truths verified (Tests 1 and 4 pass, Tests 3 and 5 fail, Test 2 partial)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `apps/ios/trendy/Services/Sync/SyncEngine.swift` | Mutation queue management, pendingCount tracking, lastSyncTime | EXISTS+SUBSTANTIVE | 1306 lines, comprehensive sync logic, BUT init doesn't load pending count |
| `apps/ios/trendy/ViewModels/EventStore.swift` | CRUD operations queue mutations, cached sync state | EXISTS+SUBSTANTIVE | 1411 lines, full CRUD with mutation queueing, BUT mutation queue is AFTER save not transactional |
| `apps/ios/trendy/Views/Components/SyncStatusBanner.swift` | Display sync state with relative time | EXISTS+WIRED | Shows pending count, last sync time, syncing state |
| `apps/ios/trendy/Views/List/EventListView.swift` | Live sync state binding | EXISTS+WIRED | Uses eventStore.currentSyncState, currentPendingCount, currentLastSyncTime |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| EventStore.recordEvent | SyncEngine.queueMutation | try await syncEngine.queueMutation() | WIRED but TIMING_BUG | Mutation queued AFTER save - not atomic |
| SyncEngine.init | pendingCount | @MainActor var pendingCount: Int = 0 | NOT_LOADED | Starts at 0, doesn't query SwiftData |
| EventStore.setModelContext | refreshSyncStateForUI | Task { await refreshSyncStateForUI() } | WIRED | But refreshSyncStateForUI reads from SyncEngine which hasn't loaded count |
| SyncEngine.pendingDeleteIds | pullChanges resurrection prevention | if pendingDeleteIds.contains() skip | IN_SESSION_ONLY | Set is in-memory, lost on restart |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| SYNC-01: Offline CRUD | SATISFIED | Events saved locally, mutations queued |
| SYNC-02: Auto-sync on network restore | PARTIAL | Deletes reappear after restart |
| SYNC-03: Mutation persistence | BLOCKED | Mutations lost on force quit; pendingCount not loaded on init |
| SYNC-04: Sync state visibility | SATISFIED | UI shows pending count, last sync time, error state |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| EventStore.swift | 499-529 | Save then queue async | BLOCKER | Force quit loses mutation |
| SyncEngine.swift | 64 | pendingCount: Int = 0 | BLOCKER | Banner never shows on restart |
| SyncEngine.swift | 68 | pendingDeleteIds: Set<String> = [] | BLOCKER | Delete resurrection after restart |

### Human Verification Results

Human testing revealed these specific failures:

**Test 4 (Mutation Persistence) - FAILED:**
1. Enable Airplane Mode
2. Create event offline - event appears, banner shows pending
3. Force quit app (swipe up from app switcher)
4. Relaunch app
5. **Actual:** No pending banner shows
6. **Expected:** "1 pending change" banner should show

**Test 5 (Edit/Delete Offline) - FAILED:**
1. Enable Airplane Mode
2. Edit an existing event (change notes) - works
3. Delete a different event - disappears from UI
4. Force quit app
5. Relaunch app
6. **Actual:** Offline-created event didn't sync (no mutation), deleted event reappears
7. **Expected:** Edit should persist, deleted event should stay deleted

### Root Cause Analysis

**Gap 1: Mutation queueing timing**

```swift
// EventStore.recordEvent() lines 498-535
do {
    try modelContext.save()  // (1) Event saved to SwiftData
    reloadWidgets()
    
    // --- FORCE QUIT HERE LOSES MUTATION ---
    
    if let syncEngine = syncEngine {
        let payload = try JSONEncoder().encode(request)
        try await syncEngine.queueMutation(...)  // (2) Mutation queued AFTER
    }
}
```

The save and queueMutation are not atomic. A force quit between (1) and (2) results in an event that exists locally but has no corresponding PendingMutation to sync it.

**Gap 2: pendingCount not loaded on init**

```swift
// SyncEngine.swift line 64
@MainActor public private(set) var pendingCount: Int = 0  // Starts at 0

// SyncEngine.init() lines 80-94 - only loads cursor, not pending count
init(apiClient: APIClient, modelContainer: ModelContainer) {
    self.lastSyncCursor = Int64(UserDefaults.standard.integer(forKey: cursorKeyValue))
    // NO: let count = fetchPendingMutationCount()
}
```

The SyncEngine never queries SwiftData for existing PendingMutation records on startup.

**Gap 3: Resurrection prevention is session-only**

```swift
// SyncEngine.swift line 68
private var pendingDeleteIds: Set<String> = []  // In-memory only

// Line 828 - only prevents resurrection if ID was captured THIS session
if pendingDeleteIds.contains(change.entityId) {
    Log.sync.debug("Skipping resurrection of pending-delete entity")
    return
}
```

If app restarts, pendingDeleteIds is empty. When pullChanges runs, deleted events get recreated because the change_log has CREATE entries for them and we have no memory of the pending DELETE.

### Gaps Summary

Two critical gaps block the phase goal "Reliable offline-first sync that **never loses data**":

1. **Mutation atomicity:** Mutations must be queued in the same transaction as (or before) entity saves. Currently, force quit between save and queueMutation loses the mutation, violating "never loses data."

2. **State persistence:** SyncEngine must load existing pendingCount and pendingDeleteIds on init. Currently, app restart loses awareness of pending mutations, violating both "sync state visibility" and "deletes stick."

These require code changes before the phase goal can be verified as achieved.

---

*Verified: 2026-01-16*
*Verifier: Claude (gsd-verifier)*
*Human verification by: User*
