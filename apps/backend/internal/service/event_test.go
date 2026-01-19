package service

import (
	"context"
	"testing"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
)

// mockEventRepository is a mock implementation of EventRepository for testing
type mockEventRepository struct {
	events           map[string]*models.Event // id -> event
	sampleIDToEvent  map[string]*models.Event // healthkit_sample_id -> event
	createCalls      int
	upsertCalls      int
	batchUpsertCalls int
}

func newMockEventRepository() *mockEventRepository {
	return &mockEventRepository{
		events:          make(map[string]*models.Event),
		sampleIDToEvent: make(map[string]*models.Event),
	}
}

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

func (m *mockEventRepository) CreateBatch(ctx context.Context, events []models.Event) ([]models.Event, error) {
	result := make([]models.Event, 0, len(events))
	for i := range events {
		created, err := m.Create(ctx, &events[i])
		if err != nil {
			return nil, err
		}
		result = append(result, *created)
	}
	return result, nil
}

func (m *mockEventRepository) GetByID(ctx context.Context, id string) (*models.Event, error) {
	if event, ok := m.events[id]; ok {
		return event, nil
	}
	return nil, nil
}

func (m *mockEventRepository) GetByUserID(ctx context.Context, userID string, limit, offset int) ([]models.Event, error) {
	var result []models.Event
	for _, event := range m.events {
		if event.UserID == userID {
			result = append(result, *event)
		}
	}
	return result, nil
}

func (m *mockEventRepository) GetByUserIDAndDateRange(ctx context.Context, userID string, startDate, endDate time.Time) ([]models.Event, error) {
	return m.GetByUserID(ctx, userID, 0, 0)
}

func (m *mockEventRepository) GetForExport(ctx context.Context, userID string, startDate, endDate *time.Time, eventTypeIDs []string) ([]models.Event, error) {
	return m.GetByUserID(ctx, userID, 0, 0)
}

func (m *mockEventRepository) Update(ctx context.Context, id string, event *models.Event) (*models.Event, error) {
	if existing, ok := m.events[id]; ok {
		if event.EventTypeID != "" {
			existing.EventTypeID = event.EventTypeID
		}
		if !event.Timestamp.IsZero() {
			existing.Timestamp = event.Timestamp
		}
		existing.UpdatedAt = time.Now()
		return existing, nil
	}
	return nil, nil
}

func (m *mockEventRepository) UpdateFields(ctx context.Context, id string, fields map[string]interface{}) (*models.Event, error) {
	if existing, ok := m.events[id]; ok {
		// Apply fields to existing event
		for key, value := range fields {
			switch key {
			case "notes":
				if value == nil {
					existing.Notes = nil
				} else if s, ok := value.(string); ok {
					existing.Notes = &s
				}
			case "event_type_id":
				if s, ok := value.(string); ok {
					existing.EventTypeID = s
				}
			case "timestamp":
				if t, ok := value.(time.Time); ok {
					existing.Timestamp = t
				}
			case "is_all_day":
				if b, ok := value.(bool); ok {
					existing.IsAllDay = b
				}
			case "end_date":
				if value == nil {
					existing.EndDate = nil
				} else if t, ok := value.(time.Time); ok {
					existing.EndDate = &t
				}
			}
		}
		existing.UpdatedAt = time.Now()
		return existing, nil
	}
	return nil, nil
}

func (m *mockEventRepository) Delete(ctx context.Context, id string) error {
	delete(m.events, id)
	return nil
}

func (m *mockEventRepository) CountByEventType(ctx context.Context, userID string) (map[string]int64, error) {
	counts := make(map[string]int64)
	for _, event := range m.events {
		if event.UserID == userID {
			counts[event.EventTypeID]++
		}
	}
	return counts, nil
}

func (m *mockEventRepository) GetByHealthKitSampleIDs(ctx context.Context, userID string, sampleIDs []string) ([]models.Event, error) {
	var result []models.Event
	for _, sampleID := range sampleIDs {
		if event, ok := m.sampleIDToEvent[sampleID]; ok && event.UserID == userID {
			result = append(result, *event)
		}
	}
	return result, nil
}

