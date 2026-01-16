# Project Research Summary

**Project:** Trendy iOS Data Infrastructure Overhaul
**Domain:** iOS background data infrastructure (HealthKit, CoreLocation, SwiftData sync)
**Researched:** 2026-01-15
**Confidence:** MEDIUM-HIGH

## Executive Summary

This research covers the technical landscape for rebuilding Trendy's iOS background data systems. The current implementation has grown organically into monolithic services (`HealthKitService` at 1,972 lines, `SyncEngine` at 1,116 lines) that violate separation of concerns and make debugging difficult.

**The core finding:** iOS background execution is inherently unreliable by design. Apple prioritizes battery life and privacy over app convenience. Successful background data capture requires:
1. Proper entitlements and observer query setup (missing pieces identified)
2. Design for eventual consistency, not real-time guarantees
3. Defensive re-registration on every app launch
4. Clear separation between platform adapters, processors, and persistence

**Key risk:** HealthKit background delivery may only work reliably when charging. This is documented iOS behavior. The app must refresh data on foreground return and set appropriate user expectations.

## Key Findings

### Recommended Stack

The existing stack (Swift/SwiftUI + SwiftData + HealthKit + CoreLocation + Supabase) is correct. Key improvements needed:

**Core technologies to adopt:**
- `HKAnchoredObjectQuery` with persistent anchors — current code uses `HKSampleQuery`, missing change tracking
- `CLMonitor` (iOS 17+) — modern actor-based geofencing, cleaner than CLLocationManager
- `@ModelActor` — thread-safe SwiftData background operations
- `BGProcessingTask` — for batch sync operations (up to 10 minutes)

