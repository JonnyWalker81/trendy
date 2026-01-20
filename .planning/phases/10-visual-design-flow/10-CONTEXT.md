# Phase 10: Visual Design & Flow - Context

**Gathered:** 2026-01-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Polished onboarding experience for new users with modern visual design, smooth transitions, and a well-ordered flow. The flow order is Welcome → Auth → Permissions. This phase covers layouts, animations, progress indication, and pre-permission priming screens. Accessibility is handled in Phase 11.

</domain>

<decisions>
## Implementation Decisions

### Screen layouts
- Full-bleed hero layout with large visual at top, content below
- Hero area uses SF Symbols with gradient backgrounds (not custom illustrations or Lottie)
- Minimal text density: bold headline + single sentence per screen
- Dark mode native aesthetic with deep backgrounds and glowing accents
- Respects system light/dark mode preference (not dark-only)
- Primary action button pinned at bottom of screen (always visible)

### Transition animations
- Horizontal slide transitions between screens (classic left/right)
- Swipe gestures enabled for navigation (both directions)
- Snappy timing: 0.2-0.3 second duration
- Spring animation curve (bouncy, iOS-native feel)
- Haptic feedback on Continue button tap, then transition

### Progress indicator
- Progress bar style (not dots or step numbers)
- Positioned at top of screen, below safe area
- Smooth fill animation when advancing (~0.3s)
- Display only — not interactive/tappable
- Accent/brand color for filled portion
- Visible track showing unfilled portion (gray/muted)

### Permission priming
- Full screen priming screens (same layout as other onboarding)
- Both notifications and location permissions get priming screens
- Subtle text link for Skip option (not prominent)
- Brief inline text explains what user misses when skipping
- Button text: "Enable [Permission]" (explicit about what's next)
- After denial: show "You can enable this in Settings later" message, then continue

### Claude's Discretion
- SF Symbol sizing/weight per screen
- Secondary action styling (text link vs ghost button)
- Staggered element animation within screens
- Celebration animation style on completion
- Hero symbol animation (subtle pulse/glow vs static)
- Step count text presence alongside progress bar
- Progress bar thickness
- Permission benefit messaging tone

</decisions>

<specifics>
## Specific Ideas

No specific product references mentioned — open to standard iOS patterns with the aesthetic direction captured above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 10-visual-design-flow*
*Context gathered: 2026-01-20*