// healthKitContentKey generates a unique key for HealthKit content-based deduplication.
func mockHealthKitContentKey(userID, eventTypeID string, timestamp time.Time, healthKitCategory *string) string {
	category := ""
	if healthKitCategory != nil {
		category = *healthKitCategory
	}
	return userID + "|" + eventTypeID + "|" + timestamp.Truncate(time.Second).UTC().Format(time.RFC3339) + "|" + category
}

func (m *mockEventRepository) GetByHealthKitContent(ctx context.Context, userID string, events []models.Event) (map[string]models.Event, error) {
	result := make(map[string]models.Event)

	// Build content keys for events we're looking for
	lookupKeys := make(map[string]bool)
	for _, event := range events {
		key := mockHealthKitContentKey(userID, event.EventTypeID, event.Timestamp, event.HealthKitCategory)
		lookupKeys[key] = true
	}

	// Check all stored events for content matches
	for _, event := range m.events {
		if event.UserID != userID || event.SourceType != "healthkit" {
			continue
		}
		key := mockHealthKitContentKey(userID, event.EventTypeID, event.Timestamp, event.HealthKitCategory)
		if lookupKeys[key] {
			result[key] = *event
		}
	}
	return result, nil
}

func (m *mockEventRepository) UpsertHealthKitEvent(ctx context.Context, event *models.Event) (*models.Event, bool, error) {
	m.upsertCalls++
	sampleID := *event.HealthKitSampleID

	// Check 1: Sample ID duplicate
	if existing, ok := m.sampleIDToEvent[sampleID]; ok && existing.UserID == event.UserID {
		// Return existing event as-is (HealthKit data is immutable)
		return existing, false, nil // wasCreated = false
	}

	// Check 2: Content-based duplicate (different sample ID but same event content)
	contentKey := mockHealthKitContentKey(event.UserID, event.EventTypeID, event.Timestamp, event.HealthKitCategory)
	for _, existing := range m.events {
		if existing.UserID != event.UserID || existing.SourceType != "healthkit" {
			continue
		}
		existingKey := mockHealthKitContentKey(existing.UserID, existing.EventTypeID, existing.Timestamp, existing.HealthKitCategory)
		if existingKey == contentKey {
			// Content duplicate found - return existing event
			return existing, false, nil
		}
	}

	// No duplicate found - create new event
	if event.ID == "" {
		event.ID = generateMockID()
	}
	event.CreatedAt = time.Now()
	event.UpdatedAt = time.Now()
	m.events[event.ID] = event
	m.sampleIDToEvent[sampleID] = event
	return event, true, nil // wasCreated = true
}

func (m *mockEventRepository) UpsertHealthKitEventsBatch(ctx context.Context, events []models.Event) ([]models.Event, []string, error) {
	m.batchUpsertCalls++
	var result []models.Event
	var createdIDs []string

	for i := range events {
		upserted, wasCreated, err := m.UpsertHealthKitEvent(ctx, &events[i])
		if err != nil {
			return nil, nil, err
		}
		result = append(result, *upserted)
		if wasCreated {
			createdIDs = append(createdIDs, upserted.ID)
		}
	}
	return result, createdIDs, nil
}

func (m *mockEventRepository) GetByIDs(ctx context.Context, ids []string) ([]models.Event, error) {
	var result []models.Event
	for _, id := range ids {
		if event, ok := m.events[id]; ok {
			result = append(result, *event)
		}
	}
	return result, nil
}

func (m *mockEventRepository) Upsert(ctx context.Context, event *models.Event) (*models.Event, bool, error) {
	m.upsertCalls++
	// Check if event already exists by ID
	if existing, ok := m.events[event.ID]; ok && existing.UserID == event.UserID {
		// Update existing event
		existing.Timestamp = event.Timestamp
		existing.Notes = event.Notes
		existing.Properties = event.Properties
		existing.UpdatedAt = time.Now()
		return existing, false, nil // wasCreated = false
	}

	// Create new event
	event.CreatedAt = time.Now()
	event.UpdatedAt = time.Now()
	m.events[event.ID] = event
	return event, true, nil // wasCreated = true
}

