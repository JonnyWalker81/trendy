# Testing Patterns

**Analysis Date:** 2026-01-15

## Test Framework

**Go Backend:**
- Runner: Go standard testing (`go test`)
- Assertion: Standard library assertions with `t.Errorf`, `t.Fatalf`
- No external testing libraries

**Run Commands:**
```bash
# Run all backend tests
cd apps/backend && go test ./...

# Run specific package tests
cd apps/backend && go test ./internal/service -v

# Run with coverage
cd apps/backend && go test ./... -cover

# Run specific test function
cd apps/backend && go test ./internal/middleware -run TestParseWildcardOrigin -v
```

**Web App:**
- No test framework configured
- No test files exist in `apps/web/src/`
- package.json has no test scripts

**iOS App:**
- No unit test targets detected
- SwiftUI previews used for visual testing

## Test File Organization

**Go Backend - Location:**
- Co-located with source files
- Pattern: `*_test.go` in same directory as implementation

**Structure:**
```
apps/backend/internal/
├── middleware/
│   ├── cors.go
│   └── cors_test.go        # Tests for cors.go
├── service/
│   ├── event.go
│   └── event_test.go       # Tests for event.go
```

**Existing Test Files:**
- `apps/backend/internal/middleware/cors_test.go` - CORS wildcard origin parsing
- `apps/backend/internal/service/event_test.go` - Event service business logic

## Test Structure

**Go - Table-Driven Tests:**
```go
func TestParseWildcardOrigin(t *testing.T) {
    tests := []struct {
        name    string
        pattern string
        wantNil bool
        scheme  string
        suffix  string
    }{
        {
            name:    "valid https wildcard",
            pattern: "https://*.example.com",
            wantNil: false,
            scheme:  "https://",
            suffix:  ".example.com",
        },
        // ... more test cases
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := parseWildcardOrigin(tt.pattern)
            if tt.wantNil {
                if got != nil {
                    t.Errorf("parseWildcardOrigin(%q) = %+v, want nil", tt.pattern, got)
                }
                return
            }
            // ... assertions
        })
    }
}
```

**Go - Setup/Teardown Pattern:**
```go
func TestCreateEvent_HealthKit_Idempotency(t *testing.T) {
    ctx := context.Background()

    // Setup: Create mock repositories
    eventRepo := newMockEventRepository()
    eventTypeRepo := newMockEventTypeRepository()
    changeLogRepo := newMockChangeLogRepository()

    // Setup: Create service with mocks
    service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

    // Setup: Create test data
    userID := "user-123"
    eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
        UserID: userID,
        Name:   "Steps",
    })

    // Test execution
    event1, err := service.CreateEvent(ctx, userID, req)
    if err != nil {
        t.Fatalf("First CreateEvent failed: %v", err)
    }

    // Assertions
    if len(events) != 1 {
        t.Errorf("Expected 1 event, got %d", len(events))
    }
}
```

## Mocking

**Go - Manual Mocks (In-File):**
```go
// Mock repository implementing the interface
type mockEventRepository struct {
    events           map[string]*models.Event
    sampleIDToEvent  map[string]*models.Event
    createCalls      int
    upsertCalls      int
}

func newMockEventRepository() *mockEventRepository {
    return &mockEventRepository{
        events:          make(map[string]*models.Event),
        sampleIDToEvent: make(map[string]*models.Event),
    }
}

// Implement interface methods
func (m *mockEventRepository) Create(ctx context.Context, event *models.Event) (*models.Event, error) {
    m.createCalls++
    if event.ID == "" {
        event.ID = generateMockID()
    }
    event.CreatedAt = time.Now()
    event.UpdatedAt = time.Now()
    m.events[event.ID] = event
    return event, nil
}
```

**What to Mock:**
- Repository interfaces (database access)
- External API clients
- Time-sensitive operations (use fixed timestamps)

**What NOT to Mock:**
- Service layer business logic
- Pure functions
- Value objects/models

**Mock ID Generation:**
```go
var mockIDCounter int

func generateMockID() string {
    mockIDCounter++
    return "mock-id-" + string(rune('0'+mockIDCounter))
}
```