**What NOT to use:**
- `HKObserverQuery` alone (doesn't tell WHAT changed)
- `CLLocationManager.monitoredRegions` for state (documented bug: may return empty)
- Passing `@Model` objects across actors (will crash or corrupt)
- `BGAppRefreshTask` for sync (30-second limit too short)

### Expected Features

**Table stakes (must have):**
- HealthKit background delivery per enabled data type
- Geofence persistence across app lifecycle and device restart
- Offline data creation with automatic sync when online
- Data never lost (persistent queue with retry)

**Differentiators (should have):**
- Sync state visibility ("3 events pending sync")
- Last sync timestamp display
- Geofence health monitoring (detect silent unregistration)
- Automatic retry with exponential backoff

**Anti-features (avoid):**
- Manual "Sync Now" button (creates unmet expectations — iOS controls timing)
- Real-time HealthKit promises (iOS delivers on its schedule)
- Silent conflict resolution (user loses changes without knowing)
- Unlimited retry (drains battery, fills queue)

### Architecture Approach

**Problem:** Current architecture has god objects handling 4-6 distinct concerns each.

**Solution:** Decompose into Observer-Processor-Factory pipeline:

```
Platform Adapter (HKQueryManager, GeofenceMonitor)
       ↓
Processor (WorkoutProcessor, SleepProcessor, etc.)
       ↓
Factory (HealthEventFactory, GeofenceEventFactory)
       ↓
Repository (EventRepository with sync awareness)
       ↓
SyncCoordinator (orchestration only)
```

**Major components to create:**
1. `HKQueryManager` — observer query setup and background delivery (extracted from HealthKitService)
2. Category-specific processors — `WorkoutProcessor`, `SleepProcessor`, etc.
3. `GeofenceReconciler` — verify and restore monitored regions on launch
4. `MutationQueue` — separate from sync orchestration
5. Repositories with sync awareness — auto-queue mutations on save/delete

### Critical Pitfalls

1. **Missing HealthKit background delivery entitlement** — iOS 15+ requires `com.apple.developer.healthkit.background-delivery` in BOTH entitlements file AND provisioning profile. Silent failure if missing.

2. **HKObserverQuery completion handler not called in all paths** — HealthKit uses exponential backoff after 3 missed calls, then stops delivering entirely.

3. **Geofences silently stop after app termination** — iOS 15+ known behavior. Must re-register ALL regions in `didFinishLaunchingWithOptions` and verify against `monitoredRegions`.

4. **SwiftData models passed across threads** — NOT Sendable. Pass `persistentModelID` instead, fetch in destination context.

5. **45+ print statements in production code** — No production visibility. Replace with structured `Log.category.level` logging.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Foundation
**Rationale:** Fix silent failures before any refactoring. Current code may have broken entitlements/registration.
**Delivers:** Verified entitlements, BGTask registration, structured logging
**Addresses:** Pitfalls 1, 12, 14 (entitlements, BGTask registration, print statements)
**Risk:** LOW — audit and fix, no architecture changes

### Phase 2: HealthKit Reliability
**Rationale:** Most user-impacting issue. Workouts/active energy not captured reliably.
**Delivers:** HKAnchoredObjectQuery with persistent anchors, processor extraction
**Addresses:** Pitfalls 2, 3, 4 (completion handler, frequency support, charging-only delivery)
**Uses:** HKAnchoredObjectQuery, HKObserverQuery proper patterns
**Risk:** MEDIUM — requires testing on real device with varied scenarios

### Phase 3: Geofence Reliability
**Rationale:** Second most reported issue. Geofences stop working after days.
**Delivers:** Startup verification, re-registration, CLMonitor evaluation
**Addresses:** Pitfalls 5, 6 (termination handling, 20-region limit)
**Implements:** GeofenceReconciler, GeofenceAuthManager extraction
**Risk:** MEDIUM — requires physical location testing

### Phase 4: SwiftData Concurrency
**Rationale:** Foundation for safe sync engine. Current patterns have threading risks.
**Delivers:** @ModelActor adoption, thread safety audit
**Addresses:** Pitfalls 7, 8 (model threading, ModelActor isolation)
**Uses:** @ModelActor macro, PersistentIdentifier passing
**Risk:** MEDIUM — requires enabling strict concurrency checking

### Phase 5: Sync Engine Robustness
**Rationale:** Highest complexity. Do after foundations are solid.
**Delivers:** Decomposed sync components, simplified cursor, conflict detection
**Addresses:** Pitfalls 9, 10, 11 (cursor race conditions, LWW data loss, queue ordering)
**Implements:** MutationQueue, PullSyncEngine, SyncCoordinator separation
**Risk:** HIGHER — most complex refactor, needs comprehensive testing first

### Phase 6: Polish & User Education
**Rationale:** Handle edge cases users control (force-quit behavior).
**Delivers:** Background health indicators, user education
**Addresses:** Pitfall 13 (force-quit disables background)
**Risk:** LOW — UX additions, no architecture changes

### Phase Ordering Rationale

- **Phase 1 before all:** Silent failures must be fixed before measuring improvement
- **Phases 2-3 parallel-capable:** HealthKit and Geofence are independent systems
- **Phase 4 before 5:** SwiftData threading must be safe before sync decomposition
- **Phase 5 last of major work:** Highest risk, benefits from all prior improvements
- **Phase 6 after stabilization:** Polish when core is reliable

### Research Flags

**Phases likely needing deeper research during planning:**
- **Phase 3:** CLMonitor behavior and migration path needs empirical validation
- **Phase 5:** Conflict resolution strategy depends on multi-device usage patterns

**Phases with standard patterns (skip research-phase):**
- **Phase 1:** Entitlements and logging are well-documented
- **Phase 4:** @ModelActor patterns are established
- **Phase 6:** UX patterns are straightforward

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official Apple APIs, well-documented |
| Features | MEDIUM | User expectations inferred from domain research |
| Architecture | MEDIUM-HIGH | Patterns verified, but implementation needs validation |
| Pitfalls | HIGH | Verified against Apple docs, forums, and current codebase |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **CLMonitor state persistence:** Documentation sparse, needs empirical testing
- **HealthKit charging requirement:** Multiple sources cite this, but behavior may vary by iOS version
- **Conflict resolution strategy:** LWW is simplest, but user-generated content may need explicit handling

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation: HKObserverQuery, HKAnchoredObjectQuery, enableBackgroundDelivery
- WWDC23: Meet Core Location Monitor (CLMonitor introduction)
- Apple Developer Documentation: BGTaskScheduler, region monitoring
- Direct codebase analysis: HealthKitService.swift, GeofenceManager.swift, SyncEngine.swift

### Secondary (MEDIUM confidence)
- DevFright: HKAnchoredObjectQuery patterns (March 2025)
- Fatbobman: Concurrent Programming in SwiftData
- Radar.com: Geofencing iOS limitations
- Apple Developer Forums: Background delivery issues, region monitoring bugs

### Tertiary (LOW confidence)
- Community reports on charging-only background delivery
- iOS 15+ geofence termination issues (may be resolved in iOS 17+)

---
*Research completed: 2026-01-15*
*Ready for roadmap: yes*
