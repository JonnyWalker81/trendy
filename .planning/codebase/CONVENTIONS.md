# Coding Conventions

**Analysis Date:** 2026-01-15

## Naming Patterns

**Files:**
- Go backend: snake_case (`event_type.go`, `cors_test.go`)
- TypeScript/React: kebab-case for components (`api-client.ts`), PascalCase for components (`EventCard.tsx`)
- Swift iOS: PascalCase (`EventStore.swift`, `APIClient.swift`)
- Test files: `*_test.go` (Go), no test files in web app currently

**Functions:**
- Go: PascalCase for exported (`CreateEvent`), camelCase for unexported (`handleResponse`)
- TypeScript: camelCase (`getAuthHeaders`, `useEvents`, `handleResponse`)
- Swift: camelCase (`fetchData`, `recordEvent`, `syncEventToBackend`)

**Variables:**
- Go: camelCase (`eventRepo`, `userID`, `startDate`)
- TypeScript: camelCase (`queryClient`, `eventTypes`, `isLoading`)
- Swift: camelCase (`modelContext`, `syncEngine`, `isOnline`)

**Types:**
- Go structs: PascalCase (`Event`, `CreateEventRequest`, `BatchCreateEventsResponse`)
- TypeScript interfaces: PascalCase (`Event`, `EventType`, `CreateEventRequest`)
- Swift classes/structs: PascalCase (`EventStore`, `APIClient`, `Event`)

**Constants:**
- Go: PascalCase for exported (`LevelDebug`), package-level const blocks
- TypeScript: SCREAMING_SNAKE_CASE for config (`LOG_LEVEL_ORDER`), camelCase for query keys
- Swift: PascalCase for enums (`PropertyType`, `SyncStatus`)

## Code Style

**Formatting:**
- Go: `go fmt` (standard formatter), no config needed
- TypeScript: ESLint with recommended configs, no Prettier config detected
- Swift: Xcode default formatting

**Linting:**
- Go: `go vet ./...`
- TypeScript: ESLint with `eslint:recommended`, `@typescript-eslint/recommended`, `react-hooks/recommended`
- Key rule: `react-refresh/only-export-components` warns on non-component exports

**Line Length:**
- No enforced limit, but code generally stays under 120 characters

## Import Organization

**Go Order:**
1. Standard library (`context`, `encoding/json`, `fmt`, `time`)
2. External packages (`github.com/gin-gonic/gin`)
3. Internal packages (`github.com/JonnyWalker81/trendy/backend/internal/...`)

**TypeScript Order:**
1. External packages (`react`, `@tanstack/react-query`, `date-fns`)
2. Internal imports using `@/` alias (`@/lib/api-client`, `@/types`, `@/components/ui/card`)

**Swift Order:**
1. Foundation/system frameworks (`Foundation`, `SwiftData`, `SwiftUI`)
2. No third-party imports (uses Apple frameworks + Supabase SDK)

**Path Aliases:**
- TypeScript: `@/*` maps to `./src/*` (configured in `tsconfig.json`)
- Go: Full module path `github.com/JonnyWalker81/trendy/backend`
- Swift: No aliases (direct imports)

## Error Handling

**Go Patterns:**
```go
// Wrap errors with context
if err != nil {
    return nil, fmt.Errorf("failed to create event: %w", err)
}

// Service layer validates and returns user-friendly errors
if eventType.UserID != userID {
    return nil, fmt.Errorf("event type does not belong to user")
}

// Handler layer translates to HTTP status codes
if err != nil {
    c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
    return
}
```

**TypeScript Patterns:**
```typescript
// API client throws errors, consumers catch them
async function handleResponse<T>(response: Response, operation: string): Promise<T> {
  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Unknown error' }))
    throw new Error(error.error || `HTTP ${response.status}`)
  }
  return response.json()
}

// Hooks use TanStack Query's built-in error handling
// Errors are accessed via query.error or mutation.error
```

**Swift Patterns:**
```swift
// Use Swift's native error handling
do {
    try modelContext.save()
} catch {
    errorMessage = EventError.saveFailed.localizedDescription
}

// Log errors with context
Log.sync.error("Failed to queue event for sync", error: error)
```

## Logging

**Framework:**
- Go: Custom logger abstraction over `log/slog` (`internal/logger/`)
- TypeScript: Custom structured logger (`lib/logger.ts`)
- Swift: Apple's unified logging (`os.Logger`) with categories

**Patterns:**

Go:
```go
log := logger.FromContext(ctx)
log.Info("operation completed",
    logger.String("event_id", id),
    logger.Duration("duration", elapsed),
)
```

