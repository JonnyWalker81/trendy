package service

import (
	"context"
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
)

const (
	// Minimum days of data required for correlation analysis
	MinDaysForCorrelation = 14

	// Minimum events required for pattern analysis
	MinEventsForPattern = 7

	// Cache validity duration
	InsightCacheDuration = 6 * time.Hour

	// Correlation thresholds
	CorrelationThresholdHigh   = 0.5
	CorrelationThresholdMedium = 0.3
	CorrelationThresholdLow    = 0.2

	// P-value thresholds
	PValueThresholdHigh   = 0.01
	PValueThresholdMedium = 0.05
	PValueThresholdLow    = 0.10
)

type intelligenceService struct {
	eventRepo     repository.EventRepository
	eventTypeRepo repository.EventTypeRepository
	insightRepo   repository.InsightRepository
	aggregateRepo repository.DailyAggregateRepository
	streakRepo    repository.StreakRepository
}

// NewIntelligenceService creates a new intelligence service
func NewIntelligenceService(
	eventRepo repository.EventRepository,
	eventTypeRepo repository.EventTypeRepository,
	insightRepo repository.InsightRepository,
	aggregateRepo repository.DailyAggregateRepository,
	streakRepo repository.StreakRepository,
) IntelligenceService {
	return &intelligenceService{
		eventRepo:     eventRepo,
		eventTypeRepo: eventTypeRepo,
		insightRepo:   insightRepo,
		aggregateRepo: aggregateRepo,
		streakRepo:    streakRepo,
	}
}

// GetInsights returns all insights for a user, computing if necessary
func (s *intelligenceService) GetInsights(ctx context.Context, userID string) (*models.InsightsResponse, error) {
	// Check for valid cached insights
	cachedInsights, err := s.insightRepo.GetValidByUserID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get cached insights: %w", err)
	}

	// If we have cached insights, return them
	if len(cachedInsights) > 0 {
		return s.buildInsightsResponse(cachedInsights)
	}

	// Otherwise, compute new insights
	if err := s.ComputeInsights(ctx, userID); err != nil {
		return nil, fmt.Errorf("failed to compute insights: %w", err)
	}

	// Fetch the newly computed insights
	newInsights, err := s.insightRepo.GetValidByUserID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get new insights: %w", err)
	}

	return s.buildInsightsResponse(newInsights)
}

// ComputeInsights calculates all insights for a user
func (s *intelligenceService) ComputeInsights(ctx context.Context, userID string) error {
	// Delete existing insights
	if err := s.insightRepo.DeleteByUserID(ctx, userID); err != nil {
		return fmt.Errorf("failed to delete existing insights: %w", err)
	}

	// Get all events for the user (last 90 days for correlation analysis)
	endDate := time.Now()
	startDate := endDate.AddDate(0, 0, -90)

	events, err := s.eventRepo.GetByUserIDAndDateRange(ctx, userID, startDate, endDate)
	if err != nil {
		return fmt.Errorf("failed to get events: %w", err)
	}

	if len(events) == 0 {
		return nil // No events, nothing to compute
	}

	// Get event types
	eventTypes, err := s.eventTypeRepo.GetByUserID(ctx, userID)
	if err != nil {
		return fmt.Errorf("failed to get event types: %w", err)
	}

	// Build daily aggregates
	aggregates := s.buildDailyAggregates(events, userID)

	// Store daily aggregates
	if err := s.aggregateRepo.BulkUpsert(ctx, aggregates); err != nil {
		return fmt.Errorf("failed to store daily aggregates: %w", err)
	}

	// Compute correlations
	correlationInsights := s.computeCorrelations(ctx, userID, aggregates, eventTypes)

	// Compute streaks
	streakInsights := s.computeStreaks(ctx, userID, events, eventTypes)

	// Compute time patterns
	patternInsights := s.computeTimePatterns(ctx, userID, events, eventTypes)

	// Combine all insights
	allInsights := make([]models.Insight, 0)
	allInsights = append(allInsights, correlationInsights...)
	allInsights = append(allInsights, streakInsights...)
	allInsights = append(allInsights, patternInsights...)

	// Store insights
	if len(allInsights) > 0 {
		if err := s.insightRepo.BulkCreate(ctx, allInsights); err != nil {
			return fmt.Errorf("failed to store insights: %w", err)
		}
	}

	return nil
}

