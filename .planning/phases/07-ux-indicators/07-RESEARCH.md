# Phase 7: UX Indicators - Research

**Researched:** 2026-01-17
**Domain:** SwiftUI UI patterns, animations, sync status visualization
**Confidence:** HIGH

## Summary

This research covers the implementation of sync status UX indicators for the Trendy iOS app. The existing codebase provides a solid foundation with `SyncEngine` (actor managing sync state), `SyncState` enum (with states including `.syncing(synced:total:)`), and `SyncStatusBanner` view (basic implementation). The phase requires enhancing these to deliver the floating indicator pattern with animations, accessibility support, and settings integration specified in CONTEXT.md.

The standard approach uses SwiftUI's built-in animation system with `withAnimation`, spring animations (default in iOS 17+), and the `@Environment(\.accessibilityReduceMotion)` property to honor accessibility settings. For the floating indicator pattern, `.safeAreaInset(edge:)` provides the recommended approach for content that should push other views while respecting safe areas.

**Primary recommendation:** Build on existing `SyncStatusBanner` architecture, extracting state observation into a dedicated `SyncStatusViewModel` and creating new `SyncIndicator` (floating pill), `SyncSettingsView` (settings section), and `SyncHistoryStore` (persisted sync history) components.

## Standard Stack

The established libraries/tools for this domain:

### Core (Built-in SwiftUI)

| Component | Purpose | Why Standard |
|-----------|---------|--------------|
| `@Environment(\.accessibilityReduceMotion)` | Detect reduce motion preference | Apple's official accessibility API |
| `withAnimation(.spring())` | Smooth state transitions | iOS 17+ default, physics-based motion |
| `.safeAreaInset(edge:)` | Floating indicator positioning | Proper safe area management |
| `RelativeDateTimeFormatter` | "5 min ago" timestamps | Localized, system-standard |
| `@Observable` / `@State` | View state management | SwiftUI standard pattern |

### Supporting (Already in Codebase)

| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `SyncState` enum | Sync state representation | Already defined in `SyncEngine.swift` |
| `SyncEngine` actor | Sync orchestration | State source, no changes needed |
| `EventStore` | Cached sync state (`currentSyncState`, etc.) | UI binding source |
| Design System Colors | `Color.dsSuccess`, `Color.dsWarning`, etc. | Semantic colors defined in `Colors.swift` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `.safeAreaInset` | `.overlay` with manual offset | Manual safe area handling, less robust |
| `RelativeDateTimeFormatter` | Custom "time ago" logic | More control but lose localization |
| Spring animations | `.easeInOut` curves | Less natural feel, but simpler |

**No additional dependencies required.** All functionality achievable with SwiftUI built-ins and existing codebase infrastructure.

## Architecture Patterns

### Recommended Component Structure

```
Views/
├── Components/
│   ├── SyncStatusBanner.swift      # EXISTING - enhance
│   └── SyncIndicator/
│       ├── SyncIndicatorView.swift # NEW - floating pill
│       └── SyncProgressBar.swift   # NEW - determinate progress
├── Settings/
│   └── SyncSettingsView.swift      # NEW - sync section in settings
Services/
└── Sync/
    └── SyncHistoryStore.swift      # NEW - persisted history
ViewModels/
└── SyncStatusViewModel.swift       # NEW - extracted state logic
```

### Pattern 1: Observable State Propagation

**What:** Extract sync state observation from views into dedicated ViewModel
**When to use:** When multiple views need the same sync state
**Example:**
```swift
// Source: Standard SwiftUI @Observable pattern
@Observable
@MainActor
final class SyncStatusViewModel {
    private(set) var state: SyncState = .idle
    private(set) var pendingCount: Int = 0
    private(set) var lastSyncTime: Date?
    private(set) var failureCount: Int = 0
    private(set) var isOnline: Bool = true

    // Derived properties for UI
    var shouldShowIndicator: Bool {
        switch state {
        case .syncing, .pulling, .error, .rateLimited:
            return true
        case .idle:
            return pendingCount > 0 || !isOnline
        }
    }

    func refresh(from eventStore: EventStore) async {
        state = eventStore.currentSyncState
        pendingCount = eventStore.currentPendingCount
        lastSyncTime = eventStore.currentLastSyncTime
        isOnline = eventStore.isOnline
    }
}
```

