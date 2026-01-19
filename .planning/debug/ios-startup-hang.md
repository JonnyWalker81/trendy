---
status: verifying
trigger: "iOS app startup hang - 2.21s severe hang at 00:05.227"
created: 2025-01-18T00:00:00Z
updated: 2025-01-19T05:45:00Z
---

## Quick Resume Instructions

**To continue this debug session after restarting Claude Code:**

1. Run the app with Instruments Time Profiler
2. Export the trace: `xctrace export --input <trace-file> --xpath '/trace-toc/run[@number="N"]/data/table[@schema="potential-hangs"]'`
3. Tell Claude: "Continue debugging iOS startup hang. Here are the results from Run N: [paste hang data]"
4. Reference this file: `.planning/debug/ios-startup-hang.md`

**Current Status:** Waiting for user to verify Run 5 with Instruments

## Current Focus

hypothesis: CONFIRMED - EventListView causes 2.27s hang when first selected (Run 4)
fix: Refactored EventListView to show loading placeholder initially, defer expensive grouping to background thread
test: Build succeeded - need user to run Instruments Time Profiler to verify fix
expecting: No severe hangs when switching to Events tab; loading indicator shows briefly, then content appears smoothly
next_action: User runs Instruments Time Profiler (Run 5) to verify EventListView fix

## Symptoms

expected: App launches and displays content within 250-500ms
actual: 2.29 second hang during startup (00:05.544 in Instruments trace Run 2)
errors: No crash, just severe UI hang
reproduction: Launch app fresh - hang occurs consistently
started: Unknown - investigating after calendar view fix

## Eliminated

- hypothesis: LazyView wrapper would prevent TabView pre-rendering of EventListView
  evidence: |
    LazyView implementation at apps/ios/trendy/Views/Components/LazyView.swift:43-45:
    ```swift
    var body: some View {
        build()
    }
    ```
    This calls build() unconditionally - there is no deferred loading.
    The @autoclosure only delays the evaluation of the argument at call site,
    but when SwiftUI evaluates `body`, it immediately calls `build()`.

    Time profile Run 2 at 00:05.547 shows:
    - Thread 2 (main thread) executing EventListView.body.getter
    - Full stack trace showing Section and ForEach rendering
    - This occurs AFTER LazyView was implemented, proving it has no effect
  timestamp: 2025-01-18T02:30:00Z

- hypothesis: LazyView with hasAppeared @State would prevent TabView pre-rendering
  evidence: |
    Run 3 trace shows hang STILL occurs, just moved from ~5.5s to ~7.0s (2.26s duration).

    At 00:07.030 on main thread (thread ref="2"):
    - EventListView.filterSection.getter is executing
    - This proves EventListView IS being fully rendered at startup

    The problem: SwiftUI TabView calls `onAppear` on ALL tab content when the TabView first appears,
    not just the selected tab. This is because TabView needs to measure all tabs for proper layout.

    LazyView's `Color.clear.onAppear { hasAppeared = true }` fires for ALL tabs immediately,
    defeating the lazy loading purpose.

    The hang moved later (5.5s -> 7.0s) because:
    - The app now shows LoadingView until fetchFromLocalOnly() completes
    - When isLoading becomes false, TabView appears
    - ALL LazyViews fire onAppear simultaneously
    - EventListView renders with full data, causing 2.26s hang
  timestamp: 2025-01-18T12:30:00Z

## Evidence

- timestamp: 2025-01-18T00:01:00Z
  checked: trendyApp.swift init()
  found: |
    Multiple initialization operations including PostHog, Supabase, etc.
    But these complete by ~1 second in trace.
  implication: App initialization is NOT the cause of the 5.5s hang

- timestamp: 2025-01-18T00:02:00Z
  checked: sharedModelContainer static initializer
  found: Heavy synchronous operations including schema validation
  implication: Could contribute to early startup time but not 5.5s hang

