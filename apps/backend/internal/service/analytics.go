package service

import (
	"context"
	"fmt"
	"math"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
)

type analyticsService struct {
	eventRepo repository.EventRepository
}

// NewAnalyticsService creates a new analytics service
func NewAnalyticsService(eventRepo repository.EventRepository) AnalyticsService {
	return &analyticsService{
		eventRepo: eventRepo,
	}
}

func (s *analyticsService) GetSummary(ctx context.Context, userID string) (*models.AnalyticsSummary, error) {
	// Get total event counts by type
	eventTypeCounts, err := s.eventRepo.CountByEventType(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get event type counts: %w", err)
	}

	// Get recent events (last 10)
	recentEvents, err := s.eventRepo.GetByUserID(ctx, userID, 10, 0)
	if err != nil {
		return nil, fmt.Errorf("failed to get recent events: %w", err)
	}

	totalEvents := int64(0)
	for _, count := range eventTypeCounts {
		totalEvents += count
	}

	return &models.AnalyticsSummary{
		TotalEvents:     totalEvents,
		EventTypeCounts: eventTypeCounts,
		RecentEvents:    recentEvents,
	}, nil
}

func (s *analyticsService) GetTrends(ctx context.Context, userID string, period string, startDate, endDate time.Time) ([]models.TrendData, error) {
	// Get all events in the date range
	events, err := s.eventRepo.GetByUserIDAndDateRange(ctx, userID, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get events: %w", err)
	}

	// Group events by event type
	eventsByType := make(map[string][]models.Event)
	for _, event := range events {
		eventsByType[event.EventTypeID] = append(eventsByType[event.EventTypeID], event)
	}

	// Calculate trends for each event type
	trends := []models.TrendData{}
	for eventTypeID, typeEvents := range eventsByType {
		trendData := s.calculateTrend(eventTypeID, typeEvents, period, startDate, endDate)
		trends = append(trends, *trendData)
	}

	return trends, nil
}

func (s *analyticsService) GetEventTypeAnalytics(ctx context.Context, userID, eventTypeID string, period string, startDate, endDate time.Time) (*models.TrendData, error) {
	// Get events for this event type in the date range
	allEvents, err := s.eventRepo.GetByUserIDAndDateRange(ctx, userID, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to get events: %w", err)
	}

	// Filter for the specific event type
	events := []models.Event{}
	for _, event := range allEvents {
		if event.EventTypeID == eventTypeID {
			events = append(events, event)
		}
	}

	return s.calculateTrend(eventTypeID, events, period, startDate, endDate), nil
}

func (s *analyticsService) calculateTrend(eventTypeID string, events []models.Event, period string, startDate, endDate time.Time) *models.TrendData {
	// Group events by time bucket based on period
	buckets := s.createTimeBuckets(period, startDate, endDate)
	dataPoints := []models.TimeSeriesDataPoint{}

	for _, bucket := range buckets {
		count := int64(0)
		for _, event := range events {
			if event.Timestamp.After(bucket) && event.Timestamp.Before(bucket.Add(s.getBucketDuration(period))) {
				count++
			}
		}
		dataPoints = append(dataPoints, models.TimeSeriesDataPoint{
			Date:  bucket,
			Count: count,
		})
	}

	// Calculate average
	total := int64(0)
	for _, dp := range dataPoints {
		total += dp.Count
	}
	average := float64(total) / float64(len(dataPoints))

	// Determine trend direction
	trend := s.determineTrend(dataPoints)

	return &models.TrendData{
		EventTypeID: eventTypeID,
		Period:      period,
		Data:        dataPoints,
		Average:     average,
		Trend:       trend,
	}
}

func (s *analyticsService) createTimeBuckets(period string, startDate, endDate time.Time) []time.Time {
	buckets := []time.Time{}
	current := startDate
	duration := s.getBucketDuration(period)

	for current.Before(endDate) {
		buckets = append(buckets, current)
		current = current.Add(duration)
	}

	return buckets
}

func (s *analyticsService) getBucketDuration(period string) time.Duration {
	switch period {
	case "week":
		return 24 * time.Hour // Daily buckets for week view
	case "month":
		return 24 * time.Hour // Daily buckets for month view
	case "year":
		return 7 * 24 * time.Hour // Weekly buckets for year view
	default:
		return 24 * time.Hour
	}
}

func (s *analyticsService) determineTrend(dataPoints []models.TimeSeriesDataPoint) string {
	if len(dataPoints) < 2 {
		return "stable"
	}

	// Simple linear regression to determine trend
	n := float64(len(dataPoints))
	sumX := 0.0
	sumY := 0.0
	sumXY := 0.0
	sumXX := 0.0

	for i, dp := range dataPoints {
		x := float64(i)
		y := float64(dp.Count)
		sumX += x
		sumY += y
		sumXY += x * y
		sumXX += x * x
	}

	slope := (n*sumXY - sumX*sumY) / (n*sumXX - sumX*sumX)

	// Use threshold to determine trend
	if math.Abs(slope) < 0.1 {
		return "stable"
	} else if slope > 0 {
		return "increasing"
	} else {
		return "decreasing"
	}
}