// RefreshIfStale checks if insights are stale and recomputes if necessary
func (s *intelligenceService) RefreshIfStale(ctx context.Context, userID string) error {
	validInsights, err := s.insightRepo.GetValidByUserID(ctx, userID)
	if err != nil {
		return fmt.Errorf("failed to check cached insights: %w", err)
	}

	if len(validInsights) == 0 {
		return s.ComputeInsights(ctx, userID)
	}

	return nil
}

// InvalidateInsights marks all insights as stale (called when events change)
func (s *intelligenceService) InvalidateInsights(ctx context.Context, userID string) error {
	return s.insightRepo.InvalidateAll(ctx, userID)
}

// GetWeeklySummary returns week-over-week comparison
func (s *intelligenceService) GetWeeklySummary(ctx context.Context, userID string) ([]models.WeeklySummary, error) {
	now := time.Now()
	thisWeekStart := now.AddDate(0, 0, -int(now.Weekday()))
	lastWeekStart := thisWeekStart.AddDate(0, 0, -7)
	twoWeeksAgo := lastWeekStart.AddDate(0, 0, -7)

	events, err := s.eventRepo.GetByUserIDAndDateRange(ctx, userID, twoWeeksAgo, now)
	if err != nil {
		return nil, fmt.Errorf("failed to get events: %w", err)
	}

	eventTypes, err := s.eventTypeRepo.GetByUserID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get event types: %w", err)
	}

	return s.calculateWeeklySummary(events, eventTypes, thisWeekStart, lastWeekStart), nil
}

// GetStreaks returns all streaks for a user
func (s *intelligenceService) GetStreaks(ctx context.Context, userID string) ([]models.Streak, error) {
	return s.streakRepo.GetByUserID(ctx, userID)
}

// =============================================================================
// Statistical Algorithms
// =============================================================================

// calculatePearsonCorrelation computes Pearson correlation coefficient and p-value
func calculatePearsonCorrelation(xValues, yValues []float64) (r, pValue float64, err error) {
	n := len(xValues)
	if n != len(yValues) {
		return 0, 1, fmt.Errorf("arrays must have same length")
	}
	if n < MinDaysForCorrelation {
		return 0, 1, fmt.Errorf("need at least %d days, got %d", MinDaysForCorrelation, n)
	}

	// Calculate means
	var sumX, sumY float64
	for i := 0; i < n; i++ {
		sumX += xValues[i]
		sumY += yValues[i]
	}
	meanX := sumX / float64(n)
	meanY := sumY / float64(n)

	// Calculate correlation coefficient
	var numerator, denomX, denomY float64
	for i := 0; i < n; i++ {
		dx := xValues[i] - meanX
		dy := yValues[i] - meanY
		numerator += dx * dy
		denomX += dx * dx
		denomY += dy * dy
	}

	if denomX == 0 || denomY == 0 {
		return 0, 1, nil // No variance, no correlation
	}

	r = numerator / math.Sqrt(denomX*denomY)

	// Calculate t-statistic and p-value
	if math.Abs(r) >= 1.0 {
		pValue = 0
	} else {
		t := r * math.Sqrt(float64(n-2)/(1-r*r))
		// Two-tailed p-value using normal approximation for large n
		pValue = 2 * (1 - normalCDF(math.Abs(t)))
	}

	return r, pValue, nil
}

// normalCDF calculates the cumulative distribution function for standard normal
func normalCDF(x float64) float64 {
	return 0.5 * (1 + math.Erf(x/math.Sqrt(2)))
}

// calculateLagCorrelation computes correlation with a time lag
func calculateLagCorrelation(aValues, bValues []float64, lag int) (r, pValue float64, err error) {
	n := len(aValues) - lag
	if n < MinDaysForCorrelation {
		return 0, 1, fmt.Errorf("insufficient data after lag")
	}

	shiftedA := aValues[:n]
	shiftedB := bValues[lag : lag+n]

	return calculatePearsonCorrelation(shiftedA, shiftedB)
}

