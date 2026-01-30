---
status: resolved
trigger: "Fix pre-existing unit test failures in the iOS app"
created: 2026-01-29T00:00:00Z
updated: 2026-01-29T00:10:00Z
---

## Current Focus

hypothesis: RESOLVED - All 446 tests pass
test: N/A
expecting: N/A
next_action: Archive session

## Symptoms

expected: All unit tests pass
actual: 131 tests fail (out of ~530) across 5 categories
errors: See failure_categories in prompt
reproduction: Run xcodebuild test command
started: Pre-existing failures

## Eliminated

## Evidence

- timestamp: 2026-01-29
  checked: SyncEngine init reads UserDefaults cursor
  found: SyncEngine reads lastSyncCursor from UserDefaults in init(), but tests set UserDefaults AFTER engine creation
  implication: Engine always sees cursor=0, takes bootstrap path instead of incremental path

- timestamp: 2026-01-29
  checked: Color hex conversion
  found: Color(hex:) uses Scanner which parses any length hex string; hexString uses Int() truncation instead of rounding
  implication: Short/long hex strings pass validation; roundtrip loses precision

- timestamp: 2026-01-29
  checked: EventSourceType enum
  found: Enum has 4 cases (manual, imported, geofence, healthKit) but tests expect 2
  implication: Tests written before geofence and healthKit cases were added

- timestamp: 2026-01-29
  checked: APIConfiguration.isValid
  found: "http://" passes validation because it has prefix "http://" and is not empty
  implication: Incomplete URLs with just protocol prefix are accepted

- timestamp: 2026-01-29
  checked: Circuit breaker resetCircuitBreaker()
  found: resetCircuitBreaker() resets backoffMultiplier to 1.0, preventing exponential escalation
  implication: Contradicts exponential backoff test expectations

## Resolution

root_cause: Multiple independent root causes across 5 categories:
  1. SyncEngine tests: UserDefaults cursor set AFTER engine init (engine reads at init)
  2. Circuit breaker: resetCircuitBreaker() reset multiplier, preventing escalation
  3. Color extension: No hex length validation; Int truncation instead of rounding
  4. EventSourceType: Tests expect 2 cases but enum has 4
  5. AppConfiguration: isValid accepts bare protocol prefixes like "http://"

fix:
  1. Restructured all SyncEngine test helpers to set UserDefaults cursor BEFORE creating SyncEngine
  2. Changed resetCircuitBreaker() to NOT reset multiplier (reset on successful sync instead)
  3. Added 6-char length validation to Color(hex:); changed Int() to Int(round()) in hexString
  4. Updated tests to expect 4 EventSourceType cases
  5. Added URL length check to isValid (must have content after protocol prefix)

verification: All 446 tests pass with -parallel-testing-enabled NO

files_changed:
  - apps/ios/trendy/Models/EventType.swift (Color hex conversion fix)
  - apps/ios/trendy/DesignSystem/Colors.swift (UIColor hex length validation)
  - apps/ios/trendy/Configuration/AppConfiguration.swift (URL validation fix)
  - apps/ios/trendy/Services/Sync/SyncEngine.swift (resetCircuitBreaker multiplier + success reset)
  - apps/ios/trendyTests/SyncEngine/PaginationTests.swift
  - apps/ios/trendyTests/SyncEngine/ResurrectionPreventionTests.swift
  - apps/ios/trendyTests/SyncEngine/BootstrapTests.swift
  - apps/ios/trendyTests/SyncEngine/SingleFlightTests.swift
  - apps/ios/trendyTests/SyncEngine/BatchProcessingTests.swift
  - apps/ios/trendyTests/SyncEngine/CircuitBreakerTests.swift
  - apps/ios/trendyTests/SyncEngine/DeduplicationTests.swift
  - apps/ios/trendyTests/SyncEngine/DataStoreReuseTests.swift
  - apps/ios/trendyTests/SyncEngine/DataStoreResetTests.swift
  - apps/ios/trendyTests/SyncEngine/StaleContextRecoveryTests.swift
  - apps/ios/trendyTests/EventSourceTypeTests.swift