TypeScript:
```typescript
apiLogger.info('Request completed', { operation: 'getEvents', status: 200 })
apiLogger.error('Request failed', { ...errorContext(error), endpoint: '/events' })
```

Swift:
```swift
Log.sync.info("Network restored - starting sync")
Log.api.debug("API request", context: .with { ctx in
    ctx.add("method", method)
    ctx.add("path", endpoint)
})
```

## Comments

**When to Comment:**
- Document exported functions/types (Go public APIs)
- Explain non-obvious business logic
- Note workarounds or TODOs
- Interface method documentation

**JSDoc/TSDoc:**
- TypeScript: Minimal JSDoc usage, rely on TypeScript types
- Go: Standard Go doc comments for exported items
- Swift: Use `///` for public API documentation

**Examples:**
```go
// EventService defines the interface for event business logic
type EventService interface {
    CreateEvent(ctx context.Context, userID string, req *models.CreateEventRequest) (*models.Event, error)
}
```

```swift
/// Centralized logging utility for the Trendy app.
/// Uses Apple's unified logging system (os.Logger) for native integration
/// with Console.app and performance-optimized log collection.
enum Log { ... }
```

## Function Design

**Size:**
- Keep functions focused on a single responsibility
- Extract helper functions for complex logic
- No strict line limits, but ~50-100 lines is typical maximum

**Parameters:**
- Go: Use context.Context as first parameter for handlers/services
- Go: Use pointer receivers for methods that modify state
- Go: Use request structs for complex input (`*models.CreateEventRequest`)
- TypeScript: Use destructuring for multiple optional params
- Swift: Use trailing closure syntax for callbacks

**Return Values:**
- Go: Return `(result, error)` tuple pattern
- Go: Return pointer for single objects, slice for collections
- TypeScript: Return Promise for async operations
- Swift: Use async/await for asynchronous operations

## Module Design

**Exports:**
- Go: Capitalize to export, keep internal helpers unexported
- TypeScript: Named exports for most items, default export for page components
- Swift: Use access modifiers (`private`, `internal`, `public`)

**Barrel Files:**
- TypeScript: Use `types/index.ts` to re-export all types
- No barrel files in Go (explicit imports)

## Architecture Patterns

**Go Backend - Clean Architecture:**
```
Handler (HTTP) → Service (Business Logic) → Repository (Data Access)
```

- Handlers: Only HTTP serialization, validation, response formatting
- Services: All business logic, validation, authorization checks
- Repositories: Database operations only, no business logic

**React Web - Custom Hooks Pattern:**
```
Component → Custom Hook (useEvents) → API Client → Backend
```

**Swift iOS - Observable Pattern:**
```
View → @Observable ViewModel (EventStore) → SyncEngine → APIClient
```

## Request/Response Patterns

**Go API Models:**
```go
// Request structs use binding tags for validation
type CreateEventRequest struct {
    EventTypeID string    `json:"event_type_id" binding:"required"`
    Timestamp   time.Time `json:"timestamp" binding:"required"`
    Notes       *string   `json:"notes"`  // Optional fields use pointers
}

// Response models use omitempty for optional fields
type Event struct {
    ID        string     `json:"id"`
    Notes     *string    `json:"notes,omitempty"`
    EventType *EventType `json:"event_type,omitempty"`
}
```

**TypeScript Types:**
```typescript
// Use snake_case in types to match API
interface Event {
  id: string
  event_type_id: string
  created_at: string
  event_type?: EventType  // Optional nested object
}
```

## React Component Patterns

**Component Structure:**
```typescript
// Props interface defined above component
interface EventCardProps {
  event: Event
  onEdit: (event: Event) => void
  onDelete: (event: Event) => void
  className?: string  // Allow className extension
}

// Use forwardRef for components needing ref forwarding
const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant = "default", ...props }, ref) => { ... }
)

// Use cn() utility for conditional classNames
className={cn(
  "base-classes",
  { "conditional-class": condition },
  className
)}
```

**State Management:**
- Use TanStack Query for server state (caching, refetching)
- Use React state for local UI state
- Define query keys as constants for invalidation

## Swift Patterns

**@Observable for ViewModels:**
```swift
@Observable
@MainActor
class EventStore {
    private(set) var events: [Event] = []
    var isLoading = false
    var errorMessage: String?
}
```

**Async/Await:**
```swift
func fetchData() async {
    isLoading = true
    defer { isLoading = false }

    do {
        // async operations
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

---

*Convention analysis: 2026-01-15*