// calculateConsistency computes normalized entropy (1 = very consistent, 0 = random)
func calculateConsistency(distribution []float64) float64 {
	n := len(distribution)
	if n == 0 {
		return 0
	}

	// Calculate total for normalization
	var total float64
	for _, v := range distribution {
		total += v
	}
	if total == 0 {
		return 0
	}

	// Calculate entropy
	var entropy float64
	for _, v := range distribution {
		if v > 0 {
			prob := v / total
			entropy -= prob * math.Log2(prob)
		}
	}

	// Normalize by maximum entropy
	maxEntropy := math.Log2(float64(n))
	if maxEntropy == 0 {
		return 1
	}

	return 1 - (entropy / maxEntropy)
}

// =============================================================================
// Helper Methods
// =============================================================================

// buildDailyAggregates creates daily aggregates from events
func (s *intelligenceService) buildDailyAggregates(events []models.Event, userID string) []models.DailyAggregate {
	// Group events by date and event type
	aggregateMap := make(map[string]*models.DailyAggregate) // key: "date|eventTypeID"

	for _, event := range events {
		dateStr := event.Timestamp.Format("2006-01-02")
		key := fmt.Sprintf("%s|%s", dateStr, event.EventTypeID)

		if agg, exists := aggregateMap[key]; exists {
			agg.EventCount++
		} else {
			date, _ := time.Parse("2006-01-02", dateStr)
			aggregateMap[key] = &models.DailyAggregate{
				UserID:      userID,
				Date:        date,
				EventTypeID: event.EventTypeID,
				EventCount:  1,
			}
		}
	}

	// Convert map to slice
	aggregates := make([]models.DailyAggregate, 0, len(aggregateMap))
	for _, agg := range aggregateMap {
		aggregates = append(aggregates, *agg)
	}

	return aggregates
}

// computeCorrelations calculates correlations between event types
func (s *intelligenceService) computeCorrelations(ctx context.Context, userID string, aggregates []models.DailyAggregate, eventTypes []models.EventType) []models.Insight {
	if len(eventTypes) < 2 {
		return nil
	}

	// Build time series for each event type
	// Map: eventTypeID -> map[date] -> count
	timeSeriesMap := make(map[string]map[string]int)
	allDates := make(map[string]bool)

	for _, agg := range aggregates {
		dateStr := agg.Date.Format("2006-01-02")
		allDates[dateStr] = true

		if _, exists := timeSeriesMap[agg.EventTypeID]; !exists {
			timeSeriesMap[agg.EventTypeID] = make(map[string]int)
		}
		timeSeriesMap[agg.EventTypeID][dateStr] = agg.EventCount
	}

	// Sort dates
	dates := make([]string, 0, len(allDates))
	for d := range allDates {
		dates = append(dates, d)
	}
	sort.Strings(dates)

	if len(dates) < MinDaysForCorrelation {
		return nil
	}

	// Create event type map for quick lookup
	eventTypeMap := make(map[string]models.EventType)
	for _, et := range eventTypes {
		eventTypeMap[et.ID] = et
	}

	insights := make([]models.Insight, 0)
	now := time.Now()
	validUntil := now.Add(InsightCacheDuration)

	// Calculate correlation for each pair of event types
	for i := 0; i < len(eventTypes); i++ {
		for j := i + 1; j < len(eventTypes); j++ {
			etA := eventTypes[i]
			etB := eventTypes[j]

			// Build aligned time series
			xValues := make([]float64, len(dates))
			yValues := make([]float64, len(dates))

			for k, date := range dates {
				if count, exists := timeSeriesMap[etA.ID][date]; exists {
					xValues[k] = float64(count)
				}
				if count, exists := timeSeriesMap[etB.ID][date]; exists {
					yValues[k] = float64(count)
				}
			}

			// Calculate correlation
			r, pValue, err := calculatePearsonCorrelation(xValues, yValues)
			if err != nil {
				continue
			}

			// Only keep significant correlations
			if math.Abs(r) < CorrelationThresholdLow || pValue > PValueThresholdLow {
				continue
			}

			// Determine confidence
			confidence := determineConfidence(r, pValue, len(dates))

			// Determine direction
			direction := models.DirectionNeutral
			if r > 0 {
				direction = models.DirectionPositive
			} else if r < 0 {
				direction = models.DirectionNegative
			}

			// Build insight
			title := fmt.Sprintf("%s and %s", etA.Name, etB.Name)
			description := buildCorrelationDescription(etA.Name, etB.Name, r, direction)

			etAID := etA.ID
			etBID := etB.ID

			insight := models.Insight{
				UserID:       userID,
				InsightType:  models.InsightTypeCorrelation,
				Category:     models.InsightCategoryCrossEvent,
				Title:        title,
				Description:  description,
				EventTypeAID: &etAID,
				EventTypeBID: &etBID,
				MetricValue:  r,
				PValue:       &pValue,
				SampleSize:   len(dates),
				Confidence:   confidence,
				Direction:    direction,
				ComputedAt:   now,
				ValidUntil:   validUntil,
				EventTypeA:   &etA,
				EventTypeB:   &etB,
			}

			insights = append(insights, insight)
		}
	}

	// Sort by absolute correlation value (strongest first)
	sort.Slice(insights, func(i, j int) bool {
		return math.Abs(insights[i].MetricValue) > math.Abs(insights[j].MetricValue)
	})

	// Limit to top 10 correlations
	if len(insights) > 10 {
		insights = insights[:10]
	}

	return insights
}