func (m *mockEventRepository) UpsertBatch(ctx context.Context, events []models.Event) ([]models.Event, []repository.UpsertResult, error) {
	var result []models.Event
	var results []repository.UpsertResult

	for i := range events {
		event := &events[i]
		if event.ID == "" {
			results = append(results, repository.UpsertResult{
				Index:  i,
				ID:     "",
				Action: "failed",
				Error:  nil,
			})
			continue
		}

		upserted, wasCreated, err := m.Upsert(ctx, event)
		if err != nil {
			results = append(results, repository.UpsertResult{
				Index:  i,
				ID:     event.ID,
				Action: "failed",
				Error:  err,
			})
			continue
		}

		result = append(result, *upserted)
		action := "deduplicated"
		if wasCreated {
			action = "created"
		}
		results = append(results, repository.UpsertResult{
			Index:  i,
			ID:     upserted.ID,
			Action: action,
		})
	}
	return result, results, nil
}

func (m *mockEventRepository) CountByUser(ctx context.Context, userID string) (int64, error) {
	var count int64
	for _, event := range m.events {
		if event.UserID == userID {
			count++
		}
	}
	return count, nil
}

func (m *mockEventRepository) CountHealthKitByUser(ctx context.Context, userID string) (int64, error) {
	var count int64
	for _, event := range m.events {
		if event.UserID == userID && event.HealthKitSampleID != nil {
			count++
		}
	}
	return count, nil
}

func (m *mockEventRepository) GetLatestTimestamp(ctx context.Context, userID string) (*time.Time, error) {
	var latest *time.Time
	for _, event := range m.events {
		if event.UserID == userID {
			if latest == nil || event.UpdatedAt.After(*latest) {
				t := event.UpdatedAt
				latest = &t
			}
		}
	}
	return latest, nil
}

func (m *mockEventRepository) GetLatestHealthKitTimestamp(ctx context.Context, userID string) (*time.Time, error) {
	var latest *time.Time
	for _, event := range m.events {
		if event.UserID == userID && event.HealthKitSampleID != nil {
			if latest == nil || event.UpdatedAt.After(*latest) {
				t := event.UpdatedAt
				latest = &t
			}
		}
	}
	return latest, nil
}

// mockEventTypeRepository is a mock implementation of EventTypeRepository
type mockEventTypeRepository struct {
	eventTypes map[string]*models.EventType
}

func newMockEventTypeRepository() *mockEventTypeRepository {
	return &mockEventTypeRepository{
		eventTypes: make(map[string]*models.EventType),
	}
}

func (m *mockEventTypeRepository) Create(ctx context.Context, et *models.EventType) (*models.EventType, error) {
	if et.ID == "" {
		et.ID = generateMockID()
	}
	m.eventTypes[et.ID] = et
	return et, nil
}

func (m *mockEventTypeRepository) GetByID(ctx context.Context, id string) (*models.EventType, error) {
	if et, ok := m.eventTypes[id]; ok {
		return et, nil
	}
	return nil, nil
}

func (m *mockEventTypeRepository) GetByUserID(ctx context.Context, userID string) ([]models.EventType, error) {
	var result []models.EventType
	for _, et := range m.eventTypes {
		if et.UserID == userID {
			result = append(result, *et)
		}
	}
	return result, nil
}

func (m *mockEventTypeRepository) Update(ctx context.Context, id string, et *models.EventType) (*models.EventType, error) {
	if existing, ok := m.eventTypes[id]; ok {
		if et.Name != "" {
			existing.Name = et.Name
		}
		return existing, nil
	}
	return nil, nil
}

func (m *mockEventTypeRepository) Delete(ctx context.Context, id string) error {
	delete(m.eventTypes, id)
	return nil
}

func (m *mockEventTypeRepository) CountByUser(ctx context.Context, userID string) (int64, error) {
	var count int64
	for _, et := range m.eventTypes {
		if et.UserID == userID {
			count++
		}
	}
	return count, nil
}

func (m *mockEventTypeRepository) GetLatestTimestamp(ctx context.Context, userID string) (*time.Time, error) {
	var latest *time.Time
	for _, et := range m.eventTypes {
		if et.UserID == userID {
			if latest == nil || et.UpdatedAt.After(*latest) {
				t := et.UpdatedAt
				latest = &t
			}
		}
	}
	return latest, nil
}

// mockChangeLogRepository is a mock implementation of ChangeLogRepository
type mockChangeLogRepository struct {
	entries []models.ChangeLogInput
}

func newMockChangeLogRepository() *mockChangeLogRepository {
	return &mockChangeLogRepository{
		entries: make([]models.ChangeLogInput, 0),
	}
}