- timestamp: 2025-01-18T00:03:00Z
  checked: MainTabView.initializeNormally()
  found: |
    Sets isLoading = false at line 311-313 AFTER fetchFromLocalOnly() completes.
    This triggers mainTabContent to render, including all TabView tabs.
  implication: The hang occurs when mainTabContent first renders

- timestamp: 2025-01-18T02:00:00Z
  checked: Time profile Run 2 XML at lines 1450-1470 (5.5-5.6 second timeframe)
  found: |
    Line 1456 (5547189041 ns = 00:05.547):
    Thread ref="2" (main thread) stack includes:
    - EventListView.body.getter (addr=0x107354180 in trendy binary)
    - ForEach<>.init(_:content:)
    - Section<>.init(content:header:)
    - closure #1 in closure #1 in EventListView.body.getter
    - UpdateCollectionViewListCoordinator.updateValue()
    - SectionAccumulator.formResult()
    - ForEachChild.updateValue()

    Line 1455 (5547188583 ns = 00:05.547):
    Thread ref="1735" (background) executing:
    - Dictionary.init<A>(grouping:by:) from EventListView.updateCachedData()

    Line 1556 (5618188541 ns = 00:05.618):
    Thread ref="2" (main thread):
    - Text.init<A>(_:format:) - date formatting for section headers
    - EventListView.body.getter
  implication: |
    EventListView IS being rendered at startup despite LazyView wrapper.
    The ForEach iterates over ALL dates/events, creating Section views for each.
    Date formatting (Text with .format) happens for every section header.

    CRITICAL: LazyView is NOT working because it unconditionally calls build()

- timestamp: 2025-01-18T02:15:00Z
  checked: LazyView.swift implementation
  found: |
    ```swift
    struct LazyView<Content: View>: View {
        let build: () -> Content

        var body: some View {
            build()  // Called UNCONDITIONALLY
        }
    }
    ```

    The @autoclosure wraps the argument, but body still evaluates build() immediately.
    For true lazy loading, it needs @State to track whether to render.
  implication: LazyView has NO effect - content is created as soon as SwiftUI evaluates body

- timestamp: 2025-01-18T02:25:00Z
  checked: Background thread work during hang
  found: |
    Thread 1735 (background) runs EventListView.updateCachedData() at 00:05.486:
    - Dictionary.init<A>(grouping:by:) for event grouping
    - Calendar.startOfDay operations

    BUT Thread 2 (main) is ALSO blocked rendering EventListView at the same time.
    The background work doesn't help because:
    1. Initial render still happens before background task completes
    2. ForEach iterates all dates/events synchronously
  implication: updateCachedData's Task.detached doesn't prevent initial render hang

- timestamp: 2025-01-18T12:00:00Z
  checked: Run 3 time profile with corrected LazyView implementation
  found: |
    Hang PERSISTS but moved from ~5.5s to ~7.0s:
    - 00:07.045 - 2.26s severe hang (was at 00:05.227)

    At 00:07.030 on main thread (thread ref="2"):
    - EventListView.filterSection.getter is executing (frame addr=0x1050a16cc)
    - Full backtrace shows closure in EventListView rendering

    At 00:07.003 on background thread (thread ref="1157"):
    - EventListView.updateCachedData() running concurrently
    - Dictionary.init(grouping:by:) for event grouping

    rebuildEventsByDateCache() appears 10 times in the trace:
    - 00:01.677-00:01.695 (first call during fetchFromLocal)
    - 00:03.486-00:03.781 (second call during background sync)
  implication: |
    LazyView's hasAppeared fix DID delay rendering (moved from 5.5s to 7.0s).
    BUT SwiftUI TabView fires onAppear for ALL tabs when TabView first appears.
    This defeats the lazy loading - all tabs render simultaneously.