### Pattern 2: Floating Indicator with safeAreaInset

**What:** Floating pill that appears only when needed, pushing content
**When to use:** Sync status that shouldn't cover content but needs visibility
**Example:**
```swift
// Source: SwiftUI safeAreaInset documentation pattern
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showIndicator = false

    var body: some View {
        MainContent()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showIndicator {
                    SyncIndicatorView()
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8), value: showIndicator)
    }
}
```

### Pattern 3: Accessibility-Aware Animation

**What:** Respect system "Reduce Motion" setting
**When to use:** All animations in the app
**Example:**
```swift
// Source: Apple Accessibility documentation
extension View {
    func animateWithMotionPreference<V: Equatable>(
        value: V,
        reduceMotion: Bool
    ) -> some View {
        self.animation(
            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
            value: value
        )
    }
}

// Usage
SyncIndicatorView()
    .animateWithMotionPreference(value: syncState, reduceMotion: reduceMotion)
```

### Pattern 4: State Machine Transitions

**What:** Smooth morphing between states (offline -> syncing -> synced)
**When to use:** Multi-state indicators with animated transitions
**Example:**
```swift
// Existing SyncState enum in codebase - use for UI state machine
enum SyncIndicatorDisplayState: Equatable {
    case hidden
    case offline(pending: Int)
    case syncing(current: Int, total: Int)
    case error(message: String, canRetry: Bool)
    case success // Brief checkmark before hiding

    static func from(syncState: SyncState, pendingCount: Int, isOnline: Bool) -> Self {
        if !isOnline {
            return .offline(pending: pendingCount)
        }
        switch syncState {
        case .idle where pendingCount == 0:
            return .hidden
        case .idle:
            return .offline(pending: pendingCount)
        case .syncing(let synced, let total):
            return .syncing(current: synced, total: total)
        case .pulling:
            return .syncing(current: 0, total: 0) // Indeterminate
        case .rateLimited(_, let pending):
            return .error(message: "Rate limited", canRetry: true)
        case .error(let message):
            return .error(message: message, canRetry: true)
        }
    }
}
```

### Anti-Patterns to Avoid

- **Blocking animations:** Never use `Task.sleep` or timers to sequence UI updates - use SwiftUI's animation system
- **Ignoring reduce motion:** Always check `accessibilityReduceMotion` before applying animations
- **Polling state in views:** Use `@Observable` propagation, not `Timer` polling in views
- **Hard-coded colors:** Use design system tokens (`Color.dsSuccess`, `Color.dsWarning`, etc.)
- **Covering content:** Don't use `.overlay` for persistent indicators - use `.safeAreaInset`

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| "5 min ago" formatting | Custom string interpolation | `RelativeDateTimeFormatter` | Localization, edge cases (plural forms, languages) |
| Spring physics | Manual easing curves | `.spring(response:dampingFraction:)` | iOS 17+ default, tested parameters |
| Safe area handling | Manual bottom padding | `.safeAreaInset(edge:)` | Handles all device types, dynamic island, home indicator |
| State propagation | NotificationCenter | `@Observable` + `@Environment` | Type-safe, SwiftUI-native |
| Motion preference | Custom UserDefaults | `@Environment(\.accessibilityReduceMotion)` | System-synced, no manual listening |

**Key insight:** SwiftUI provides accessibility and animation primitives that handle edge cases (localization, device differences, user preferences) automatically. Rolling custom solutions creates maintenance burden and accessibility gaps.

## Common Pitfalls

### Pitfall 1: Animation State Mismatch