func (m *mockChangeLogRepository) Append(ctx context.Context, input *models.ChangeLogInput) (int64, error) {
	m.entries = append(m.entries, *input)
	return int64(len(m.entries)), nil
}

func (m *mockChangeLogRepository) GetSince(ctx context.Context, userID string, cursor int64, limit int) (*models.ChangeFeedResponse, error) {
	return &models.ChangeFeedResponse{}, nil
}

func (m *mockChangeLogRepository) GetLatestCursor(ctx context.Context, userID string) (int64, error) {
	return int64(len(m.entries)), nil
}

// Helper to generate mock IDs
var mockIDCounter int

func generateMockID() string {
	mockIDCounter++
	return "mock-id-" + string(rune('0'+mockIDCounter))
}

func ptr(s string) *string {
	return &s
}

// ============================================================================
// Tests
// ============================================================================

func TestCreateEvent_HealthKit_Idempotency(t *testing.T) {
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	// Create an event type
	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Steps",
	})

	sampleID := "steps-2025-01-15"

	// Create request for HealthKit event
	req := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC),
		SourceType:        "healthkit",
		HealthKitSampleID: ptr(sampleID),
		HealthKitCategory: ptr("HKQuantityTypeIdentifierStepCount"),
	}

	// First import
	event1, wasCreated, err := service.CreateEvent(ctx, userID, req)
	if err != nil {
		t.Fatalf("First CreateEvent failed: %v", err)
	}
	if !wasCreated {
		t.Error("Expected wasCreated=true for first create")
	}

	// Import same event 10 more times
	for i := 0; i < 10; i++ {
		event, wasCreated, err := service.CreateEvent(ctx, userID, req)
		if err != nil {
			t.Fatalf("CreateEvent %d failed: %v", i+2, err)
		}
		if event.ID != event1.ID {
			t.Errorf("Expected same event ID on re-import, got different: %s vs %s", event.ID, event1.ID)
		}
		if wasCreated {
			t.Errorf("Expected wasCreated=false for duplicate, iteration %d", i+2)
		}
	}

	// Verify only 1 event exists
	events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
	if len(events) != 1 {
		t.Errorf("Expected 1 event, got %d", len(events))
	}

	// Verify changelog: 1 create + 10 updates
	createCount := 0
	updateCount := 0
	for _, entry := range changeLogRepo.entries {
		if entry.Operation == models.OperationCreate {
			createCount++
		} else if entry.Operation == models.OperationUpdate {
			updateCount++
		}
	}
	if createCount != 1 {
		t.Errorf("Expected 1 create in changelog, got %d", createCount)
	}
	if updateCount != 10 {
		t.Errorf("Expected 10 updates in changelog, got %d", updateCount)
	}
}

func TestCreateEvent_HealthKit_Immutable(t *testing.T) {
	// HealthKit data is immutable - re-importing the same event with different values
	// should NOT update the existing event. The original values are preserved.
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Steps",
	})

	sampleID := "steps-2025-01-15"

	// First import with initial values
	req1 := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC),
		SourceType:        "healthkit",
		HealthKitSampleID: ptr(sampleID),
		Notes:             ptr("5000 steps"),
	}

	event1, wasCreated1, _ := service.CreateEvent(ctx, userID, req1)
	if !wasCreated1 {
		t.Error("Expected wasCreated=true for first create")
	}

	// Re-import with different values (simulating data correction attempt)
	req2 := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC),
		SourceType:        "healthkit",
		HealthKitSampleID: ptr(sampleID),
		Notes:             ptr("5500 steps"), // Different value
	}

	event2, wasCreated2, _ := service.CreateEvent(ctx, userID, req2)

	// Verify same event was returned (not created)
	if event2.ID != event1.ID {
		t.Errorf("Expected same event ID, got different")
	}
	if wasCreated2 {
		t.Error("Expected wasCreated=false for duplicate")
	}
	// Original notes should be preserved (HealthKit data is immutable)
	if event2.Notes == nil || *event2.Notes != "5000 steps" {
		t.Errorf("Expected original notes '5000 steps' to be preserved, got %v", event2.Notes)
	}
}