- timestamp: 2025-01-18T12:15:00Z
  checked: SwiftUI TabView onAppear behavior
  found: |
    SwiftUI documentation and behavior confirms:
    - TabView needs to measure all tab content for proper layout
    - onAppear fires for ALL tab content when TabView first appears
    - Only the selected tab is actually VISIBLE, but all tabs trigger onAppear

    This explains why LazyView using onAppear doesn't prevent pre-rendering:
    1. MainTabView shows LoadingView initially
    2. isLoading becomes false -> TabView appears
    3. TabView measures ALL tabs -> ALL onAppear callbacks fire
    4. ALL LazyViews set hasAppeared = true simultaneously
    5. ALL tab content renders at once -> 2.26s hang
  implication: Need different approach - track SELECTED tab, not just appeared

- timestamp: 2025-01-18T22:10:00Z
  checked: Run 4 potential-hangs export after LazyView fix
  found: |
    xctrace export of potential-hangs table showed:
    - 00:01.480 - Microhang 288ms (startup - acceptable)
    - 00:03.084 - SEVERE HANG 2.27s (Events tab first selected)
    - 00:05.854 - Microhang 254ms
    - 00:26.667 - Microhang 342ms

    The LazyView fix successfully eliminated the startup hang (no longer at 5-7s).
    But a NEW hang appeared when user switches to Events tab.
  implication: |
    EventListView itself is expensive to render, even when deferred.
    The work (grouping, sorting, ForEach) blocks main thread.

- timestamp: 2025-01-18T22:12:00Z
  checked: EventListView code structure
  found: |
    EventListView.swift analysis revealed multiple issues:

    1. .task AND .onAppear both call updateCachedData() - redundant

    2. updateCachedData() synchronous path for <100 events:
       ```swift
       if events.count < 100 {
           cachedGroupedEvents = Dictionary(grouping: events) { event in
               Calendar.current.startOfDay(for: event.timestamp)
           }
           cachedSortedDates = cachedGroupedEvents.keys.sorted(by: >)
       }
       ```
       This runs on main thread, blocking UI.

    3. filteredEvents computed property iterates all events on every access

    4. ForEach(sortedDates) creates ALL Section views before any are displayed
  implication: |
    Even with LazyView deferring creation, EventListView's initial render is too expensive.
    Need to: (1) show loading placeholder immediately, (2) move all data work to background

## Resolution

root_cause: |
  TWO ISSUES IDENTIFIED:

  ISSUE 1 (Fixed in previous commit): Startup hang caused by TabView onAppear behavior
  - LazyView's onAppear fires for ALL tabs when TabView appears
  - Fixed with tab-selection-aware LazyView that only builds content when tab is selected

  ISSUE 2 (Fixed now): Events tab hang when first selected (Run 4: 2.27s at 00:03.084)
  - When EventListView renders for the first time, expensive work blocks main thread:
    1. filteredEvents computed property iterates all events
    2. updateCachedData() groups events by date using Dictionary(grouping:)
    3. ForEach creates ALL Section views synchronously
    4. Both .task and .onAppear were calling updateCachedData() redundantly

  The Instruments trace (Run 4) showed:
  - 00:01.480 - Microhang 288ms (startup)
  - 00:03.084 - SEVERE HANG 2.27s (Events tab first render)
  - 00:05.854 - Microhang 254ms (subsequent operation)

fix: |
  EVENTLISTVIEW REFACTORING (apps/ios/trendy/Views/List/EventListView.swift):

  1. Added `hasCompletedInitialLoad` @State to track when data is ready

  2. Split body into loadingPlaceholder and eventsList computed properties:
     - loadingPlaceholder: Simple ProgressView shown immediately
     - eventsList: Full List view rendered only after data ready

  3. Replaced synchronous updateCachedData() with async updateCachedDataAsync():
     - ALWAYS runs expensive Dictionary(grouping:) on background thread
     - Uses Task.detached to avoid blocking main thread
     - Sets hasCompletedInitialLoad = true when complete

  4. Removed redundant onAppear { updateCachedData() }:
     - .task already handles initial cache population
     - Duplicate call was causing unnecessary work

  5. Updated onChange handlers to use async version in Task blocks

  Result: When user taps Events tab:
  - Immediately shows "Loading events..." indicator (no blocking)
  - Background thread processes event grouping
  - When complete, smooth transition to full list

