package service

import (
	"context"
	"sync"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/repository"
)

// SyncStatus represents comprehensive sync state for a user
type SyncStatus struct {
	LastSync        *time.Time      `json:"last_sync,omitempty"`
	LastEvent       *time.Time      `json:"last_event,omitempty"`
	LastEventType   *time.Time      `json:"last_event_type,omitempty"`
	Counts          SyncCounts      `json:"counts"`
	HealthKit       HealthKitStatus `json:"healthkit"`
	LatestCursor    int64           `json:"latest_cursor"`
	Status          string          `json:"status"`
	Recommendations []string        `json:"recommendations,omitempty"`
}

type SyncCounts struct {
	Events     int64 `json:"events"`
	EventTypes int64 `json:"event_types"`
}

type HealthKitStatus struct {
	LastSync *time.Time `json:"last_sync,omitempty"`
	Count    int64      `json:"count"`
}

type syncService struct {
	eventRepo     repository.EventRepository
	eventTypeRepo repository.EventTypeRepository
	changeLogRepo repository.ChangeLogRepository
}

func NewSyncService(
	eventRepo repository.EventRepository,
	eventTypeRepo repository.EventTypeRepository,
	changeLogRepo repository.ChangeLogRepository,
) SyncService {
	return &syncService{eventRepo: eventRepo, eventTypeRepo: eventTypeRepo, changeLogRepo: changeLogRepo}
}

func (s *syncService) GetSyncStatus(ctx context.Context, userID string) (*SyncStatus, error) {
	var wg sync.WaitGroup
	var mu sync.Mutex
	var firstErr error
	var eventCount, eventTypeCount, healthKitCount, latestCursor int64
	var lastEvent, lastEventType, lastHealthKit *time.Time

	setError := func(err error) {
		mu.Lock()
		if firstErr == nil {
			firstErr = err
		}
		mu.Unlock()
	}

	wg.Add(7)
	go func() {
		defer wg.Done()
		c, e := s.eventRepo.CountByUser(ctx, userID)
		if e != nil {
			setError(e)
			return
		}
		mu.Lock()
		eventCount = c
		mu.Unlock()
	}()
	go func() {
		defer wg.Done()
		c, e := s.eventTypeRepo.CountByUser(ctx, userID)
		if e != nil {
			setError(e)
			return
		}
		mu.Lock()
		eventTypeCount = c
		mu.Unlock()
	}()
	go func() {
		defer wg.Done()
		c, e := s.eventRepo.CountHealthKitByUser(ctx, userID)
		if e != nil {
			setError(e)
			return
		}
		mu.Lock()
		healthKitCount = c
		mu.Unlock()
	}()
	go func() {
		defer wg.Done()
		c, e := s.changeLogRepo.GetLatestCursor(ctx, userID)
		if e != nil {
			setError(e)
			return
		}
		mu.Lock()
		latestCursor = c
		mu.Unlock()
	}()
	go func() {
		defer wg.Done()
		t, e := s.eventRepo.GetLatestTimestamp(ctx, userID)
		if e != nil {
			setError(e)
			return
		}
		mu.Lock()
		lastEvent = t
		mu.Unlock()
	}()
	go func() {
		defer wg.Done()
		t, e := s.eventTypeRepo.GetLatestTimestamp(ctx, userID)
		if e != nil {
			setError(e)
			return
		}
		mu.Lock()
		lastEventType = t
		mu.Unlock()
	}()
	go func() {
		defer wg.Done()
		t, e := s.eventRepo.GetLatestHealthKitTimestamp(ctx, userID)
		if e != nil {
			setError(e)
			return
		}
		mu.Lock()
		lastHealthKit = t
		mu.Unlock()
	}()
	wg.Wait()

	if firstErr != nil {
		return nil, firstErr
	}

	status, recs := computeSyncRecommendations(eventCount, eventTypeCount, healthKitCount, latestCursor, lastEvent, lastEventType)
	return &SyncStatus{
		LastEvent: lastEvent, LastEventType: lastEventType,
		Counts:       SyncCounts{Events: eventCount, EventTypes: eventTypeCount},
		HealthKit:    HealthKitStatus{LastSync: lastHealthKit, Count: healthKitCount},
		LatestCursor: latestCursor, Status: status, Recommendations: recs,
	}, nil
}

func computeSyncRecommendations(eventCount, eventTypeCount, healthKitCount, latestCursor int64, lastEvent, lastEventType *time.Time) (string, []string) {
	var recs []string
	if eventTypeCount == 0 {
		recs = append(recs, "No event types found. Create event types to start tracking.")
	}
	if eventCount == 0 && eventTypeCount > 0 {
		recs = append(recs, "No events recorded yet. Start tracking to see data.")
	}
	status := "all_synced"
	if latestCursor == 0 && (eventCount > 0 || eventTypeCount > 0) {
		status = "resync_recommended"
		recs = append(recs, "Change log is empty but data exists. Consider a full sync.")
	}
	if len(recs) > 0 && status == "all_synced" {
		status = "pending_changes"
	}
	return status, recs
}