func TestCreateEvent_MultipleWorkoutsAtSameTimestamp(t *testing.T) {
	// Two DIFFERENT workouts at the same timestamp should both be created
	// if they have DIFFERENT healthkit_categories (which distinguishes them)
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Workout",
	})

	timestamp := time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC)

	// Create two workouts at the same timestamp with DIFFERENT categories
	// (This is the realistic scenario - different workout types at same time)
	req1 := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         timestamp,
		SourceType:        "healthkit",
		HealthKitSampleID: ptr("workout-abc123"),
		HealthKitCategory: ptr("running"), // Running
	}
	req2 := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         timestamp, // Same timestamp
		SourceType:        "healthkit",
		HealthKitSampleID: ptr("workout-def456"), // Different sample ID
		HealthKitCategory: ptr("cycling"),        // Different category
	}

	event1, _, err := service.CreateEvent(ctx, userID, req1)
	if err != nil {
		t.Fatalf("First workout creation failed: %v", err)
	}

	event2, _, err := service.CreateEvent(ctx, userID, req2)
	if err != nil {
		t.Fatalf("Second workout creation failed: %v", err)
	}

	// Verify both events exist with different IDs (different categories = different events)
	if event1.ID == event2.ID {
		t.Error("Expected different event IDs for different workout categories")
	}

	events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
	if len(events) != 2 {
		t.Errorf("Expected 2 events, got %d", len(events))
	}
}

func TestCreateEvent_SameTimestampSameCategory_Deduped(t *testing.T) {
	// Two HealthKit events with same timestamp AND same category are content-based duplicates
	// (even if they have different sample IDs - this handles HealthKit DB restore scenario)
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Workout",
	})

	timestamp := time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC)
	category := "running"

	// First workout
	req1 := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         timestamp,
		SourceType:        "healthkit",
		HealthKitSampleID: ptr("original-sample-id"),
		HealthKitCategory: ptr(category),
	}

	event1, wasCreated1, _ := service.CreateEvent(ctx, userID, req1)
	if !wasCreated1 {
		t.Error("Expected wasCreated=true for first create")
	}

	// Same workout re-imported with different sample ID (HealthKit DB restore scenario)
	req2 := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         timestamp,           // Same timestamp
		SourceType:        "healthkit",
		HealthKitSampleID: ptr("new-sample-id"), // Different sample ID
		HealthKitCategory: ptr(category),        // Same category
	}

	event2, wasCreated2, _ := service.CreateEvent(ctx, userID, req2)

	// Should be deduplicated by content (same timestamp + category)
	if wasCreated2 {
		t.Error("Expected wasCreated=false for content-based duplicate")
	}
	if event1.ID != event2.ID {
		t.Error("Expected same event ID for content-based duplicate")
	}

	events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
	if len(events) != 1 {
		t.Errorf("Expected 1 event after content-based dedupe, got %d", len(events))
	}
}

func TestCreateEvent_ManualAndHealthKitAtSameTimestamp(t *testing.T) {
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Steps",
	})

	timestamp := time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC)

	// Create manual event
	manualReq := &models.CreateEventRequest{
		EventTypeID: eventType.ID,
		Timestamp:   timestamp,
		SourceType:  "manual",
	}

	// Create HealthKit event at same timestamp
	healthKitReq := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         timestamp,
		SourceType:        "healthkit",
		HealthKitSampleID: ptr("steps-2025-01-15"),
	}

	event1, _, err := service.CreateEvent(ctx, userID, manualReq)
	if err != nil {
		t.Fatalf("Manual event creation failed: %v", err)
	}

	event2, _, err := service.CreateEvent(ctx, userID, healthKitReq)
	if err != nil {
		t.Fatalf("HealthKit event creation failed: %v", err)
	}

	// Both should exist
	if event1.ID == event2.ID {
		t.Error("Expected different event IDs for manual vs HealthKit")
	}

	events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
	if len(events) != 2 {
		t.Errorf("Expected 2 events, got %d", len(events))
	}
}

