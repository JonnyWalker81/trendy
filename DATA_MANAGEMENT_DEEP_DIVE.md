# Trendy App: Data Management Deep Dive

## Table of Contents
1. [SwiftData Overview](#swiftdata-overview)
2. [Data Storage Location](#data-storage-location)
3. [Data Persistence & Durability](#data-persistence--durability)
4. [Core Components](#core-components)
5. [Data Flow Architecture](#data-flow-architecture)
6. [Transaction Management](#transaction-management)
7. [Data Relationships](#data-relationships)
8. [Migration & Schema Evolution](#migration--schema-evolution)
9. [Performance Considerations](#performance-considerations)
10. [Backup & Recovery](#backup--recovery)

## SwiftData Overview

SwiftData is Apple's modern persistence framework introduced in iOS 17. It's built on top of Core Data but provides a more Swift-native API. Here's how Trendy uses it:

### Key Characteristics:
- **Declarative**: Uses Swift macros like `@Model`
- **Type-safe**: Compile-time checking of queries
- **Automatic UI updates**: Works seamlessly with SwiftUI
- **Built on SQLite**: Inherits Core Data's proven storage engine

## Data Storage Location

### Primary Storage Path
```
/var/mobile/Containers/Data/Application/{APP_UUID}/Library/Application Support/default.store
```

This translates to:
- **iOS Device**: `~/Library/Application Support/default.store`
- **iOS Simulator**: `~/Library/Developer/CoreSimulator/Devices/{DEVICE_ID}/data/Containers/Data/Application/{APP_UUID}/Library/Application Support/default.store`

### Storage Structure
```
default.store (SQLite database)
├── ZEVENT table (Event model)
├── ZEVENTTYPE table (EventType model)
├── Metadata tables (Z_METADATA, Z_MODELCACHE)
└── Index tables (for relationships and queries)
```

## Data Persistence & Durability

### Persistence Guarantees

1. **Write-Ahead Logging (WAL)**
   - SwiftData/Core Data uses SQLite's WAL mode
   - Changes are first written to a log file
   - Provides crash recovery and better concurrency
   - Files: `default.store`, `default.store-wal`, `default.store-shm`

2. **ACID Compliance**
   - **Atomicity**: All changes in a save() succeed or fail together
   - **Consistency**: Data integrity rules are enforced
   - **Isolation**: Concurrent operations don't interfere
   - **Durability**: Saved data survives app/system crashes

3. **Durability Levels**
   ```swift
   // In trendyApp.swift
   let modelConfiguration = ModelConfiguration(
       schema: schema, 
       isStoredInMemoryOnly: false  // FALSE = Persistent to disk
   )
   ```

### Data Lifecycle
```
User Action → Model Change → ModelContext (in-memory) → save() → SQLite → Disk
                                    ↑                         ↓
                                    └──── Rollback on error ←─┘
```

## Core Components

### 1. ModelContainer (trendyApp.swift)
```swift
var sharedModelContainer: ModelContainer = {
    let schema = Schema([
        Event.self,
        EventType.self
    ])
    let modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false
    )
    
    do {
        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    } catch {
        fatalError("Could not create ModelContainer: \(error)")
    }
}()
```

**Responsibilities:**
- Manages the persistent store coordinator
- Handles schema registration
- Creates model contexts
- Controls storage location and options

### 2. ModelContext
```swift
// Injected via environment
@Environment(\.modelContext) private var modelContext

// Or via EventStore
class EventStore {
    private var modelContext: ModelContext?
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }
}
```

**Responsibilities:**
- Manages object lifecycle
- Tracks changes (insertions, updates, deletions)
- Handles save operations
- Provides query interface

### 3. EventStore (ViewModels/EventStore.swift)
```swift
@Observable
@MainActor
class EventStore {
    private(set) var events: [Event] = []
    private(set) var eventTypes: [EventType] = []
    private var modelContext: ModelContext?
    
    func fetchData() async {
        guard let modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<Event>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            events = try modelContext.fetch(descriptor)
            
            let typeDescriptor = FetchDescriptor<EventType>(
                sortBy: [SortDescriptor(\.name)]
            )
            eventTypes = try modelContext.fetch(typeDescriptor)
        } catch {
            print("Failed to fetch data: \(error)")
        }
    }
    
    func createEvent(type: EventType, notes: String? = nil) async {
        guard let modelContext else { return }
        
        let event = Event(
            timestamp: Date(),
            eventType: type,
            notes: notes
        )
        
        modelContext.insert(event)
        
        do {
            try modelContext.save()
            await fetchData() // Refresh local cache
        } catch {
            errorMessage = EventError.saveFailed.localizedDescription
        }
    }
}
```

## Data Flow Architecture

### Create Operation
```
1. User taps bubble in BubblesView
   ↓
2. BubblesView calls eventStore.createEvent()
   ↓
3. EventStore creates new Event instance
   ↓
4. modelContext.insert(event) - Stages for insertion
   ↓
5. modelContext.save() - Persists to SQLite
   ↓
6. fetchData() - Refreshes in-memory cache
   ↓
7. @Published updates trigger UI refresh
```

### Read Operation
```
1. View appears (e.g., CalendarView)
   ↓
2. .task { await eventStore.fetchData() }
   ↓
3. FetchDescriptor creates SQL query
   ↓
4. modelContext.fetch() executes query
   ↓
5. Results loaded into memory
   ↓
6. @Published arrays update
   ↓
7. SwiftUI re-renders with new data
```

### Update Operation
```
1. User modifies event (e.g., adds note)
   ↓
2. Direct property modification: event.notes = "New note"
   ↓
3. ModelContext tracks as "dirty" object
   ↓
4. modelContext.save() persists changes
   ↓
5. SQLite UPDATE statement executed
```

### Delete Operation
```
1. User swipes to delete in EventListView
   ↓
2. eventStore.deleteEvent(event)
   ↓
3. modelContext.delete(event)
   ↓
4. Relationship cleanup (nullify eventType reference)
   ↓
5. modelContext.save() commits deletion
```

## Transaction Management

### Save Operation Details
```swift
do {
    try modelContext.save()
    // All changes committed atomically
} catch {
    // All changes rolled back
    // ModelContext returns to pre-save state
}
```

### Batch Operations
```swift
// Calendar import example
for mapping in eventTypeMappings where mapping.isSelected {
    for calendarEvent in mapping.calendarEvents {
        let newEvent = Event(...)
        modelContext.insert(newEvent)
        // No save() here - batching inserts
    }
}
// Single save() for all events - atomic operation
try modelContext.save()
```

### Concurrency
- `@MainActor` ensures all EventStore operations happen on main thread
- Prevents race conditions and data corruption
- SwiftData handles background queue coordination internally

## Data Relationships

### EventType ← → Event Relationship
```swift
// EventType.swift
@Relationship(deleteRule: .nullify) var events: [Event]?

// Event.swift
var eventType: EventType?
```

**Behavior:**
- Bidirectional relationship
- `.nullify` rule: Deleting EventType sets Event.eventType to nil
- Prevents orphaned events
- Maintains referential integrity

### Relationship Management in Code
```swift
// Creating event with relationship
let event = Event(
    timestamp: Date(),
    eventType: type,  // Relationship established here
    notes: notes
)

// Querying by relationship
func events(for eventType: EventType) -> [Event] {
    events.filter { $0.eventType?.id == eventType.id }
}
```

## Migration & Schema Evolution

### Current Migration Handling
```swift
// Event.swift - Migration fix example
var isAllDay: Bool = false  // Default value for migration
var endDate: Date?         // Optional for backward compatibility
```

### Migration Process
1. **Schema Change Detection**: SwiftData detects model changes
2. **Lightweight Migration**: Automatic for simple changes (add optional property)
3. **Heavy Migration**: Required for complex changes (would need custom logic)

### Migration Error Example (from logs)
```
Error Domain=NSCocoaErrorDomain Code=134110 
"An error occurred during persistent store migration."
reason=Validation error missing attribute values on mandatory destination attribute
```

**Solution**: Provide default values for new non-optional properties

## Performance Considerations

### 1. Lazy Loading
```swift
// EventStore fetches all data upfront
let descriptor = FetchDescriptor<Event>(
    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
)
events = try modelContext.fetch(descriptor)
```

**Trade-offs:**
- ✅ Simple mental model
- ✅ Fast UI updates
- ❌ Memory usage scales with data size
- ❌ Initial load time increases

### 2. Indexing
SwiftData automatically creates indexes for:
- Primary keys (id)
- Relationship foreign keys (eventType)
- Sort descriptors used in queries

### 3. Query Optimization
```swift
// Efficient: Single query with sorting
let descriptor = FetchDescriptor<Event>(
    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
)

// Inefficient: Fetch all then sort in memory
let events = try modelContext.fetch(FetchDescriptor<Event>())
let sorted = events.sorted { $0.timestamp > $1.timestamp }
```

### 4. Memory Management
- SwiftData uses faulting (lazy loading of properties)
- Large strings (notes) are loaded on access
- Relationships are loaded when traversed

## Backup & Recovery

### Automatic Backups
1. **iCloud Backup**: Included by default if user has iCloud Backup enabled
2. **iTunes/Finder Backup**: Included in device backups
3. **Location**: App's Documents and Library directories are backed up

### Data Recovery Scenarios

#### App Crash During Save
```
1. WAL (Write-Ahead Log) preserves uncommitted changes
2. On next launch, SQLite recovers from WAL
3. Data integrity maintained
```

#### Device Restore
```
1. Install app on new device
2. Restore from iCloud/iTunes backup
3. default.store file is restored
4. All data available immediately
```

#### Corrupted Database
```swift
// Current implementation (trendyApp.swift)
} catch {
    fatalError("Could not create ModelContainer: \(error)")
}

// Better approach for production:
} catch {
    // 1. Log error
    // 2. Attempt recovery
    // 3. Create fresh database if unrecoverable
    // 4. Notify user of data loss
}
```

### Manual Backup Strategy
```swift
// Potential enhancement - Export functionality
func exportData() -> Data {
    let export = [
        "events": events.map { /* convert to dictionary */ },
        "eventTypes": eventTypes.map { /* convert to dictionary */ }
    ]
    return try! JSONEncoder().encode(export)
}
```

## Best Practices Implemented

1. **Single Source of Truth**: EventStore manages all data operations
2. **Atomic Operations**: Batch saves for related changes
3. **Error Handling**: Graceful failure with user feedback
4. **Consistency**: Relationships maintain referential integrity
5. **Performance**: Appropriate indexes and query optimization

## Potential Improvements

1. **Pagination**: For large datasets
   ```swift
   let descriptor = FetchDescriptor<Event>(
       predicate: #Predicate { $0.timestamp > cutoffDate },
       sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
       fetchLimit: 100
   )
   ```

2. **Background Processing**: Move heavy operations off main thread
   ```swift
   await MainActor.run {
       // UI updates only
   }
   ```

3. **Data Validation**: Add model-level constraints
   ```swift
   @Model
   final class Event {
       @Attribute(.unique) var externalId: String?
   }
   ```

4. **Conflict Resolution**: For future sync features
   ```swift
   @Attribute(.preserveValueOnDeletion) var lastModified: Date
   ```

## Summary

Trendy's data management system provides:
- **Reliable persistence** via SQLite and WAL
- **ACID compliance** for data integrity  
- **Automatic UI updates** through @Observable
- **Simple API** hiding complex persistence details
- **Good performance** for typical usage patterns
- **Crash resilience** and backup support

The architecture scales well for personal tracking apps while remaining maintainable and extensible.