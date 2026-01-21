# Phase 11: Accessibility - Context

**Gathered:** 2026-01-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the existing onboarding flow accessible to VoiceOver users and respect motion preferences. All screens built in Phase 10 need accessibility modifiers added. No new UI or features — this phase adds accessibility support to what exists.

</domain>

<decisions>
## Implementation Decisions

### VoiceOver Labels
- Contextual labels on buttons: "Continue to permissions", "Skip notification setup" — not just "Continue" or "Skip"
- Hero images and decorative icons marked as `.accessibilityHidden(true)` — VoiceOver skips them
- Accessibility hints on ALL buttons explaining what happens next
- Progress bar announces "Permissions, step 3 of 6" (step name + count)

### Focus Order
- Auto-focus step heading/title when transitioning between onboarding steps
- Use `.accessibilityFocused()` binding to move focus on step changes

### Claude's Discretion
- Grouping strategy for permission priming screens (benefits together vs individual)
- Escape/back action hints based on iOS conventions
- Pre-announcement strategy for system permission dialogs
- Reduce Motion transition style (instant vs crossfade) per Apple HIG
- Confetti alternative when Reduce Motion enabled
- Pulsing icon behavior with Reduce Motion (disable vs keep)
- Progress bar animation with Reduce Motion
- Overall accessibility depth (WCAG AA vs premium)
- Dynamic Type testing scope
- Color contrast verification scope
- Verification approach (manual walkthrough vs code review)

</decisions>

<specifics>
## Specific Ideas

- VoiceOver labels should feel natural, not robotic — "Continue to set up notifications" reads better than "Button: continue notification setup"
- When focus moves to heading on step change, user immediately knows where they are

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 11-accessibility*
*Context gathered: 2026-01-20*