**What goes wrong:** Animation doesn't complete because state changes mid-animation
**Why it happens:** SwiftUI animation tied to view lifecycle, not animation completion
**How to avoid:** Use explicit state machine with "success" intermediate state, auto-dismiss after delay
**Warning signs:** Indicators "flash" or jump to final state

```swift
// Correct pattern: explicit success state with auto-dismiss
case .synced:
    return .success // Shows checkmark
    // After 2 seconds, transition to .hidden

// In view:
.onChange(of: displayState) { _, newState in
    if case .success = newState {
        Task {
            try? await Task.sleep(for: .seconds(2))
            displayState = .hidden // Triggers hide animation
        }
    }
}
```

### Pitfall 2: Reduce Motion Ignored for Transitions

**What goes wrong:** `.transition()` animations still play when reduce motion enabled
**Why it happens:** `transition` and `animation` are separate - both need accessibility handling
**How to avoid:** Conditionally set both animation AND transition based on reduce motion
**Warning signs:** Elements slide in/out even with reduce motion enabled

```swift
// Correct pattern
.transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
.animation(reduceMotion ? nil : .spring(), value: showIndicator)
```

### Pitfall 3: RelativeDateTimeFormatter Memory Allocation

**What goes wrong:** Formatter recreated every render, causing memory churn
**Why it happens:** Creating formatter inline in `body`
**How to avoid:** Create formatter once as static or in init
**Warning signs:** High allocations in Instruments during idle

```swift
// Wrong
var body: some View {
    let formatter = RelativeDateTimeFormatter() // Recreated every render!
    Text(formatter.localizedString(for: date, relativeTo: Date()))
}

// Correct
static let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()
```

### Pitfall 4: Stale Cached Sync State

**What goes wrong:** UI shows old state after sync completes
**Why it happens:** Cached `currentSyncState` in `EventStore` not refreshed
**How to avoid:** Ensure `refreshSyncStateForUI()` called after all state changes
**Warning signs:** Indicator stuck in "syncing" state after sync completes

```swift
// EventStore already has this pattern - ensure it's called
await syncEngine.performSync()
await refreshSyncStateForUI() // Critical - update cached state
```

### Pitfall 5: Sync History Unbounded Growth

**What goes wrong:** Sync history storage grows indefinitely
**Why it happens:** No limit on stored history entries
**How to avoid:** Cap at N entries (e.g., 10), prune oldest on insert
**Warning signs:** UserDefaults/SwiftData bloat over time

## Code Examples

Verified patterns from official sources and codebase analysis:

### Relative Time Display with Tap-to-Absolute

```swift
// Pattern: Show relative by default, absolute on tap
struct RelativeTimestampView: View {
    let date: Date
    @State private var showAbsolute = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        Text(showAbsolute
            ? Self.absoluteFormatter.string(from: date)
            : Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))
            .font(.caption)
            .foregroundStyle(Color.dsMutedForeground)
            .onTapGesture {
                showAbsolute.toggle()
            }
    }
}
```

### Floating Pill Indicator

```swift
// Based on: existing SyncStatusBanner + safeAreaInset pattern
struct SyncIndicatorPill: View {
    let displayState: SyncIndicatorDisplayState
    let onTap: () -> Void
    let onRetry: () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            statusText
            Spacer()
            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onTapGesture(perform: onTap)
    }

    private var backgroundColor: Color {
        switch displayState {
        case .hidden, .success:
            return Color.dsSuccess.opacity(0.95)
        case .offline:
            return Color.dsWarning.opacity(0.95)
        case .syncing:
            return Color.dsPrimary.opacity(0.95)
        case .error:
            return Color.dsDestructive.opacity(0.95)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch displayState {
        case .hidden:
            EmptyView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.dsSuccessForeground)
        case .offline:
            Image(systemName: "wifi.slash")
                .foregroundStyle(Color.dsWarningForeground)
        case .syncing:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.dsPrimaryForeground)
                .scaleEffect(0.8)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.dsDestructiveForeground)
        }
    }

    // ... statusText, actionButton implementations
}
```

