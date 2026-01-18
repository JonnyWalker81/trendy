---
phase: 07-ux-indicators
plan: 03
subsystem: ui
tags: [swiftui, sync, error-handling, accessibility]

# Dependency graph
requires:
  - phase: 07-01
    provides: SyncIndicatorDisplayState, SyncStatusViewModel base
  - phase: 07-02
    provides: SyncSettingsView for error surfacing context
provides:
  - SyncErrorView with tap-to-expand and error classification
  - Enhanced SyncStatusViewModel with error persistence and escalation
affects:
  - 07-04 (can integrate SyncErrorView into floating indicator)
  - integration (error handling now has consistent UX)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Error classification helper (static func on view)
    - Error persistence until dismissed (not auto-dismiss)
    - Consecutive failure tracking for visual escalation

key-files:
  created:
    - apps/ios/trendy/Views/Components/SyncIndicator/SyncErrorView.swift
  modified:
    - apps/ios/trendy/ViewModels/SyncStatusViewModel.swift

key-decisions:
  - "Errors persist until dismissed or resolved (no auto-dismiss)"
  - "Auth errors (401/403) show Sign In button, others show Retry"
  - "Escalation triggers at 3+ consecutive failures (red border)"
  - "Error classification uses static helper for reusability"

patterns-established:
  - "Error persistence: record on failure, dismiss explicitly, clear on success"
  - "Auth vs non-auth error handling: different actions, same visual"
  - "Escalation counter: only resets on success, not on dismiss"

# Metrics
duration: 28min
completed: 2026-01-18
---

# Phase 7 Plan 03: Error Persistence and Escalation Summary

**Sync error display with tap-to-expand, auth handling, and escalation after repeated failures**

## Performance

- **Duration:** 28 min
- **Started:** 2026-01-18T19:50:05Z
- **Completed:** 2026-01-18T20:17:49Z
- **Tasks:** 2

## Key Deliverables

### 1. SyncErrorView (273 lines)

A SwiftUI view for displaying sync errors with:
- User-friendly message displayed prominently
- Tap-to-expand technical details (respects reduce motion)
- Auth errors show "Sign In" button, others show "Retry"
- Escalated visual (red border) after 3+ failures
- Static `classifyError()` helper for error message classification:
  - 401/unauthorized/session expired -> auth error
  - 403/forbidden -> auth error
  - network/connection/offline -> network error
  - 500/server -> server error
  - Default -> "Sync failed"

### 2. Enhanced SyncStatusViewModel

Extended the view model from 07-01 with error persistence:
- `persistedError: (message: String, timestamp: Date)?` - stays until dismissed
- `lastErrorWasAuthError: Bool` - tracks auth-specific handling
- `consecutiveFailureCount: Int` - for escalation (3+ threshold)
- `isErrorEscalated: Bool` computed property
- `recordError(message:)` - records error and increments failure count
- `dismissError()` - clears error but NOT failure count
- `recordSuccess()` - clears error AND resets failure count
- Updated `displayState` to show persisted errors even when idle
- Updated `refresh(from:)` to detect and record errors from sync engine

## Implementation Details

### Error Flow

```
SyncEngine.error -> refresh() -> recordError() -> persistedError set
                                             -> consecutiveFailureCount++
                                             -> displayState returns .error

User taps Dismiss -> dismissError() -> persistedError cleared
                                    -> displayState may return .hidden
                                    (but consecutiveFailureCount preserved)

User taps Retry -> sync succeeds -> recordSuccess() -> all cleared
```

### Escalation Logic

- consecutiveFailureCount increments on each error
- At 3+, `isErrorEscalated` returns true
- SyncErrorView shows red border when escalated
- Only `recordSuccess()` resets the counter (not dismiss)

## Commits

| Hash | Description |
|------|-------------|
| d78210e | feat(07-03): add SyncErrorView with tap-to-expand |
| 2a0e2ad | feat(07-03): add error persistence and escalation to SyncStatusViewModel |

## Deviations from Plan

None - plan executed exactly as written.

## Success Criteria Verification

- [x] SyncErrorView shows user-friendly message
- [x] SyncErrorView expands to show technical details on tap
- [x] SyncErrorView handles auth errors with Sign In action
- [x] SyncErrorView shows escalated visual after 3+ failures
- [x] SyncStatusViewModel persists errors until dismissed
- [x] SyncStatusViewModel tracks consecutive failures
- [x] Build passes (Swift syntax verified)

## Next Steps

- 07-04: Integration of error display into floating indicator
- Wire SyncErrorView into SyncIndicatorView for error state display