verification: |
  1. Run Instruments Time Profiler with app launch
  2. Verify no hangs > 500ms during startup (target: < 300ms)
  3. Default tab (BubblesView) renders immediately
  4. Switch to Events tab - verify:
     - Loading indicator appears instantly (no hang)
     - Events appear after brief loading (< 500ms)
     - No severe hangs in Time Profiler
  5. Test with large event count (500+) to ensure scalability

files_changed:
  - apps/ios/trendy/Views/Components/LazyView.swift: Tab-selection-aware LazyView (previous fix)
  - apps/ios/trendy/Views/MainTabView.swift: Updated LazyView usage (previous fix)
  - apps/ios/trendy/Views/List/EventListView.swift: Async data loading with loading placeholder

## Instruments Trace History

| Run | Trace File | Status | Key Finding |
|-----|------------|--------|-------------|
| 1 | trendy-after.trace/Trace1.run | Calendar fix applied | 5 severe hangs during tab switching → 1 severe hang at startup |
| 2 | trendy-after.trace/Trace2.run | LazyView v1 (broken) | 2.21s hang still at 00:05.227 - LazyView didn't defer |
| 3 | trendy-after.trace/Trace3.run | LazyView v2 (onAppear) | 2.26s hang moved to 00:07.045 - TabView fires all onAppear |
| 4 | trendy-after.trace/Trace4.run | LazyView v3 (selection binding) | Startup fixed! But 2.27s hang at 00:03 when Events tab selected |
| 5 | (pending) | EventListView async loading | Need to verify Events tab loads without hang |

## All Fixes Applied (Chronological)

### Fix 1: Calendar View O(N×days) - VERIFIED ✅
**File:** `apps/ios/trendy/ViewModels/EventStore.swift`
- Added `eventsByDateCache: [Date: [Event]]` dictionary
- Changed `events(on:)` from O(N) filter to O(1) lookup
- Result: Calendar samples dropped 90% (126→12)

### Fix 2: LazyView for Tab Deferral - VERIFIED ✅
**File:** `apps/ios/trendy/Views/Components/LazyView.swift`
```swift
struct LazyView<Content: View>: View {
    let tag: Int
    @Binding var selection: Int
    let build: () -> Content
    @State private var hasBeenSelected = false

    var body: some View {
        if hasBeenSelected || selection == tag {
            build()
                .onAppear { hasBeenSelected = true }
        } else {
            Color.clear
        }
    }
}
```
**File:** `apps/ios/trendy/Views/MainTabView.swift`
- Wrapped tabs 1-4 with `LazyView(tag:selection:)`
- Result: Startup hang eliminated (Run 4 shows no severe hang at startup)

### Fix 3: EventListView Async Loading - PENDING VERIFICATION
**File:** `apps/ios/trendy/Views/List/EventListView.swift`
- Added `hasCompletedInitialLoad` state
- Added `loadingPlaceholder` shown while loading
- Changed to `updateCachedDataAsync()` - always runs on background thread
- Removed redundant `.onAppear` call
- Result: Need Run 5 to verify

## How to Verify (Run 5)

1. Open Xcode, build and run on device
2. Open Instruments → Time Profiler
3. Record app launch + switch to Events tab
4. Stop recording
5. Export hangs:
   ```bash
   xctrace export --input /path/to/trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]'
   ```
6. Expected: No severe hangs (all < 500ms)

## If Hang Persists After Run 5

Investigate these areas:
1. `EventListView.filteredEvents` - may still be computed synchronously
2. SwiftUI List rendering - may need pagination/virtualization
3. Date formatting in section headers - expensive if many sections
4. SwiftData fetch - may be blocking main thread

Export time-profile and grep for app functions:
```bash
xctrace export --input <trace> --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > profile.xml
grep -oE 'name="[^"]+' profile.xml | sed 's/name="//' | grep -i "event\|list\|store" | sort | uniq -c | sort -rn
```
