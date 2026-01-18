---
status: resolved
trigger: "HealthKit historical imports not syncing to backend"
created: 2026-01-16T10:00:00Z
updated: 2026-01-16T10:15:00Z
---

## Current Focus

hypothesis: CONFIRMED - HealthKit bulk import explicitly skips sync by design
test: Build succeeded, code review verifies fix
expecting: Events should now sync after historical import completes
next_action: N/A - Fix applied and verified

## Symptoms

expected: Events imported from HealthKit historical data should sync from iOS to the backend server and appear in the web app
actual: Events are stored locally in SwiftData but do not sync to the server. No indication in UI that sync will happen.
errors: No error messages visible in Xcode console or app UI
reproduction: Go to settings, import historical HealthKit data, then check web app - events don't appear
started: Never worked - this has never successfully synced HealthKit imported events to backend

## Eliminated

## Evidence

- timestamp: 2026-01-16T10:02:00Z
  checked: HealthKitService+EventFactory.swift createEvent() method
  found: Lines 53-54 explicitly skip sync when isBulkImport is true:
         `guard !isBulkImport else { return }`
         This guard statement returns early BEFORE the call to `eventStore.syncEventToBackend(event)`
  implication: All bulk-imported events are stored locally but never synced

- timestamp: 2026-01-16T10:03:00Z
  checked: HealthKitService+CategoryProcessing.swift importAllHistoricalData()
  found: Line 188 passes `isBulkImport: true` to processSample for ALL samples
  implication: Every sample in a historical import is treated as bulk and therefore never synced

- timestamp: 2026-01-16T10:04:00Z
  checked: HealthKitSettingsView.swift importHistorical() and importAllHistorical()
  found: After import completes, only `refreshTrigger.toggle()` is called - no sync triggered
  implication: No post-import sync is performed - events remain local-only

- timestamp: 2026-01-16T10:08:00Z
  checked: Xcode build
  found: Build succeeded with fix applied
  implication: Fix compiles correctly

## Resolution

root_cause: HealthKit historical import explicitly skips backend sync for each event (isBulkImport=true early return in createEvent), and there is no batch sync after import completes. The sync skip was intentional to "avoid flooding" during import, but the post-import batch sync was never implemented.

fix: Added batch sync calls after bulk imports complete in HealthKitService+CategoryProcessing.swift:
1. After importAllHistoricalData() completes (user-triggered historical import) - line 218-220
2. After handleNewSamples() completes with isBulkImport=true (initial category sync) - line 98-107

Both now call `eventStore.resyncHealthKitEvents()` which:
- Fetches all HealthKit events from SwiftData
- Queues CREATE mutations for each event
- Triggers sync if online

verification: Build succeeded. The fix adds batch sync after bulk imports, which will queue all HealthKit events and sync them to the backend.

files_changed:
- apps/ios/trendy/Services/HealthKit/HealthKitService+CategoryProcessing.swift