// computeStreaks calculates current and longest streaks for each event type
func (s *intelligenceService) computeStreaks(ctx context.Context, userID string, events []models.Event, eventTypes []models.EventType) []models.Insight {
	insights := make([]models.Insight, 0)
	now := time.Now()
	validUntil := now.Add(InsightCacheDuration)

	// Create event type map
	eventTypeMap := make(map[string]models.EventType)
	for _, et := range eventTypes {
		eventTypeMap[et.ID] = et
	}

	// Calculate streaks for each event type
	for _, et := range eventTypes {
		current, longest := calculateStreaksForEventType(events, et.ID)

		// Save current streak if active
		if current.Length > 0 {
			streak := models.Streak{
				UserID:      userID,
				EventTypeID: et.ID,
				StreakType:  models.StreakTypeCurrent,
				StartDate:   current.StartDate,
				Length:      current.Length,
				IsActive:    current.IsActive,
				EventType:   &et,
			}

			// Save to repository
			s.streakRepo.Upsert(ctx, &streak)

			// Create insight for active streak
			if current.IsActive && current.Length >= 2 {
				etID := et.ID
				isNew := current.Length >= longest.Length

				description := fmt.Sprintf("You've done %s for %d days in a row", et.Name, current.Length)
				if isNew {
					description += " - your best streak!"
				}

				insight := models.Insight{
					UserID:       userID,
					InsightType:  models.InsightTypeStreak,
					Category:     models.InsightCategoryStreak,
					Title:        fmt.Sprintf("%s Streak", et.Name),
					Description:  description,
					EventTypeAID: &etID,
					MetricValue:  float64(current.Length),
					SampleSize:   current.Length,
					Confidence:   models.ConfidenceHigh,
					Direction:    models.DirectionPositive,
					ComputedAt:   now,
					ValidUntil:   validUntil,
					EventTypeA:   &et,
					Metadata: map[string]interface{}{
						"is_longest":    isNew,
						"previous_best": longest.Length,
						"start_date":    current.StartDate,
						"streak_type":   "current",
						"is_active":     current.IsActive,
					},
				}

				insights = append(insights, insight)
			}
		}

		// Save longest streak
		if longest.Length > 0 {
			streak := models.Streak{
				UserID:      userID,
				EventTypeID: et.ID,
				StreakType:  models.StreakTypeLongest,
				StartDate:   longest.StartDate,
				EndDate:     longest.EndDate,
				Length:      longest.Length,
				IsActive:    false,
				EventType:   &et,
			}

			s.streakRepo.Upsert(ctx, &streak)
		}
	}

	return insights
}

