# Phase 2: HealthKit Reliability - Research

**Researched:** 2026-01-16
**Domain:** iOS HealthKit background delivery, incremental data fetching, server-side deduplication
**Confidence:** HIGH (retroactive documentation of implemented patterns)
**Type:** Retroactive research - documenting patterns learned during implementation

## Summary

This document captures the patterns, decisions, and lessons learned during Phase 2 implementation. The phase successfully established reliable background delivery for HealthKit data with proper anchor persistence, freshness indicators, and server-side deduplication.

**Key accomplishments:**
1. HKQueryAnchor persistence via NSKeyedArchiver to App Group UserDefaults enables incremental fetching that survives app restarts
2. HKObserverQuery with proper completionHandler pattern ensures iOS does not terminate the app during background delivery
3. Per-category freshness timestamps give users visibility into data synchronization status
4. Server-side upsert pattern with healthkit_sample_id ensures idempotent event creation

**Primary insight:** The critical pattern for HealthKit background delivery is calling `completionHandler()` in ALL code paths of the HKObserverQuery callback. Failing to do so causes iOS to terminate the app.

## Standard Stack

The established libraries/tools used for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| HealthKit | iOS 17+ | Health data access | Apple's only API for health data |
| HKObserverQuery | iOS 8+ | Background change notifications | Required for background delivery |
| HKAnchoredObjectQuery | iOS 8+ | Incremental data fetching | Returns only new samples since anchor |
| NSKeyedArchiver | Foundation | Anchor serialization | HKQueryAnchor conforms to NSSecureCoding |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| App Group UserDefaults | iOS 8+ | Cross-reinstall persistence | Anchors, settings that must survive reinstalls |
| RelativeDateTimeFormatter | iOS 13+ | Human-readable time display | "5 min ago", "Yesterday" formatting |
| HKStatisticsQuery | iOS 8+ | Aggregated data (steps, calories) | Daily totals instead of raw samples |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| App Group UserDefaults | Keychain | More secure but complex setup; overkill for anchors |
| NSKeyedArchiver | Codable | HKQueryAnchor doesn't conform to Codable |
| HKAnchoredObjectQuery | HKSampleQuery | Sample query re-fetches all data, no incremental support |

## Architecture Patterns

### Data Flow
```
┌─────────────────────────┐
│     iOS HealthKit       │
└───────────┬─────────────┘
            │ HKObserverQuery callback
            ▼
┌─────────────────────────┐
│   HealthKitService      │
│  - Observer queries     │
│  - Anchor persistence   │
│  - Timestamp tracking   │
└───────────┬─────────────┘
            │ HKAnchoredObjectQuery
            ▼
┌─────────────────────────┐
│   Sample Processing     │
│  - Dedupe check         │
│  - Event creation       │
└───────────┬─────────────┘
            │ healthKitSampleId
            ▼
┌─────────────────────────┐
│    Backend API          │
│  - UpsertHealthKitEvent │
│  - Partial unique index │
└─────────────────────────┘
```

### Pattern 1: HKObserverQuery with Mandatory completionHandler

**What:** Background delivery query that notifies when HealthKit data changes
**When to use:** Always for background delivery of any HealthKit type
**Critical rule:** completionHandler() MUST be called in ALL code paths

**Example from implementation (HealthKitService.swift lines 426-449):**
```swift
// Source: apps/ios/trendy/Services/HealthKitService.swift
let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
    guard let self = self else {
        completionHandler()  // CRITICAL: Call even when self is nil
        return
    }

    if let error = error {
        Log.healthKit.error("Observer query error", error: error, context: .with { ctx in
            ctx.add("category", category.displayName)
        })
        completionHandler()  // CRITICAL: Call on error path
        return
    }

    Log.healthKit.debug("Update received", context: .with { ctx in
        ctx.add("category", category.displayName)
    })

    // Process new samples
    Task {
        await self.handleNewSamples(for: category)
    }

    completionHandler()  // CRITICAL: Call on success path
}
```

### Pattern 2: HKQueryAnchor Persistence via NSKeyedArchiver