### Determinate Progress Bar

```swift
// Pattern: Combined progress bar + count display
struct SyncProgressView: View {
    let current: Int
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Syncing \(current) of \(total)")
                .font(.subheadline)
                .foregroundStyle(Color.dsPrimaryForeground)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)

                    // Progress fill
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geometry.size.width * progress, height: 4)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: progress)
                }
            }
            .frame(height: 4)
        }
    }
}
```

### Error with Tap-to-Expand

```swift
// Pattern: User-friendly message, technical details on tap
struct SyncErrorView: View {
    let userMessage: String
    let technicalDetails: String?
    let onRetry: () async -> Void

    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.dsDestructive)

                Text(userMessage)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Button("Retry") {
                    Task { await onRetry() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if showDetails, let details = technicalDetails {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(Color.dsMutedForeground)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.dsDestructive.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showDetails.toggle()
            }
        }
    }
}
```

### Sync History Entry Model

```swift
// Pattern: Persisted sync history with UserDefaults
struct SyncHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let eventsCount: Int
    let eventTypesCount: Int
    let geofencesCount: Int
    let status: Status
    let errorMessage: String?
    let durationMs: Int

    enum Status: String, Codable {
        case success
        case partialSuccess
        case failed
    }

    var summary: String {
        var parts: [String] = []
        if eventsCount > 0 { parts.append("\(eventsCount) events") }
        if eventTypesCount > 0 { parts.append("\(eventTypesCount) event types") }
        if geofencesCount > 0 { parts.append("\(geofencesCount) geofences") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}

@Observable
final class SyncHistoryStore {
    private static let storageKey = "sync_history"
    private static let maxEntries = 10

    private(set) var entries: [SyncHistoryEntry] = []

    init() {
        loadFromStorage()
    }

    func record(_ entry: SyncHistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        saveToStorage()
    }

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SyncHistoryEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func saveToStorage() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Linear animations default | Spring animations default | iOS 17 | More natural feel |
| Custom safe area handling | `.safeAreaInset(edge:)` | iOS 15 | Simpler, more robust |
| Manual accessibility checks | `@Environment(\.accessibilityReduceMotion)` | iOS 14 | Automatic system sync |
| Formatter in `body` | Static formatters | SwiftUI best practice | Performance |

**Deprecated/outdated:**
- `.animation()` without `value:` parameter - deprecated, causes unexpected animations
- Manual bottom padding for floating elements - use `.safeAreaInset` instead
- `UIAccessibility.isReduceMotionEnabled` - use SwiftUI environment instead

## Open Questions

None requiring resolution before planning. The codebase provides all necessary infrastructure.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `SyncEngine.swift`, `SyncStatusBanner.swift`, `EventStore.swift`, `Colors.swift`
- SwiftUI safeAreaInset documentation
- Apple Accessibility documentation for Reduce Motion

### Secondary (MEDIUM confidence)
- [Hacking with Swift - Reduce Motion](https://www.hackingwithswift.com/quick-start/swiftui/how-to-reduce-animations-when-requested)
- [Hacking with Swift - safeAreaInset](https://www.hackingwithswift.com/quick-start/swiftui/how-to-inset-the-safe-area-with-custom-content)
- [Create with Swift - Safe Area Inset](https://www.createwithswift.com/placing-ui-components-within-the-safe-area-inset/)
- [SwiftUI Animation Masterclass 2025](https://dev.to/sebastienlato/swiftui-animation-masterclass-springs-curves-smooth-motion-3e4o)

### Tertiary (LOW confidence)
- N/A - all findings verified with official sources or codebase

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all components are SwiftUI built-ins or exist in codebase
- Architecture: HIGH - patterns align with existing codebase conventions
- Pitfalls: HIGH - derived from codebase analysis and verified documentation

**Research date:** 2026-01-17
**Valid until:** 2026-03-17 (stable SwiftUI patterns, no expected breaking changes)