func TestCreateEventsBatch_HealthKit_Idempotency(t *testing.T) {
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Steps",
	})

	// Create 3 HealthKit events via batch
	batchReq := &models.BatchCreateEventsRequest{
		Events: []models.CreateEventRequest{
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 15, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-15"),
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 16, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-16"),
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 17, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-17"),
			},
		},
	}

	// First batch import
	resp1, err := service.CreateEventsBatch(ctx, userID, batchReq)
	if err != nil {
		t.Fatalf("First batch failed: %v", err)
	}
	if resp1.Success != 3 {
		t.Errorf("Expected 3 successes, got %d", resp1.Success)
	}

	// Re-import same batch
	resp2, err := service.CreateEventsBatch(ctx, userID, batchReq)
	if err != nil {
		t.Fatalf("Second batch failed: %v", err)
	}
	if resp2.Success != 3 {
		t.Errorf("Expected 3 successes, got %d", resp2.Success)
	}

	// Verify still only 3 events
	events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
	if len(events) != 3 {
		t.Errorf("Expected 3 events after re-import, got %d", len(events))
	}

	// Verify changelog: 3 creates only (per CONTEXT.md, batch imports skip UPDATE entries)
	createCount := 0
	updateCount := 0
	for _, entry := range changeLogRepo.entries {
		if entry.Operation == models.OperationCreate {
			createCount++
		} else if entry.Operation == models.OperationUpdate {
			updateCount++
		}
	}
	if createCount != 3 {
		t.Errorf("Expected 3 creates in changelog, got %d", createCount)
	}
	if updateCount != 0 {
		t.Errorf("Expected 0 updates in changelog (skipped in batch), got %d", updateCount)
	}
}

func TestCreateEventsBatch_MixedHealthKitAndManual(t *testing.T) {
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Steps",
	})

	// Mix of HealthKit and manual events
	batchReq := &models.BatchCreateEventsRequest{
		Events: []models.CreateEventRequest{
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 15, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-15"),
			},
			{
				EventTypeID: eventType.ID,
				Timestamp:   time.Date(2025, 1, 16, 0, 0, 0, 0, time.UTC),
				SourceType:  "manual", // Manual event
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 17, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-17"),
			},
		},
	}

	resp, err := service.CreateEventsBatch(ctx, userID, batchReq)
	if err != nil {
		t.Fatalf("Batch failed: %v", err)
	}
	if resp.Success != 3 {
		t.Errorf("Expected 3 successes, got %d", resp.Success)
	}

	events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
	if len(events) != 3 {
		t.Errorf("Expected 3 events, got %d", len(events))
	}

	// Count HealthKit vs manual
	healthKitCount := 0
	manualCount := 0
	for _, e := range events {
		if e.SourceType == "healthkit" {
			healthKitCount++
		} else if e.SourceType == "manual" {
			manualCount++
		}
	}
	if healthKitCount != 2 {
		t.Errorf("Expected 2 HealthKit events, got %d", healthKitCount)
	}
	if manualCount != 1 {
		t.Errorf("Expected 1 manual event, got %d", manualCount)
	}
}

func TestCreateEventsBatch_PartialDuplicates(t *testing.T) {
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Steps",
	})

	// First create 2 events
	firstBatch := &models.BatchCreateEventsRequest{
		Events: []models.CreateEventRequest{
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 15, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-15"),
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 16, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-16"),
			},
		},
	}

	_, _ = service.CreateEventsBatch(ctx, userID, firstBatch)

	// Now batch with 3 new + 2 existing
	secondBatch := &models.BatchCreateEventsRequest{
		Events: []models.CreateEventRequest{
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 15, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-15"), // Existing
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 16, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-16"), // Existing
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 17, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-17"), // New
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 18, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-18"), // New
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 19, 0, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("steps-2025-01-19"), // New
			},
		},
	}

	resp, err := service.CreateEventsBatch(ctx, userID, secondBatch)
	if err != nil {
		t.Fatalf("Second batch failed: %v", err)
	}
	if resp.Success != 5 {
		t.Errorf("Expected 5 successes, got %d", resp.Success)
	}

	// Verify 5 total events (2 original + 3 new)
	events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
	if len(events) != 5 {
		t.Errorf("Expected 5 events, got %d", len(events))
	}

	// Verify changelog: 5 creates total (batch imports skip UPDATE entries)
	createCount := 0
	updateCount := 0
	for _, entry := range changeLogRepo.entries {
		if entry.Operation == models.OperationCreate {
			createCount++
		} else if entry.Operation == models.OperationUpdate {
			updateCount++
		}
	}
	if createCount != 5 {
		t.Errorf("Expected 5 creates in changelog, got %d", createCount)
	}
	if updateCount != 0 {
		t.Errorf("Expected 0 updates in changelog (skipped in batch), got %d", updateCount)
	}
}