**What:** Serialize HKQueryAnchor to Data for UserDefaults storage
**When to use:** After each successful HKAnchoredObjectQuery to enable incremental fetching
**Why:** HKQueryAnchor conforms to NSSecureCoding, making NSKeyedArchiver the correct serialization method

**Example from implementation (HealthKitService.swift lines 1622-1656):**
```swift
// Source: apps/ios/trendy/Services/HealthKitService.swift
/// Save anchor for a category to persistent storage
private func saveAnchor(_ anchor: HKQueryAnchor, for category: HealthDataCategory) {
    do {
        let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        Self.sharedDefaults.set(data, forKey: "\(queryAnchorKeyPrefix)\(category.rawValue)")
        Log.healthKit.debug("Saved anchor", context: .with { ctx in
            ctx.add("category", category.displayName)
        })
    } catch {
        Log.healthKit.error("Failed to archive anchor", error: error, context: .with { ctx in
            ctx.add("category", category.displayName)
        })
    }
}

/// Load anchor for a category from persistent storage
private func loadAnchor(for category: HealthDataCategory) -> HKQueryAnchor? {
    guard let data = Self.sharedDefaults.data(forKey: "\(queryAnchorKeyPrefix)\(category.rawValue)") else {
        return nil
    }
    do {
        let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        return anchor
    } catch {
        Log.healthKit.error("Failed to unarchive anchor", error: error, context: .with { ctx in
            ctx.add("category", category.displayName)
        })
        return nil
    }
}
```

### Pattern 3: HKAnchoredObjectQuery for Incremental Fetching

**What:** Query that returns only samples added since the last anchor
**When to use:** When processing HKObserverQuery notifications to get new data
**Key insight:** Pass nil anchor on first query to get all data, then persist new anchor

**Example from implementation (HealthKitService.swift lines 521-575):**
```swift
// Source: apps/ios/trendy/Services/HealthKitService.swift
@MainActor
private func handleNewSamples(for category: HealthDataCategory) async {
    guard let sampleType = category.hkSampleType else { return }

    // Get current anchor (may be nil for first query)
    let currentAnchor = queryAnchors[category]

    // Execute anchored query
    let (samples, newAnchor) = await withCheckedContinuation { (continuation: CheckedContinuation<([HKSample], HKQueryAnchor?), Never>) in
        let query = HKAnchoredObjectQuery(
            type: sampleType,
            predicate: nil,
            anchor: currentAnchor,
            limit: HKObjectQueryNoLimit
        ) { _, addedSamples, _, newAnchor, error in
            if let error = error {
                Log.healthKit.error("Anchored query error", error: error, context: .with { ctx in
                    ctx.add("category", category.displayName)
                })
                continuation.resume(returning: ([], nil))
                return
            }
            continuation.resume(returning: (addedSamples ?? [], newAnchor))
        }
        healthStore.execute(query)
    }

    // Update and persist anchor if we got new samples or a new anchor
    if let newAnchor = newAnchor {
        queryAnchors[category] = newAnchor
        saveAnchor(newAnchor, for: category)
    }

    // Process only truly new samples
    for sample in samples {
        await processSample(sample, category: category, isBulkImport: currentAnchor == nil)
    }

    // Record update time for freshness display
    if !samples.isEmpty {
        recordCategoryUpdate(for: category)
    }
}
```

### Pattern 4: Server-Side Upsert with Partial Unique Index

**What:** Database constraint that ensures idempotent event creation for HealthKit data
**When to use:** When syncing HealthKit data to server to prevent duplicates
**Why partial index:** HealthKit events need sample ID uniqueness, while manual events use timestamp uniqueness

**Example from implementation (supabase/migrations/20251227000000_add_healthkit_dedupe.sql):**
```sql
-- Source: supabase/migrations/20251227000000_add_healthkit_dedupe.sql
-- Partial unique index for HealthKit deduplication
CREATE UNIQUE INDEX IF NOT EXISTS idx_events_healthkit_dedupe
ON public.events (user_id, healthkit_sample_id)
WHERE source_type = 'healthkit' AND healthkit_sample_id IS NOT NULL;

-- Partial unique index for non-HealthKit events (manual/imported)
CREATE UNIQUE INDEX IF NOT EXISTS idx_events_manual_dedupe
ON public.events (user_id, event_type_id, timestamp)
WHERE source_type != 'healthkit';
```