**Pointer Helpers:**
```go
func ptr(s string) *string {
    return &s
}
```

## Fixtures and Factories

**Go - Test Data Creation:**
```go
// Create test event type
eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
    UserID: userID,
    Name:   "Steps",
})

// Create test request
req := &models.CreateEventRequest{
    EventTypeID:       eventType.ID,
    Timestamp:         time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC),
    SourceType:        "healthkit",
    HealthKitSampleID: ptr("steps-2025-01-15"),
}
```

**Location:**
- Test data created inline within test functions
- Mock implementations defined at top of test file
- No separate fixtures directory

## Coverage

**Requirements:**
- No enforced coverage threshold
- Focus on critical business logic paths

**View Coverage:**
```bash
# Generate coverage report
cd apps/backend && go test ./... -coverprofile=coverage.out

# View in browser
cd apps/backend && go tool cover -html=coverage.out
```

## Test Types

**Unit Tests:**
- Service layer tests with mocked repositories (`event_test.go`)
- Utility function tests (`cors_test.go`)
- Focus on business logic validation

**Integration Tests:**
- Not currently implemented
- Would test Handler → Service → Repository chain
- Would require test database setup

**E2E Tests:**
- Not implemented
- No Cypress, Playwright, or similar configured

## Common Patterns

**Async Testing (Go):**
```go
// Context-based testing
ctx := context.Background()
result, err := service.CreateEvent(ctx, userID, req)
```

**Error Testing (Go):**
```go
// Test error conditions
if err != nil {
    t.Fatalf("CreateEvent failed: %v", err)
}

// Test for expected errors
_, err := service.CreateEvent(ctx, userID, invalidReq)
if err == nil {
    t.Error("Expected error for invalid request, got nil")
}
```

**Idempotency Testing:**
```go
func TestCreateEvent_HealthKit_Idempotency(t *testing.T) {
    // First import
    event1, err := service.CreateEvent(ctx, userID, req)

    // Import same event 10 more times
    for i := 0; i < 10; i++ {
        event, err := service.CreateEvent(ctx, userID, req)
        if event.ID != event1.ID {
            t.Errorf("Expected same event ID on re-import")
        }
    }

    // Verify only 1 event exists
    events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
    if len(events) != 1 {
        t.Errorf("Expected 1 event, got %d", len(events))
    }
}
```

**Batch Operation Testing:**
```go
func TestCreateEventsBatch_MixedHealthKitAndManual(t *testing.T) {
    // Create mixed batch request
    batchReq := &models.BatchCreateEventsRequest{
        Events: []models.CreateEventRequest{
            {SourceType: "healthkit", ...},
            {SourceType: "manual", ...},
        },
    }

    resp, err := service.CreateEventsBatch(ctx, userID, batchReq)
    if resp.Success != 3 {
        t.Errorf("Expected 3 successes, got %d", resp.Success)
    }
}
```

## Test Gaps

**Critical Missing Tests:**

1. **Web App** (`apps/web/src/`)
   - No unit tests for hooks
   - No component tests
   - No API client tests
   - No integration tests

2. **iOS App** (`apps/ios/trendy/`)
   - No unit tests for ViewModels
   - No service layer tests
   - No API client tests

3. **Go Backend Gaps:**
   - Handler layer tests (HTTP endpoints)
   - Repository layer tests (database operations)
   - Auth middleware tests
   - Error handling edge cases

**Recommended Testing Framework Additions:**

Web App:
```bash
# Install Vitest for unit testing
yarn add -D vitest @testing-library/react @testing-library/jest-dom
```

iOS:
```swift
// Add XCTest targets in Xcode project
// Test EventStore, APIClient, SyncEngine
```

## Running Tests

**Backend:**
```bash
# From repo root
just test-backend

# Or directly
cd apps/backend && go test ./...

# Verbose output
cd apps/backend && go test ./... -v

# With race detection
cd apps/backend && go test ./... -race
```

**All Tests:**
```bash
# From repo root
just test
```

---

*Testing analysis: 2026-01-15*
