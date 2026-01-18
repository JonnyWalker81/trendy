---
status: verifying
trigger: "iOS app UI freezes during tab switching and scrolling - jittery, unresponsive"
created: 2026-01-15T10:00:00Z
updated: 2026-01-15T10:30:00Z
---

## Current Focus

hypothesis: CONFIRMED - THREE root causes working together:
  1. PostHog session replay with screenshotMode=true captures entire view hierarchy continuously
  2. EVERY tab switch calls fetchData() in .task - 5 views = 5 calls despite debouncing
  3. fetchFromLocal creates fresh ModelContext and loads 1001+ events EVERY time

test: N/A - root causes confirmed through code analysis
expecting: N/A
next_action: Apply fix - Disable PostHog session replay OR optimize tab behavior

## Symptoms

expected: Fast response - actions should complete quickly (< 1 second)
actual: UI freezes during tab switching and scrolling. Tab switching is very slow, and scrolling is jittery/unresponsive once on a tab.
errors: No explicit errors, but concerning log output:
- Excessive PostHog `$snapshot` events (dozens queued rapidly, depth 1-32+)
- "System gesture gate timed out" - indicates UI thread blocking
- "Failed to create 1206x0 image slot" - memory pressure
- fetchFromLocal loading 1001 events repeatedly
reproduction: Switch between tabs in the iOS app, then try scrolling
timeline: Recent change - started after a recent code change/update

## Eliminated

## Evidence

- timestamp: 2026-01-15T10:00:00Z
  checked: Log analysis from symptoms
  found: PostHog $snapshot events firing rapidly (depth 1-32+), "System gesture gate timed out", fetchFromLocal loading 1001 events on each tab switch
  implication: Multiple potential causes - PostHog session replay, excessive data fetching, or both

- timestamp: 2026-01-15T10:05:00Z
  checked: trendyApp.swift PostHog configuration (lines 291-326)
  found: PostHog session replay enabled with screenshotMode=true (required for SwiftUI), captureLogs=true, minLogLevel=.info
  implication: Session replay with screenshotMode=true takes periodic screenshots of the ENTIRE view hierarchy - very expensive for complex SwiftUI views

- timestamp: 2026-01-15T10:05:00Z
  checked: EventStore.swift fetchData method (lines 360-397)
  found: Has debouncing with 5-second interval (fetchDebounceInterval), but fetchData can still be called from many places
  implication: Debouncing should prevent redundant fetches, need to check what's bypassing it

- timestamp: 2026-01-15T10:05:00Z
  checked: MainTabView.swift (lines 79-104)
  found: onChange(of: scenePhase) triggers store.fetchData() when app becomes active, but NO trigger on tab switch
  implication: Tab switching itself shouldn't trigger fetchData - need to investigate child views

- timestamp: 2026-01-15T10:10:00Z
  checked: ALL 5 tab views - BubblesView.swift, EventListView.swift, CalendarView.swift, AnalyticsView.swift, EventTypeSettingsView.swift
  found: EVERY single tab view has `.task { await eventStore.fetchData() }` modifier that runs when view appears
  implication: SMOKING GUN #1 - Tab switching causes 5 views to re-appear, each triggering fetchData

- timestamp: 2026-01-15T10:10:00Z
  checked: EventStore.swift fetchData method
  found: Even with 5-second debouncing, fetchFromLocal() creates a FRESH ModelContext and loads ALL events every time
  implication: SMOKING GUN #2 - 1001 events loaded into memory on each tab switch, even if debounced

- timestamp: 2026-01-15T10:10:00Z
  checked: PostHog configuration in trendyApp.swift (lines 297-308)
  found: Session replay enabled with screenshotMode=true (required for SwiftUI) - takes FULL SCREENSHOTS of entire view hierarchy
  implication: SMOKING GUN #3 - Every UI change triggers expensive screenshot capture on main thread

- timestamp: 2026-01-15T10:15:00Z
  checked: SyncEngine.swift performSync method
  found: performSync() calls bootstrapFetch or pullChanges which do network calls + multiple DB operations
  implication: fetchData() -> performSync() adds network latency + DB operations on TOP of local fetch

## Resolution

root_cause: THREE CAUSES COMBINED:
1. **PostHog Session Replay**: screenshotMode=true takes full screenshots on EVERY UI change. Combined with tab switching which causes many view updates, this floods the main thread with snapshot work.

2. **Redundant fetchData calls**: Every tab view (5 total) has `.task { await eventStore.fetchData() }`. When switching tabs, each view re-appears and triggers fetchData. Even with 5-second debouncing, this creates coordination overhead.

3. **Heavy fetchFromLocal**: fetchFromLocal() creates a NEW ModelContext every time and loads ALL 1001+ events from SwiftData. This is expensive even when data hasn't changed.

The combination creates a perfect storm: tab switch -> views re-appear -> fetchData called -> sync engine work + DB fetch -> PostHog captures EVERY intermediate UI state as screenshots -> main thread blocks -> "System gesture gate timed out"

fix: Applied two-part fix:
1. DISABLED PostHog session replay in trendyApp.swift - this was the primary cause of main thread blocking
2. Made tab view .task{} calls conditional on !eventStore.hasLoadedOnce - prevents redundant fetchData calls on tab switch

verification: (pending - need to test on device)
files_changed:
- apps/ios/trendy/trendyApp.swift - Disabled PostHog session replay
- apps/ios/trendy/Views/Dashboard/BubblesView.swift - Conditional fetchData
- apps/ios/trendy/Views/List/EventListView.swift - Conditional fetchData
- apps/ios/trendy/Views/Calendar/CalendarView.swift - Conditional fetchData
- apps/ios/trendy/Views/Analytics/AnalyticsView.swift - Conditional fetchData
- apps/ios/trendy/Views/Settings/EventTypeSettingsView.swift - Conditional fetchData