### Anti-Patterns to Avoid

- **Forgetting completionHandler():** If you don't call completionHandler() in the HKObserverQuery callback, iOS will terminate your app after a timeout. This is the #1 cause of background delivery failures.

- **Using HKSampleQuery for background updates:** HKSampleQuery fetches ALL matching samples every time. Use HKAnchoredObjectQuery for incremental fetching.

- **Storing anchors in standard UserDefaults:** Standard UserDefaults can be cleared on app reinstall. Use App Group UserDefaults for data that must persist.

- **Using Codable for HKQueryAnchor:** HKQueryAnchor does not conform to Codable. You must use NSKeyedArchiver/NSKeyedUnarchiver.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Relative time formatting | Custom date math | RelativeDateTimeFormatter | Handles localization, edge cases automatically |
| Anchor serialization | Custom encoding | NSKeyedArchiver | HKQueryAnchor conforms to NSSecureCoding |
| Background delivery | BGTaskScheduler | HKObserverQuery + enableBackgroundDelivery | HealthKit has its own background system |
| Daily aggregation | Sum raw samples | HKStatisticsQuery | Handles timezones, data sources correctly |
| Deduplication | Check-then-insert | Partial unique index + upsert | Race condition safe |

**Key insight:** HealthKit has its own APIs for everything - don't try to build workarounds with generic iOS APIs.

## Common Pitfalls

### Pitfall 1: completionHandler() Not Called

**What goes wrong:** iOS terminates app during background delivery
**Why it happens:** Developers forget to call completionHandler() in error paths or early returns
**How to avoid:** Put completionHandler() call at the BEGINNING of every early return

```swift
// WRONG - easy to forget
if let error = error {
    // log error
    return  // OOPS! completionHandler not called
}

// RIGHT - call first, then return
if let error = error {
    completionHandler()
    // log error
    return
}
```

**Warning signs:** Background delivery works initially but stops after hours

### Pitfall 2: First Query Returns All Data

**What goes wrong:** On first launch, app processes entire HealthKit history
**Why it happens:** nil anchor means "return all samples"
**How to avoid:** Detect bulk import (currentAnchor == nil) and handle differently:
- Skip notifications for bulk imports
- Consider skipping server sync for very old data
- Process in batches to avoid memory issues

**Warning signs:** App hangs on first launch with large HealthKit history

### Pitfall 3: enableBackgroundDelivery Not Called

**What goes wrong:** Observer query works in foreground but not background
**Why it happens:** Developers set up HKObserverQuery but forget enableBackgroundDelivery
**How to avoid:** Call enableBackgroundDelivery immediately after setting up observer query

```swift
healthStore.execute(query)
observerQueries[category] = query

// Enable background delivery immediately after
do {
    try await healthStore.enableBackgroundDelivery(for: sampleType, frequency: category.backgroundDeliveryFrequency)
} catch {
    // Log but continue - foreground delivery still works
}
```

**Warning signs:** HealthKit sync only happens when app is open

### Pitfall 4: Anchor Not Persisted

**What goes wrong:** App re-processes all data after restart
**Why it happens:** Anchor saved to memory-only dictionary
**How to avoid:** Save anchor to persistent storage (App Group UserDefaults) after every query

**Warning signs:** Duplicate events created after app restart

### Pitfall 5: Wrong Deduplication Strategy

**What goes wrong:** Duplicate events or missing updates
**Why it happens:** Using timestamp for HealthKit deduplication
**How to avoid:** Use healthkit_sample_id (UUID from HKSample) as dedupe key

```swift
// Each HKSample has a unique UUID
let sampleId = sample.uuid.uuidString
```

**Warning signs:** Same workout appears multiple times, or edited workout creates duplicate

## Code Examples