// calculateStreaksForEventType finds current and longest streaks
func calculateStreaksForEventType(events []models.Event, eventTypeID string) (current, longest models.Streak) {
	// Get unique dates for this event type
	eventDates := make(map[string]bool)
	for _, e := range events {
		if e.EventTypeID == eventTypeID {
			dateStr := e.Timestamp.Format("2006-01-02")
			eventDates[dateStr] = true
		}
	}

	if len(eventDates) == 0 {
		return
	}

	// Sort dates
	dates := make([]time.Time, 0, len(eventDates))
	for dateStr := range eventDates {
		t, _ := time.Parse("2006-01-02", dateStr)
		dates = append(dates, t)
	}
	sort.Slice(dates, func(i, j int) bool { return dates[i].Before(dates[j]) })

	// Find streaks
	var currentStart time.Time
	currentLength := 0
	longestStart := dates[0]
	longestLength := 1
	longestEnd := dates[0]

	for i := 0; i < len(dates); i++ {
		if i == 0 {
			currentStart = dates[i]
			currentLength = 1
		} else {
			diff := dates[i].Sub(dates[i-1]).Hours() / 24
			if diff <= 1 {
				currentLength++
			} else {
				// Streak broken, check if it was longest
				if currentLength > longestLength {
					longestLength = currentLength
					longestStart = currentStart
					longestEnd = dates[i-1]
				}
				currentStart = dates[i]
				currentLength = 1
			}
		}
	}

	// Check final streak
	if currentLength > longestLength {
		longestLength = currentLength
		longestStart = currentStart
		longestEnd = dates[len(dates)-1]
	}

	// Check if current streak is still active (last event within 48 hours)
	today := time.Now().Truncate(24 * time.Hour)
	lastEventDate := dates[len(dates)-1]
	isActive := today.Sub(lastEventDate).Hours() <= 48

	if isActive {
		current = models.Streak{
			EventTypeID: eventTypeID,
			StreakType:  models.StreakTypeCurrent,
			StartDate:   currentStart,
			Length:      currentLength,
			IsActive:    true,
		}
	}

	longest = models.Streak{
		EventTypeID: eventTypeID,
		StreakType:  models.StreakTypeLongest,
		StartDate:   longestStart,
		EndDate:     &longestEnd,
		Length:      longestLength,
	}

	return
}

// computeTimePatterns analyzes time-of-day and day-of-week patterns
func (s *intelligenceService) computeTimePatterns(ctx context.Context, userID string, events []models.Event, eventTypes []models.EventType) []models.Insight {
	insights := make([]models.Insight, 0)
	now := time.Now()
	validUntil := now.Add(InsightCacheDuration)

	// Create event type map
	eventTypeMap := make(map[string]models.EventType)
	for _, et := range eventTypes {
		eventTypeMap[et.ID] = et
	}

	for _, et := range eventTypes {
		// Filter events for this type
		typeEvents := make([]models.Event, 0)
		for _, e := range events {
			if e.EventTypeID == et.ID {
				typeEvents = append(typeEvents, e)
			}
		}

		if len(typeEvents) < MinEventsForPattern {
			continue
		}

		// Day of week pattern
		dowPattern := calculateDayOfWeekPattern(typeEvents)
		if dowPattern.Consistency > 0.3 {
			etID := et.ID
			insight := models.Insight{
				UserID:       userID,
				InsightType:  models.InsightTypePattern,
				Category:     models.InsightCategoryDayOfWeek,
				Title:        fmt.Sprintf("%s - Best Day", et.Name),
				Description:  fmt.Sprintf("You're most consistent with %s on %s (%.0f%% of sessions)", et.Name, dowPattern.PeakLabel, dowPattern.PeakPercent),
				EventTypeAID: &etID,
				MetricValue:  dowPattern.Consistency,
				SampleSize:   len(typeEvents),
				Confidence:   determinePatternConfidence(dowPattern.Consistency, len(typeEvents)),
				Direction:    models.DirectionNeutral,
				ComputedAt:   now,
				ValidUntil:   validUntil,
				EventTypeA:   &et,
				Metadata: map[string]interface{}{
					"pattern_type": "day_of_week",
					"distribution": dowPattern.Distribution,
					"peak_day":     dowPattern.PeakValue,
					"peak_label":   dowPattern.PeakLabel,
					"peak_percent": dowPattern.PeakPercent,
					"consistency":  dowPattern.Consistency,
				},
			}
			insights = append(insights, insight)
		}

		// Hour of day pattern
		hourPattern := calculateHourPattern(typeEvents)
		if hourPattern.Consistency > 0.3 {
			etID := et.ID
			insight := models.Insight{
				UserID:       userID,
				InsightType:  models.InsightTypePattern,
				Category:     models.InsightCategoryTimeOfDay,
				Title:        fmt.Sprintf("%s - Peak Time", et.Name),
				Description:  fmt.Sprintf("You usually do %s around %s (%.0f%% of sessions)", et.Name, hourPattern.PeakLabel, hourPattern.PeakPercent),
				EventTypeAID: &etID,
				MetricValue:  hourPattern.Consistency,
				SampleSize:   len(typeEvents),
				Confidence:   determinePatternConfidence(hourPattern.Consistency, len(typeEvents)),
				Direction:    models.DirectionNeutral,
				ComputedAt:   now,
				ValidUntil:   validUntil,
				EventTypeA:   &et,
				Metadata: map[string]interface{}{
					"pattern_type": "hour_of_day",
					"distribution": hourPattern.Distribution,
					"peak_hour":    hourPattern.PeakValue,
					"peak_label":   hourPattern.PeakLabel,
					"peak_percent": hourPattern.PeakPercent,
					"consistency":  hourPattern.Consistency,
				},
			}
			insights = append(insights, insight)
		}
	}

	return insights
}