// ============================================================================
// Content-Based Deduplication Tests
// ============================================================================

// TestCreateEvent_HealthKit_ContentBasedDedupe tests that when the same workout
// is synced with a different sample ID (e.g., after HealthKit database restore),
// it is deduplicated by content (event_type_id + timestamp + category).
func TestCreateEvent_HealthKit_ContentBasedDedupe(t *testing.T) {
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Workout",
	})

	timestamp := time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC)
	workoutCategory := "workout"

	// First import with original sample ID
	req1 := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         timestamp,
		SourceType:        "healthkit",
		HealthKitSampleID: ptr("original-sample-id-123"),
		HealthKitCategory: ptr(workoutCategory),
		Notes:             ptr("Running workout"),
	}

	event1, wasCreated, err := service.CreateEvent(ctx, userID, req1)
	if err != nil {
		t.Fatalf("First CreateEvent failed: %v", err)
	}
	if !wasCreated {
		t.Error("Expected wasCreated=true for first create")
	}

	// Re-sync same workout with DIFFERENT sample ID (simulates HealthKit DB restore)
	req2 := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         timestamp,         // Same timestamp
		SourceType:        "healthkit",
		HealthKitSampleID: ptr("new-sample-id-456"), // Different sample ID!
		HealthKitCategory: ptr(workoutCategory),     // Same category
		Notes:             ptr("Running workout"),
	}

	event2, wasCreated2, err := service.CreateEvent(ctx, userID, req2)
	if err != nil {
		t.Fatalf("Second CreateEvent failed: %v", err)
	}

	// Should detect as duplicate and return existing event
	if wasCreated2 {
		t.Error("Expected wasCreated=false for content-based duplicate")
	}
	if event2.ID != event1.ID {
		t.Errorf("Expected same event ID (content-based dedupe), got different: %s vs %s", event2.ID, event1.ID)
	}

	// Verify only 1 event exists
	events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
	if len(events) != 1 {
		t.Errorf("Expected 1 event after content-based dedupe, got %d", len(events))
	}
}

// TestCreateEvent_HealthKit_DifferentCategoriesNotDeduplicated tests that
// two workouts at the same timestamp but with different categories are NOT
// deduplicated (they represent different activities).
func TestCreateEvent_HealthKit_DifferentCategoriesNotDeduplicated(t *testing.T) {
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Activity",
	})

	timestamp := time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC)

	// First: Running workout
	req1 := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         timestamp,
		SourceType:        "healthkit",
		HealthKitSampleID: ptr("running-sample-id"),
		HealthKitCategory: ptr("running"), // Running category
	}

	event1, _, err := service.CreateEvent(ctx, userID, req1)
	if err != nil {
		t.Fatalf("First CreateEvent failed: %v", err)
	}

	// Second: Cycling workout at same timestamp (different category)
	req2 := &models.CreateEventRequest{
		EventTypeID:       eventType.ID,
		Timestamp:         timestamp, // Same timestamp
		SourceType:        "healthkit",
		HealthKitSampleID: ptr("cycling-sample-id"),
		HealthKitCategory: ptr("cycling"), // Different category!
	}

	event2, wasCreated, err := service.CreateEvent(ctx, userID, req2)
	if err != nil {
		t.Fatalf("Second CreateEvent failed: %v", err)
	}

	// Should create new event (different category)
	if !wasCreated {
		t.Error("Expected wasCreated=true for different category")
	}
	if event2.ID == event1.ID {
		t.Error("Expected different event IDs for different categories at same timestamp")
	}

	// Verify both events exist
	events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
	if len(events) != 2 {
		t.Errorf("Expected 2 events (different categories), got %d", len(events))
	}
}

