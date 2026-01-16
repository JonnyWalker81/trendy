---
phase: 05-sync-engine
plan: 02
subsystem: sync
tags: [cleanup, reliability, captive-portal, swiftdata]
depends_on: []
provides:
  - QueuedOperation model removed from codebase
  - Captive portal detection in SyncEngine
affects:
  - Future sync operations will be more reliable
tech-stack:
  added: []
  patterns:
    - Health check before sync for connectivity verification
key-files:
  created: []
  modified:
    - apps/ios/trendy/trendyApp.swift
    - apps/ios/trendy/Models/Migration/SchemaV2.swift
    - apps/ios/trendy/Services/Sync/SyncEngine.swift
  deleted:
    - apps/ios/trendy/Models/QueuedOperation.swift
decisions:
  - decision: "Use getEventTypes() for health check"
    rationale: "Always returns data if connected (users have default types), lightweight payload"
  - decision: "Health check before isSyncing guard"
    rationale: "Prevents unnecessary state changes when connectivity is unavailable"
  - decision: "Keep QueuedOperationV1 in SchemaV1"
    rationale: "Required for users migrating from V1 schema"
metrics:
  duration: "5 min"
  completed: "2026-01-16"
---

# Phase 05 Plan 02: Sync Cleanup and Hardening Summary

**One-liner:** Removed deprecated QueuedOperation model and added captive portal detection via health check before sync.

## What Was Built

### Task 1: Remove QueuedOperation from schema
- Deleted `apps/ios/trendy/Models/QueuedOperation.swift` entirely
- Removed `QueuedOperation.self` from SwiftData schema in `trendyApp.swift`
- Removed from `SchemaV2.swift` models list
- Removed schema validation check for QueuedOperation
- Kept `QueuedOperationV1` in `SchemaV1.swift` for migration support

### Task 2: Add captive portal detection
- Added `performHealthCheck()` method to SyncEngine
- Uses `getEventTypes()` API call to verify actual connectivity
- Integrated into `performSync()` before the sync starts
- Gracefully skips sync with clear logging when health check fails

### Task 3: Update DebugStorageView
- Already completed in previous session (Queued Operations row removed)
- No additional changes needed

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Use getEventTypes() for health check | Always returns data if connected; lightweight; empty response indicates problem |
| Health check before isSyncing guard | No point setting syncing state if we can't connect |
| Keep QueuedOperationV1 in SchemaV1 | Required for V1->V2 migration support |

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

1. **Build:** SUCCESS - `xcodebuild` completed without errors
2. **QueuedOperation grep:** Only comments and SchemaV1 references remain (intentional)
3. **Health check integration:** `performHealthCheck` called in `performSync` before any sync operations

## Technical Notes

### Health Check Implementation
```swift
private func performHealthCheck() async -> Bool {
    do {
        let types = try await apiClient.getEventTypes()
        Log.sync.debug("Health check passed", context: .with { ctx in
            ctx.add("event_types_count", types.count)
        })
        return true
    } catch {
        Log.sync.warning("Health check failed - likely captive portal or no connectivity", ...)
        return false
    }
}
```

### Why getEventTypes() vs other endpoints
- `getChanges(limit: 0)` returns empty array even with valid connection - not a reliable signal
- `getEventTypes()` always returns data (users have default types) if connectivity works
- Both are lightweight, but getEventTypes provides more reliable signal

## Commits

| Hash | Type | Description |
|------|------|-------------|
| c3a05d8 | chore | Remove deprecated QueuedOperation model |
| 4a3543b | feat | Add captive portal detection to SyncEngine |

## Files Changed

| File | Change |
|------|--------|
| `apps/ios/trendy/Models/QueuedOperation.swift` | Deleted |
| `apps/ios/trendy/trendyApp.swift` | Removed QueuedOperation from schema |
| `apps/ios/trendy/Models/Migration/SchemaV2.swift` | Removed QueuedOperation from models |
| `apps/ios/trendy/Services/Sync/SyncEngine.swift` | Added health check method and integration |

## Next Phase Readiness

Phase 05-02 complete. Ready for next plan in phase.