// calculateDayOfWeekPattern analyzes day-of-week distribution
func calculateDayOfWeekPattern(events []models.Event) models.TimePattern {
	dayCounts := make([]float64, 7)
	total := 0

	for _, event := range events {
		day := int(event.Timestamp.Weekday())
		dayCounts[day]++
		total++
	}

	if total == 0 {
		return models.TimePattern{}
	}

	// Find peak day
	maxDay := 0
	maxCount := dayCounts[0]
	for i, count := range dayCounts {
		if count > maxCount {
			maxCount = count
			maxDay = i
		}
	}

	dayNames := []string{"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}

	// Calculate percentages
	distribution := make([]float64, 7)
	for i, count := range dayCounts {
		distribution[i] = (count / float64(total)) * 100
	}

	return models.TimePattern{
		PatternType:  "day_of_week",
		Distribution: distribution,
		PeakValue:    maxDay,
		PeakLabel:    dayNames[maxDay],
		PeakPercent:  distribution[maxDay],
		Consistency:  calculateConsistency(dayCounts),
	}
}

// calculateHourPattern analyzes hour-of-day distribution
func calculateHourPattern(events []models.Event) models.TimePattern {
	hourCounts := make([]float64, 24)
	total := 0

	for _, event := range events {
		hour := event.Timestamp.Hour()
		hourCounts[hour]++
		total++
	}

	if total == 0 {
		return models.TimePattern{}
	}

	// Find peak hour
	maxHour := 0
	maxCount := hourCounts[0]
	for i, count := range hourCounts {
		if count > maxCount {
			maxCount = count
			maxHour = i
		}
	}

	// Calculate percentages
	distribution := make([]float64, 24)
	for i, count := range hourCounts {
		distribution[i] = (count / float64(total)) * 100
	}

	return models.TimePattern{
		PatternType:  "hour_of_day",
		Distribution: distribution,
		PeakValue:    maxHour,
		PeakLabel:    formatHour(maxHour),
		PeakPercent:  distribution[maxHour],
		Consistency:  calculateConsistency(hourCounts),
	}
}

// formatHour formats an hour (0-23) as a readable string
func formatHour(hour int) string {
	if hour == 0 {
		return "12 AM"
	} else if hour < 12 {
		return fmt.Sprintf("%d AM", hour)
	} else if hour == 12 {
		return "12 PM"
	} else {
		return fmt.Sprintf("%d PM", hour-12)
	}
}

// calculateWeeklySummary compares this week to last week
func (s *intelligenceService) calculateWeeklySummary(events []models.Event, eventTypes []models.EventType, thisWeekStart, lastWeekStart time.Time) []models.WeeklySummary {
	summaries := make([]models.WeeklySummary, 0, len(eventTypes))

	for _, et := range eventTypes {
		thisWeekCount := 0
		lastWeekCount := 0

		for _, e := range events {
			if e.EventTypeID != et.ID {
				continue
			}
			if e.Timestamp.After(thisWeekStart) || e.Timestamp.Equal(thisWeekStart) {
				thisWeekCount++
			} else if (e.Timestamp.After(lastWeekStart) || e.Timestamp.Equal(lastWeekStart)) && e.Timestamp.Before(thisWeekStart) {
				lastWeekCount++
			}
		}

		// Skip if no activity in either week
		if thisWeekCount == 0 && lastWeekCount == 0 {
			continue
		}

		// Calculate change
		var changePercent float64
		var direction string

		if lastWeekCount == 0 {
			if thisWeekCount > 0 {
				changePercent = 100
				direction = "up"
			} else {
				changePercent = 0
				direction = "same"
			}
		} else {
			changePercent = (float64(thisWeekCount-lastWeekCount) / float64(lastWeekCount)) * 100
			if changePercent > 5 {
				direction = "up"
			} else if changePercent < -5 {
				direction = "down"
			} else {
				direction = "same"
			}
		}

		summaries = append(summaries, models.WeeklySummary{
			EventTypeID:    et.ID,
			EventTypeName:  et.Name,
			EventTypeColor: et.Color,
			EventTypeIcon:  et.Icon,
			ThisWeekCount:  thisWeekCount,
			LastWeekCount:  lastWeekCount,
			ChangePercent:  changePercent,
			Direction:      direction,
		})
	}

	// Sort by this week count descending
	sort.Slice(summaries, func(i, j int) bool {
		return summaries[i].ThisWeekCount > summaries[j].ThisWeekCount
	})

	return summaries
}

// =============================================================================
// Utility Functions
// =============================================================================

// determineConfidence determines confidence level based on r, p-value, and sample size
func determineConfidence(r, pValue float64, sampleSize int) models.Confidence {
	absR := math.Abs(r)

	if pValue < PValueThresholdHigh && sampleSize > 30 && absR > CorrelationThresholdHigh {
		return models.ConfidenceHigh
	}
	if pValue < PValueThresholdMedium && sampleSize > MinDaysForCorrelation && absR > CorrelationThresholdMedium {
		return models.ConfidenceMedium
	}
	return models.ConfidenceLow
}

// determinePatternConfidence determines confidence for pattern insights
func determinePatternConfidence(consistency float64, sampleSize int) models.Confidence {
	if consistency > 0.6 && sampleSize > 30 {
		return models.ConfidenceHigh
	}
	if consistency > 0.4 && sampleSize > MinEventsForPattern {
		return models.ConfidenceMedium
	}
	return models.ConfidenceLow
}

// buildCorrelationDescription creates a human-readable description
func buildCorrelationDescription(nameA, nameB string, r float64, direction models.Direction) string {
	strength := "somewhat"
	if math.Abs(r) > 0.7 {
		strength = "strongly"
	} else if math.Abs(r) > 0.5 {
		strength = "moderately"
	}

	if direction == models.DirectionPositive {
		return fmt.Sprintf("%s and %s are %s positively correlated (r=%.2f)", nameA, nameB, strength, r)
	} else if direction == models.DirectionNegative {
		return fmt.Sprintf("%s and %s are %s negatively correlated (r=%.2f)", nameA, nameB, strength, r)
	}
	return fmt.Sprintf("%s and %s show no significant correlation", nameA, nameB)
}

// buildInsightsResponse constructs the API response from insights
func (s *intelligenceService) buildInsightsResponse(insights []models.Insight) (*models.InsightsResponse, error) {
	correlations := make([]models.Insight, 0)
	patterns := make([]models.Insight, 0)
	streaks := make([]models.Insight, 0)

	var computedAt time.Time

	for _, insight := range insights {
		if computedAt.IsZero() || insight.ComputedAt.After(computedAt) {
			computedAt = insight.ComputedAt
		}

		switch insight.InsightType {
		case models.InsightTypeCorrelation:
			correlations = append(correlations, insight)
		case models.InsightTypePattern:
			patterns = append(patterns, insight)
		case models.InsightTypeStreak:
			streaks = append(streaks, insight)
		}
	}

	return &models.InsightsResponse{
		Correlations:   correlations,
		Patterns:       patterns,
		Streaks:        streaks,
		WeeklySummary:  nil, // Populated separately via GetWeeklySummary
		ComputedAt:     computedAt,
		DataSufficient: len(insights) > 0,
		TotalDays:      0, // Could calculate from aggregates
	}, nil
}