### Example 1: Full Observer Query Setup

```swift
// Source: apps/ios/trendy/Services/HealthKitService.swift lines 420-466
@MainActor
private func startObserverQuery(for category: HealthDataCategory, sampleType: HKSampleType) async {
    guard observerQueries[category] == nil else { return }

    let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
        guard let self = self else {
            completionHandler()
            return
        }

        if let error = error {
            Log.healthKit.error("Observer query error", error: error, context: .with { ctx in
                ctx.add("category", category.displayName)
            })
            completionHandler()
            return
        }

        Task {
            await self.handleNewSamples(for: category)
        }

        completionHandler()
    }

    healthStore.execute(query)
    observerQueries[category] = query

    do {
        try await enableBackgroundDelivery(for: category)
    } catch {
        // Logged in enableBackgroundDelivery
    }
}
```

### Example 2: Freshness Indicator Display

```swift
// Source: apps/ios/trendy/Views/HealthKit/HealthKitSettingsView.swift lines 329-371
private func formatRelativeTime(_ date: Date?) -> String {
    guard let date = date else { return "Never" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

// In category row view:
if let lastUpdate = healthKitService?.lastUpdateTime(for: category) {
    Text("Updated \(formatRelativeTime(lastUpdate))")
        .font(.caption)
        .foregroundStyle(.secondary)
} else {
    Text("Not yet updated")
        .font(.caption)
        .foregroundStyle(.orange)
}
```

### Example 3: Server Upsert Pattern

```swift
// Source: apps/backend/internal/repository/event.go lines 395-465
func (r *eventRepository) UpsertHealthKitEvent(ctx context.Context, event *models.Event) (*models.Event, bool, error) {
    if event.HealthKitSampleID == nil || *event.HealthKitSampleID == "" {
        return nil, false, fmt.Errorf("healthkit_sample_id is required for upsert")
    }

    // Check if event already exists
    existingEvents, err := r.GetByHealthKitSampleIDs(ctx, event.UserID, []string{*event.HealthKitSampleID})
    if err != nil {
        return nil, false, fmt.Errorf("failed to check existing event: %w", err)
    }

    if len(existingEvents) == 0 {
        // INSERT: No existing event, create new one
        body, err = r.client.Insert("events", data)
    } else {
        // UPDATE: Event already exists, update by ID
        existingID := existingEvents[0].ID
        body, err = r.client.Update("events", existingID, data)
    }

    wasCreated := len(existingEvents) == 0
    return &events[0], wasCreated, nil
}
```

## Key Decisions

### Decision 1: App Group UserDefaults for Anchor Storage

**Choice:** Use App Group UserDefaults instead of standard UserDefaults or Keychain
**Rationale:**
- Anchors need to survive app reinstalls (standard UserDefaults does not)
- Keychain is overkill for non-sensitive data
- App Group enables future sharing with extensions (e.g., widget)

### Decision 2: NSKeyedArchiver for HKQueryAnchor

**Choice:** Use NSKeyedArchiver with requiringSecureCoding: true
**Rationale:**
- HKQueryAnchor conforms to NSSecureCoding, not Codable
- requiringSecureCoding: true is required for secure unarchiving
- Apple's recommended serialization pattern for HealthKit objects

### Decision 3: Per-Category Timestamps

**Choice:** Track lastUpdateTime per HealthDataCategory, not per query
**Rationale:**
- Users care about "when was my step data last synced", not individual query times
- Simpler mental model for debugging
- Aligns with how the settings UI is organized

### Decision 4: Partial Unique Index for Deduplication

**Choice:** Use separate partial indexes for HealthKit vs manual events
**Rationale:**
- HealthKit events need sample ID uniqueness (workouts can start at same second)
- Manual events need timestamp uniqueness (user expectation)
- Partial indexes allow both constraints to coexist

### Decision 5: Oldest Category Update in Dashboard

