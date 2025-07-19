# Trendy App Code Walkthrough

## Overview
Trendy is an iOS event tracking app built with SwiftUI and SwiftData. It allows users to quickly log events, import from their calendar, and visualize patterns through analytics.

## 1. App Architecture & Entry Point

### trendyApp.swift
```swift
@main
struct trendyApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Event.self, EventType.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        // Creates the SwiftData container
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .environment(EventStore(modelContext: sharedModelContainer.mainContext))
    }
}
```

**Key Points:**
- `@main` marks the app entry point
- Creates a SwiftData `ModelContainer` with our data models
- Injects the `EventStore` as an environment object
- All views can access data through the environment

## 2. Data Models (SwiftData)

### Event.swift
```swift
@Model
final class Event {
    var id: UUID
    var timestamp: Date
    var notes: String?
    var eventType: EventType?
    var sourceType: EventSourceType
    var externalId: String?
    var originalTitle: String?
    var isAllDay: Bool = false
    var endDate: Date?
}
```

**Features:**
- `@Model` macro makes it SwiftData compatible
- Tracks when events occur (`timestamp`)
- Links to event types (categories)
- Supports imported calendar events
- Handles all-day and multi-day events

### EventType.swift
```swift
@Model
final class Event[Type {
    var id: UUID
    var name: String
    var colorHex: String
    var iconName: String
    @Relationship(deleteRule: .nullify) var events: [Event]?
}
```

**Features:**
- Categories for events (Exercise, Medical, Work, etc.)
- Custom colors and SF Symbol icons
- One-to-many relationship with events
- Cascade delete rule to handle orphaned events

## 3. State Management

### EventStore.swift (Main State Manager)
```swift
@Observable
@MainActor
class EventStore {
    private(set) var events: [Event] = []
    private(set) var eventTypes: [EventType] = []
    private var modelContext: ModelContext?
    
    func createEvent(type: EventType, notes: String? = nil) async {
        let event = Event(timestamp: Date(), eventType: type, notes: notes)
        modelContext.insert(event)
        try modelContext.save()
        await fetchData()
    }
}
```

**Key Concepts:**
- `@Observable` macro for SwiftUI integration
- `@MainActor` ensures UI updates on main thread
- Central place for all data operations
- Automatic UI updates when data changes

## 4. View Structure

### ContentView.swift (Tab Navigation)
```swift
struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}
```

### MainTabView.swift
```swift
TabView {
    BubblesView()
        .tabItem { Label("Track", systemImage: "circle.grid.2x2") }
    
    EventListView()
        .tabItem { Label("Events", systemImage: "list.bullet") }
    
    CalendarView()
        .tabItem { Label("Calendar", systemImage: "calendar") }
    
    AnalyticsView()
        .tabItem { Label("Analytics", systemImage: "chart.line.uptrend.xyaxis") }
    
    SettingsView()
        .tabItem { Label("Settings", systemImage: "gear") }
}
```

## 5. Core Features

### A. Quick Event Tracking (BubblesView)
```swift
LazyVGrid(columns: columns, spacing: 16) {
    ForEach(eventStore.eventTypes) { eventType in
        EventBubbleView(eventType: eventType)
            .onTapGesture {
                // Quick tap records event
                await recordEvent(eventType)
            }
            .onLongPressGesture {
                // Long press adds notes
                showingNoteInput = true
            }
    }
}
```

**User Flow:**
1. Tap a bubble → Instant event creation
2. Long press → Add notes before creating
3. Haptic feedback confirms action

### B. Calendar Import

#### CalendarImportManager.swift
```swift
func requestCalendarAccess() async -> Bool {
    if #available(iOS 17.0, *) {
        hasCalendarAccess = try await eventStore.requestFullAccessToEvents()
    }
}

func fetchEvents(from: Date, to: Date, calendars: [EKCalendar]) async -> [EKEvent] {
    let predicate = eventStore.predicateForEvents(withStart: from, end: to, calendars: calendars)
    return eventStore.events(matching: predicate)
}
```

#### Import Flow:
1. **Permission Request** → Uses EventKit for calendar access
2. **Date Selection** → User picks date range
3. **Calendar Selection** → Choose which calendars
4. **Event Mapping** → Smart categorization by title patterns
5. **Selective Import** → Toggle which events to import

### C. Multi-Level Calendar View

#### Three View Modes:
```swift
enum CalendarViewMode {
    case month  // Detailed daily view
    case quarter // 3-month overview
    case year   // 12-month grid
}
```

#### CompactMonthView.swift
```swift
ForEach(eventTypes.prefix(3)) { eventType in
    Circle()
        .fill(eventType.color)
        .frame(width: 4, height: 4)
}
```
- Shows event type colors
- Scales for different zoom levels
- Tap to zoom into specific dates

### D. Analytics & Visualization

#### AnalyticsViewModel.swift
```swift
func generateStatistics(for eventType: EventType) -> Statistics {
    // Calculate inclusive date range
    let totalDays = daysBetween + 1
    let averagePerDay = Double(totalCount) / Double(totalDays)
    
    // Trend analysis
    let recentDailyAvg = Double(recentEvents.count) / 14.0
    let previousDailyAvg = Double(previousEvents.count) / 14.0
    let percentageChange = ((recentDailyAvg - previousDailyAvg) / previousDailyAvg) * 100
}
```

#### Chart Visualization:
```swift
Chart(data) { dataPoint in
    LineMark(x: .value("Date", dataPoint.date), 
             y: .value("Count", dataPoint.count))
    AreaMark(...) // Filled area under line
    PointMark(...) // Data points
}
```

## 6. Key Design Patterns

### Environment Injection
```swift
@Environment(EventStore.self) private var eventStore
@Environment(\.modelContext) private var modelContext
```
- Clean dependency injection
- Views automatically update with data changes

### State Persistence
```swift
@AppStorage("analyticsSelectedEventTypeId") private var savedEventTypeId: String
```
- Remembers user preferences
- Seamless experience between sessions

### Error Handling
```swift
enum EventError: LocalizedError {
    case saveFailed
    case deleteFailed
    
    var errorDescription: String? {
        switch self {
        case .saveFailed: return "Failed to save event"
        case .deleteFailed: return "Failed to delete event"
        }
    }
}
```

## 7. Performance Optimizations

- **Lazy Loading**: `LazyVGrid` for efficient scrolling
- **Batch Operations**: Import multiple events in one transaction
- **Filtered Queries**: Only load relevant data
- **Async/Await**: Non-blocking UI operations

## 8. User Experience Features

- **Haptic Feedback**: Physical confirmation of actions
- **Search & Filter**: Find events quickly
- **Dark Mode**: Automatic color adaptation
- **Accessibility**: VoiceOver support built-in

## Data Flow Example

1. **User taps bubble** → BubblesView
2. **Create event** → EventStore.createEvent()
3. **Save to database** → ModelContext.save()
4. **Update UI** → @Observable triggers view refresh
5. **Show in calendar** → CalendarView queries updated data
6. **Analytics update** → Charts reflect new event

This architecture ensures:
- Clean separation of concerns
- Reactive UI updates
- Persistent data storage
- Smooth user experience