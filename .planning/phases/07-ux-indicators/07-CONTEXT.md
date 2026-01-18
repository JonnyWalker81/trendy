# Phase 7: UX Indicators - Context

**Gathered:** 2026-01-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Clear sync state visibility for users. This phase delivers visual indicators showing what's happening with their data: sync status, last sync timestamps, error surfacing, and progress feedback. Users should never wonder if their data is synced or what went wrong.

</domain>

<decisions>
## Implementation Decisions

### Status Indicator Design
- Floating element that appears only when active (syncing, errors, offline)
- Persistent banner when offline — shows "Offline - X pending" with pending count
- User can collapse offline banner to small icon (tap to expand later)
- Animated transition when going back online: "Offline - 3 pending" morphs smoothly to "Syncing 1 of 3..."
- Use app's semantic colors from `tokens/palette.svg`:
  - Success: `#059669` (green)
  - Warning: `#D97706` (amber)
  - Destructive: `#DC2626` (red)
  - Primary: `#2563EB` (blue syncing)
- Smooth spring animations between states
- Honor system "reduce motion" accessibility setting
- No sounds — visual feedback only

### Timestamp Display
- Relative format ("5 min ago") with absolute on tap ("3:42 PM")
- Show in both: summary in floating indicator, detail in settings
- Dedicated sync section in Settings with:
  - Last sync timestamp
  - Pending count
  - Manual "Sync Now" button
  - Recent syncs history (last 5-10)
- Sync history entries include: time + count + type ("3:42 PM - 3 events, 2 event types")
- Sync history includes failed attempts with error reason
- Pull-to-refresh AND Sync Now button both available

### Error Surfacing
- Errors persist until resolved or dismissed (no auto-dismiss)
- User-friendly message shown, technical details available on tap
- Auth errors (401/403) prompt re-login with action: "Session expired, sign in again"
- Distinguish network errors ("No connection") from server errors ("Server error, try again later")
- Escalate visibility after 3+ failures — more prominent, suggest action

### Progress Feedback
- Count-based progress: "Syncing 3 of 5..." with determinate count
- Progress bar + count shown together
- Cancelable with partial success (keep already-synced, queue rest)
- Combined progress for all sync types (HealthKit + events together)
- "All synced" checkmark appears briefly, then hides
- Launch sync is non-blocking — app loads fully, sync happens async with indicator
- Floating indicator always appears when any sync starts
- Pull-to-refresh: inline spinner triggers, then floating shows progress
- New data from server animates in or highlights briefly

### Claude's Discretion
- Exact visual style (pill vs toast banner)
- Floating element position (top vs bottom)
- Auto-dismiss timing for success state
- Haptic feedback choices
- Tap behavior for collapsed icon
- Retry granularity (all vs individual)
- Skip option for permanently failing items
- ETA display for large syncs
- Stale data warning threshold

</decisions>

<specifics>
## Specific Ideas

- Smooth morphing animation when state changes (e.g., offline to syncing)
- Use existing app palette colors — don't introduce new colors
- iOS accessibility: respect reduce motion setting

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-ux-indicators*
*Context gathered: 2026-01-17*
