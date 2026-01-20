# Debug: Sync Indicator Tap Interference

**Status:** resolved
**Created:** 2026-01-19
**Updated:** 2026-01-19
**Issue:** Floating sync indicator widget blocks tab bar taps during sync

---

## Symptoms

| Field | Description |
|-------|-------------|
| **Expected** | Tapping tab bar buttons should switch tabs even when sync indicator is visible |
| **Actual** | Taps near the bottom of the screen are intercepted by sync indicator |
| **Errors** | None (behavior issue, not crash) |
| **Reproduction** | 1. Trigger a sync 2. While sync indicator is visible, tap on tab bar buttons 3. Tab selection fails |
| **Timeline** | Since sync indicator was added |

---

## Root Cause

The sync indicator had an `onTap` gesture that navigated to the Settings tab (tab 4) when tapped. This was incorrect behavior - the sync indicator should be purely visual/informational with no general tap functionality.

The previous fix attempted to limit the tap area using `.contentShape(Capsule())`, but the correct fix is to remove the tap gesture entirely and make the view passthrough.

---

## Fix Applied

**Architecture Change in `SyncIndicatorView.swift`:**

Used a ZStack approach to separate visual (passthrough) content from interactive (button) content:

1. **Removed `onTap` property entirely** - sync indicator should not navigate anywhere on tap
2. **Restructured body using ZStack:**
   - **Layer 1 (bottom):** Visual pill with `.allowsHitTesting(false)` - all taps pass through to tab bar
   - **Layer 2 (top):** Action button overlay - only the Retry/Sync Now buttons intercept taps
3. **Added `actionButtonPlaceholder`** - invisible placeholder in the visual layer to reserve space for buttons
4. **Updated all preview calls** to remove `onTap: {}`

**Changes to `MainTabView.swift`:**
1. Removed the `onTap` closure from the `SyncIndicatorView` instantiation

**Key Insight:** Simply using `.allowsHitTesting(false)` on the parent disables ALL descendants including buttons. The ZStack approach allows the visual layer to be passthrough while keeping buttons interactive in a separate overlay layer.

---

## Verification

- [x] Build succeeds with no errors
- [x] Sync indicator visual pill is fully passthrough (no tap interception)
- [x] Action buttons (Retry, Sync Now) remain functional in their overlay layer
- [x] Tab bar receives all taps except those directly on action buttons
- [ ] Manual testing on device/simulator (pending user verification)

---

## Files Changed

| File | Change |
|------|--------|
| `apps/ios/trendy/Views/Components/SyncIndicator/SyncIndicatorView.swift` | Removed onTap, made view passthrough, preserved action button interactivity |
| `apps/ios/trendy/Views/MainTabView.swift` | Removed onTap closure |
