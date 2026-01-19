---
status: resolved
trigger: "iOS app shows duplicate workout events - same 'Workout' event appearing 5+ times with identical timestamps"
created: 2026-01-18T12:45:00Z
updated: 2026-01-18T15:30:00Z
resolved: 2026-01-18T15:30:00Z
---

## Current Focus

hypothesis: CONFIRMED - Race condition in HealthKit sample processing
test: Applied fix by adding early sampleId claim before async operations
expecting: No new duplicates will be created
next_action: CHECK DATABASE FOR DUPLICATES using Supabase CLI

## Database Verification (2026-01-18)

**Checked via Supabase MCP:**
- Production (cwxghazeohicindcznhx): ✅ No duplicate healthkit_sample_ids
- Dev (vhfofrwzadzcguyyvvip): ✅ No duplicate healthkit_sample_ids

**Conclusion:** Duplicates are iOS-local only (SwiftData). Backend is clean.

**Fix Applied (prevents NEW duplicates):**
- HealthKitService+WorkoutProcessing.swift: Early sampleId claim before async
- HealthKitService+CategoryProcessing.swift: Same fix for mindfulness/water
- SyncEngine.swift: Deduplication check in queueMutation()

**User Action Required:**
Use "Force Full Resync" in iOS Settings to clear local duplicates and resync from server.

## Symptoms

expected: Each workout event should appear once in the event list
actual: Same workout events appearing 5+ times with identical timestamps (12:28 PM, 12:17 PM, 9:32 AM)
errors: No explicit errors shown, but "10 pending changes" and "1 pending change" indicators visible
reproduction: Visible in iOS app event list - duplicates appear with same timestamp and same "Auto-logged" notes
started: Unknown when started, but appears to be recent based on today's date (Jan 18, 2026)

## Eliminated

## Evidence

- timestamp: 2026-01-18T13:00:00Z
  checked: SyncEngine.queueMutation()
  found: Does NOT check for existing mutations before inserting
  implication: Multiple mutations can be queued for same event

- timestamp: 2026-01-18T13:10:00Z
  checked: Event model @Attribute(.unique)
  found: Unique constraint is on 'id' field only, not healthKitSampleId
  implication: Two events with same healthKitSampleId but different UUIDs can both be inserted

- timestamp: 2026-01-18T13:20:00Z
  checked: processWorkoutSample race condition
  found: In-memory check (processedSampleIds) and DB check (eventExistsWithHealthKitSampleId) both happen BEFORE event creation
  implication: Race condition window where two concurrent calls both pass checks before either saves

- timestamp: 2026-01-18T13:25:00Z
  checked: Event init
  found: Event init generates NEW UUIDv7 with each call: id: String = UUIDv7.generate()
  implication: Two events for same workout get DIFFERENT IDs, bypassing unique constraint

## Resolution

root_cause: Race condition in HealthKit workout processing - HKObserverQuery can fire multiple times rapidly (e.g., app foreground + background delivery). When two concurrent processWorkoutSample calls process the same workout, both pass the duplicate checks (in-memory processedSampleIds and DB eventExistsWithHealthKitSampleId) before either creates the event. Each call generates a new UUIDv7, so both events insert successfully despite having the same healthKitSampleId.

fix: |
  1. Modified processWorkoutSample() to insert sampleId into processedSampleIds IMMEDIATELY after the guard check, BEFORE any async operations. This acts as a synchronous mutex.
  2. Applied same fix to processMindfulnessSample() and processWaterSample()
  3. Added deduplication to SyncEngine.queueMutation() to prevent duplicate mutations for same entity

verification: ✅ Build SUCCEEDED - ready for testing
files_changed:
  - apps/ios/trendy/Services/HealthKit/HealthKitService+WorkoutProcessing.swift
  - apps/ios/trendy/Services/HealthKit/HealthKitService+CategoryProcessing.swift
  - apps/ios/trendy/Services/Sync/SyncEngine.swift
