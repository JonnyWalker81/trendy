---
phase: 22-metrics-documentation
plan: 01
subsystem: metrics, observability
tags: [metrickit, ossignposter, instruments, telemetry, signposts]

# Dependency graph
requires:
  - phase: 21-code-quality-refactoring
    provides: Refactored SyncEngine with clear method boundaries
provides:
  - SyncMetrics instrumentation class with OSSignposter and MetricKit integration
  - MetricsSubscriber singleton for production telemetry payloads
  - Full SyncEngine instrumentation (5 intervals, 5 event types)
affects: [testing, production-monitoring, performance-analysis]

# Tech tracking
tech-stack:
  added: [MetricKit, os.OSSignposter, mxSignpost]
  patterns: [signpost-intervals, metrickit-subscriber, instrumentation-singleton]

key-files:
  created:
    - apps/ios/trendy/Services/Metrics/SyncMetrics.swift
    - apps/ios/trendy/Services/Metrics/MetricsSubscriber.swift
  modified:
    - apps/ios/trendy/Services/Sync/SyncEngine.swift
    - apps/ios/trendy/trendyApp.swift

key-decisions:
  - "Typed begin/end methods per operation (not generic) for compile-time safety"
  - "Per-operation NSLock dictionaries for thread-safe interval tracking"
  - "MetricsSubscriber initialized first in App.init for full coverage"
  - "Both OSSignposter (dev) and mxSignpost (production) for dual telemetry"

patterns-established:
  - "Metrics interval pattern: let id = SyncMetrics.beginX(); defer { SyncMetrics.endX(id) }"
  - "Event recording pattern: SyncMetrics.recordEvent() for point-in-time events"
  - "MetricsSubscriber singleton for MXMetricManagerSubscriber"

# Metrics
duration: 45min
completed: 2026-01-24
---

# Phase 22 Plan 01: Sync Metrics Infrastructure Summary

**OSSignposter + MetricKit instrumentation for SyncEngine with 5 operation intervals and 5 event types**

## Performance

- **Duration:** 45 min
- **Started:** 2026-01-24T22:55:15Z
- **Completed:** 2026-01-24T23:40:00Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Created SyncMetrics.swift with dual telemetry (OSSignposter for Instruments, mxSignpost for MetricKit)
- Created MetricsSubscriber.swift to receive daily MetricKit production telemetry payloads
- Instrumented all 5 major SyncEngine operations with interval tracking
- Added event recording for rate limits, circuit breaker, retries, and sync success/failure

## Task Commits

Each task was committed atomically:

1. **Task 1: Create SyncMetrics instrumentation class** - `5232a53` (feat)
2. **Task 2: Create MetricsSubscriber for production telemetry** - `a82bea5` (feat)
3. **Task 3: Instrument SyncEngine with metrics** - `757c5db` (feat)

## Files Created/Modified

- `apps/ios/trendy/Services/Metrics/SyncMetrics.swift` - Centralized metrics instrumentation (309 lines)
  - 5 interval types: FullSync, FlushMutations, PullChanges, BootstrapFetch, HealthCheck
  - 5 event types: RateLimitHit, RetryAttempt, CircuitBreakerTrip, SyncSuccess, SyncFailure
  - Thread-safe interval tracking with per-operation NSLock

- `apps/ios/trendy/Services/Metrics/MetricsSubscriber.swift` - MetricKit subscriber (182 lines)
  - MXMetricManagerSubscriber implementation
  - Processes metric payloads (signposts, launch, responsiveness)
  - Processes diagnostic payloads (crashes, hangs)
  - Filters mixed-version payloads

- `apps/ios/trendy/Services/Sync/SyncEngine.swift` - Instrumented with metrics calls
  - performSync: FullSync interval + success/failure events
  - flushPendingMutations: FlushMutations interval
  - pullChanges: PullChanges interval
  - bootstrapFetch: BootstrapFetch interval
  - performHealthCheck: HealthCheck interval
  - Rate limit detection: RateLimitHit event (2 locations)
  - Circuit breaker: CircuitBreakerTrip event
  - Retry logic: RetryAttempt event (2 locations)

- `apps/ios/trendy/trendyApp.swift` - MetricsSubscriber.shared initialization in App.init

## Decisions Made

1. **Typed begin/end methods per operation** - Using `beginFullSync()/endFullSync()` instead of generic `beginInterval("FullSync")` for compile-time safety (StaticString requirement)
2. **Per-operation lock dictionaries** - Separate NSLock and interval storage per operation type for better isolation
3. **Early MetricsSubscriber initialization** - Added as first line in App.init to capture all metrics from launch
4. **Dual telemetry approach** - Both OSSignposter (viewable in Instruments during dev) and mxSignpost (captured by MetricKit in production)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

1. **OSSignposter API differences** - Initial implementation used generic String-based interval names, but OSSignposter requires StaticString. Fixed by creating typed methods per operation.
2. **MXHistogram API** - Used `.bucketCount` which doesn't exist; switched to `.bucketEnumerator.nextObject() != nil` pattern.
3. **MXCrashDiagnostic fields** - `exceptionType` and `signal` are NSNumber, not Int enums; used `.intValue` instead of `.rawValue`.

## User Setup Required

None - no external service configuration required. MetricKit works automatically on physical devices.

## Next Phase Readiness

- Sync operations now visible in Instruments Time Profiler during development
- Production telemetry will be collected via MetricKit (daily payloads on physical devices)
- Requirements completed: METR-01, METR-02, METR-03, METR-04, METR-05, METR-06

**Note:** MetricKit only works on physical devices. Use Xcode > Debug > Simulate MetricKit Payloads for testing.

---
*Phase: 22-metrics-documentation*
*Completed: 2026-01-24*