// TestCreateEventsBatch_HealthKit_ContentBasedDedupe tests batch import with
// content-based deduplication when sample IDs change.
func TestCreateEventsBatch_HealthKit_ContentBasedDedupe(t *testing.T) {
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Workout",
	})

	workoutCategory := "workout"

	// First batch: Create 3 workouts with original sample IDs
	firstBatch := &models.BatchCreateEventsRequest{
		Events: []models.CreateEventRequest{
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("original-sample-1"),
				HealthKitCategory: ptr(workoutCategory),
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 16, 11, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("original-sample-2"),
				HealthKitCategory: ptr(workoutCategory),
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 17, 12, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("original-sample-3"),
				HealthKitCategory: ptr(workoutCategory),
			},
		},
	}

	resp1, err := service.CreateEventsBatch(ctx, userID, firstBatch)
	if err != nil {
		t.Fatalf("First batch failed: %v", err)
	}
	if resp1.Success != 3 {
		t.Errorf("Expected 3 successes, got %d", resp1.Success)
	}

	// Second batch: Re-sync with NEW sample IDs (simulates HealthKit DB restore)
	secondBatch := &models.BatchCreateEventsRequest{
		Events: []models.CreateEventRequest{
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC), // Same timestamp
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("new-sample-1"), // DIFFERENT sample ID
				HealthKitCategory: ptr(workoutCategory),
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 16, 11, 0, 0, 0, time.UTC), // Same timestamp
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("new-sample-2"), // DIFFERENT sample ID
				HealthKitCategory: ptr(workoutCategory),
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 17, 12, 0, 0, 0, time.UTC), // Same timestamp
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("new-sample-3"), // DIFFERENT sample ID
				HealthKitCategory: ptr(workoutCategory),
			},
		},
	}

	resp2, err := service.CreateEventsBatch(ctx, userID, secondBatch)
	if err != nil {
		t.Fatalf("Second batch failed: %v", err)
	}
	if resp2.Success != 3 {
		t.Errorf("Expected 3 successes, got %d", resp2.Success)
	}

	// Verify still only 3 events (content-based dedupe should prevent duplicates)
	events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
	if len(events) != 3 {
		t.Errorf("Expected 3 events after content-based dedupe, got %d", len(events))
	}
}

// TestCreateEventsBatch_HealthKit_MixedDeduplication tests batch import
// with mixed sample ID and content-based deduplication.
func TestCreateEventsBatch_HealthKit_MixedDeduplication(t *testing.T) {
	ctx := context.Background()

	eventRepo := newMockEventRepository()
	eventTypeRepo := newMockEventTypeRepository()
	changeLogRepo := newMockChangeLogRepository()

	service := NewEventService(eventRepo, eventTypeRepo, changeLogRepo)

	userID := "user-123"
	eventType, _ := eventTypeRepo.Create(ctx, &models.EventType{
		UserID: userID,
		Name:   "Workout",
	})

	workoutCategory := "workout"

	// First batch: Create 2 workouts
	firstBatch := &models.BatchCreateEventsRequest{
		Events: []models.CreateEventRequest{
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("sample-1"),
				HealthKitCategory: ptr(workoutCategory),
			},
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 16, 11, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("sample-2"),
				HealthKitCategory: ptr(workoutCategory),
			},
		},
	}

	_, _ = service.CreateEventsBatch(ctx, userID, firstBatch)

	// Second batch: Mix of same sample ID, same content/different sample, and new
	secondBatch := &models.BatchCreateEventsRequest{
		Events: []models.CreateEventRequest{
			// Duplicate by sample ID (same sample-1)
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 15, 10, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("sample-1"), // Same sample ID
				HealthKitCategory: ptr(workoutCategory),
			},
			// Duplicate by content (same timestamp/type/category, different sample ID)
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 16, 11, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("sample-2-new"), // Different sample ID
				HealthKitCategory: ptr(workoutCategory),
			},
			// Genuinely new event
			{
				EventTypeID:       eventType.ID,
				Timestamp:         time.Date(2025, 1, 17, 12, 0, 0, 0, time.UTC),
				SourceType:        "healthkit",
				HealthKitSampleID: ptr("sample-3"),
				HealthKitCategory: ptr(workoutCategory),
			},
		},
	}

	resp, err := service.CreateEventsBatch(ctx, userID, secondBatch)
	if err != nil {
		t.Fatalf("Second batch failed: %v", err)
	}
	if resp.Success != 3 {
		t.Errorf("Expected 3 successes, got %d", resp.Success)
	}

	// Verify 3 total events (2 original + 1 new)
	events, _ := eventRepo.GetByUserID(ctx, userID, 100, 0)
	if len(events) != 3 {
		t.Errorf("Expected 3 events (2 deduped + 1 new), got %d", len(events))
	}
}