**Choice:** Show oldest update time rather than newest or average
**Rationale:**
- Users want to know if ANY data is stale
- Oldest time reveals the worst-case staleness
- Simple one-line display vs per-category list

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| HKSampleQuery + time predicate | HKAnchoredObjectQuery | iOS 8+ | Incremental fetching, no duplicates |
| Standard UserDefaults | App Group UserDefaults | iOS 8+ | Survives reinstalls |
| Codable serialization attempt | NSKeyedArchiver | N/A | HKQueryAnchor only supports NSCoding |

**Current best practices (verified 2025-2026):**
- HKObserverQuery + enableBackgroundDelivery is the correct pattern for background updates
- HKAnchoredObjectQuery is Apple's recommended incremental fetching mechanism
- NSKeyedArchiver with requiringSecureCoding: true is required for HKQueryAnchor serialization

## Future Considerations

### Improvements to Investigate

1. **HKAnchoredObjectQueryDescriptor (iOS 15+):** Swift concurrency-based alternative to callback-based API. Would simplify async/await code.

2. **watchOS support:** The same patterns work on watchOS, but background delivery has additional budget constraints.

3. **Background app refresh fallback:** When background delivery stops (iOS timing constraints), BGTaskScheduler could provide a fallback.

4. **Differential sync:** Currently we send full event data on upsert. Could optimize to send only changed fields.

5. **Conflict resolution:** Currently last-write-wins. Could implement more sophisticated conflict resolution for multi-device scenarios.

### Known Limitations

1. **Background delivery timing:** iOS controls when background delivery happens (1-60 min backgrounded, up to 4 hours terminated). Cannot be made faster.

2. **Read authorization opacity:** HealthKit does not report read authorization status for privacy. We track "authorization requested" but not "authorization granted".

3. **Anchor invalidation:** Apple can invalidate anchors (e.g., HealthKit database reset). Need to handle nil anchor gracefully.

## Sources

### Primary (HIGH confidence)
- [Apple Developer Documentation: HKObserverQuery](https://developer.apple.com/documentation/healthkit/hkobserverquery)
- [Apple Developer Documentation: HKAnchoredObjectQuery](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery)
- [Apple Developer Documentation: HKQueryAnchor](https://developer.apple.com/documentation/healthkit/hkqueryanchor)
- [Apple Developer Documentation: enableBackgroundDelivery](https://developer.apple.com/documentation/HealthKit/HKHealthStore/enableBackgroundDelivery(for:frequency:withCompletion:))
- [Apple Developer Documentation: Background Delivery Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit.background-delivery)

### Secondary (MEDIUM confidence)
- [DevFright: How to Use HealthKit HKAnchoredObjectQuery](https://www.devfright.com/how-to-use-healthkit-hkanchoredobjectquery/) - Verified anchor persistence pattern
- [topolog's tech blog: HealthKit changes observing](https://dmtopolog.com/healthkit-changes-observing/) - Confirmed NSKeyedArchiver usage
- [Medium: Challenges With HKObserverQuery and Background App Refresh](https://medium.com/@shemona/challenges-with-hkobserverquery-and-background-app-refresh-for-healthkit-data-handling-8f84a4617499) - Documented completionHandler requirement
- [Medium: Mastering HealthKit Common Pitfalls](https://medium.com/mobilepeople/mastering-healthkit-common-pitfalls-and-solutions-b4f46729f28e) - Confirmed pitfalls

### Tertiary (Implementation reference)
- apps/ios/trendy/Services/HealthKitService.swift (2274 lines) - Primary implementation
- apps/ios/trendy/Views/HealthKit/HealthKitDebugView.swift (882 lines) - Debug UI
- apps/ios/trendy/Views/HealthKit/HealthKitSettingsView.swift (619 lines) - Settings UI
- apps/backend/internal/repository/event.go - Server upsert pattern
- supabase/migrations/20251227000000_add_healthkit_dedupe.sql - Database constraints

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Apple's official APIs, no alternatives
- Architecture patterns: HIGH - Retroactive documentation of working implementation
- Pitfalls: HIGH - Learned through implementation and verified with web search

**Research date:** 2026-01-16
**Valid until:** Stable patterns - valid until next major iOS release (iOS 19+)
**Phase implementation completed:** 2026-01-15
