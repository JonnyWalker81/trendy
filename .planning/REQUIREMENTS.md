# Requirements: Trendy v1.1 Onboarding Overhaul

**Defined:** 2026-01-19
**Core Value:** Effortless tracking — users should set up once and forget about it

## v1.1 Requirements

Requirements for the onboarding overhaul. Each maps to roadmap phases.

### State Management

- [ ] **STATE-01**: Onboarding completion status stored in backend database (source of truth)
- [ ] **STATE-02**: Backend endpoint to get/set user's onboarding status
- [ ] **STATE-03**: Local cache of onboarding status for fast app launches
- [ ] **STATE-04**: App determines launch state from local cache before any UI renders (no flash)
- [ ] **STATE-05**: Single enum-based route state (`loading`, `onboarding`, `authenticated`)
- [ ] **STATE-06**: Returning users never see onboarding screens
- [ ] **STATE-07**: Unauthenticated returning users go directly to login
- [ ] **STATE-08**: Replace NotificationCenter routing with shared Observable
- [ ] **STATE-09**: Sync onboarding status from backend on login (updates local cache)

### Visual Design

- [ ] **DESIGN-01**: Modern layouts for all onboarding screens
- [ ] **DESIGN-02**: Consistent design language throughout flow
- [ ] **DESIGN-03**: Single loading view matching Launch Screen aesthetic
- [ ] **DESIGN-04**: PhaseAnimator/KeyframeAnimator for polished step transitions
- [ ] **DESIGN-05**: Progress indicator showing steps remaining
- [ ] **DESIGN-06**: Celebration animation on onboarding completion

### Flow & UX

- [ ] **FLOW-01**: Flow order is Welcome → Auth → Permissions
- [ ] **FLOW-02**: Pre-permission priming screens explain value before system dialog
- [ ] **FLOW-03**: Skip option available with explanation of what user will miss
- [ ] **FLOW-04**: Each permission request has contextual benefit messaging

### Accessibility

- [ ] **A11Y-01**: All onboarding screens support VoiceOver
- [ ] **A11Y-02**: Animations respect `accessibilityReduceMotion` preference

## Future Requirements

Deferred to later milestones. Tracked but not in current roadmap.

### Enhanced Personalization

- **PERS-01**: Value-first flow (let user try before requiring auth)
- **PERS-02**: Contextual permission requests (defer to first feature use)
- **PERS-03**: First event celebration with confetti

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Tutorial videos | Near 100% skip rate; static screens sufficient |
| Mandatory email verification before access | 27% never verify; blocks users |
| 5+ static intro screens | Causes abandonment; keep concise |
| Value-first flow (try before auth) | Significant architecture change; defer to v1.2 |
| Contextual permission requests | Requires feature flags and analytics; defer |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| STATE-01 | TBD | Pending |
| STATE-02 | TBD | Pending |
| STATE-03 | TBD | Pending |
| STATE-04 | TBD | Pending |
| STATE-05 | TBD | Pending |
| STATE-06 | TBD | Pending |
| STATE-07 | TBD | Pending |
| STATE-08 | TBD | Pending |
| STATE-09 | TBD | Pending |
| DESIGN-01 | TBD | Pending |
| DESIGN-02 | TBD | Pending |
| DESIGN-03 | TBD | Pending |
| DESIGN-04 | TBD | Pending |
| DESIGN-05 | TBD | Pending |
| DESIGN-06 | TBD | Pending |
| FLOW-01 | TBD | Pending |
| FLOW-02 | TBD | Pending |
| FLOW-03 | TBD | Pending |
| FLOW-04 | TBD | Pending |
| A11Y-01 | TBD | Pending |
| A11Y-02 | TBD | Pending |

**Coverage:**
- v1.1 requirements: 21 total
- Mapped to phases: 0
- Unmapped: 21 (pending roadmap)

---
*Requirements defined: 2026-01-19*
*Last updated: 2026-01-19 after initial definition*
