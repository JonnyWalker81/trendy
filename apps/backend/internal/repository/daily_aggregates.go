package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

type dailyAggregateRepository struct {
	client *supabase.Client
}

// NewDailyAggregateRepository creates a new daily aggregate repository
func NewDailyAggregateRepository(client *supabase.Client) DailyAggregateRepository {
	return &dailyAggregateRepository{client: client}
}

func (r *dailyAggregateRepository) Upsert(ctx context.Context, agg *models.DailyAggregate) (*models.DailyAggregate, error) {
	data := map[string]interface{}{
		"user_id":       agg.UserID,
		"date":          agg.Date.Format("2006-01-02"),
		"event_type_id": agg.EventTypeID,
		"event_count":   agg.EventCount,
	}

	if agg.TotalDurationSeconds != nil {
		data["total_duration_seconds"] = *agg.TotalDurationSeconds
	}
	if agg.AvgNumericValue != nil {
		data["avg_numeric_value"] = *agg.AvgNumericValue
	}
	if agg.PropertyAggregates != nil && len(agg.PropertyAggregates) > 0 {
		data["property_aggregates"] = agg.PropertyAggregates
	}

	body, err := r.client.Upsert("daily_aggregates", data, "user_id,date,event_type_id")
	if err != nil {
		return nil, fmt.Errorf("failed to upsert daily aggregate: %w", err)
	}

	var aggs []models.DailyAggregate
	if err := json.Unmarshal(body, &aggs); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(aggs) == 0 {
		return nil, fmt.Errorf("no daily aggregate returned")
	}

	return &aggs[0], nil
}

func (r *dailyAggregateRepository) BulkUpsert(ctx context.Context, aggs []models.DailyAggregate) error {
	if len(aggs) == 0 {
		return nil
	}

	data := make([]map[string]interface{}, len(aggs))
	for i, agg := range aggs {
		item := map[string]interface{}{
			"user_id":       agg.UserID,
			"date":          agg.Date.Format("2006-01-02"),
			"event_type_id": agg.EventTypeID,
			"event_count":   agg.EventCount,
		}

		if agg.TotalDurationSeconds != nil {
			item["total_duration_seconds"] = *agg.TotalDurationSeconds
		}
		if agg.AvgNumericValue != nil {
			item["avg_numeric_value"] = *agg.AvgNumericValue
		}
		if agg.PropertyAggregates != nil && len(agg.PropertyAggregates) > 0 {
			item["property_aggregates"] = agg.PropertyAggregates
		}

		data[i] = item
	}

	_, err := r.client.Upsert("daily_aggregates", data, "user_id,date,event_type_id")
	if err != nil {
		return fmt.Errorf("failed to bulk upsert daily aggregates: %w", err)
	}

	return nil
}

func (r *dailyAggregateRepository) GetByUserID(ctx context.Context, userID string) ([]models.DailyAggregate, error) {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"select":  "*,event_type:event_types(*)",
		"order":   "date.desc",
	}

	body, err := r.client.Query("daily_aggregates", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get daily aggregates: %w", err)
	}

	var aggs []models.DailyAggregate
	if err := json.Unmarshal(body, &aggs); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return aggs, nil
}

func (r *dailyAggregateRepository) GetByUserIDAndDateRange(ctx context.Context, userID string, startDate, endDate time.Time) ([]models.DailyAggregate, error) {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"and":     fmt.Sprintf("(date.gte.%s,date.lte.%s)", startDate.Format("2006-01-02"), endDate.Format("2006-01-02")),
		"select":  "*,event_type:event_types(*)",
		"order":   "date.asc",
	}

	body, err := r.client.Query("daily_aggregates", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get daily aggregates: %w", err)
	}

	var aggs []models.DailyAggregate
	if err := json.Unmarshal(body, &aggs); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return aggs, nil
}

func (r *dailyAggregateRepository) GetByUserIDAndEventType(ctx context.Context, userID, eventTypeID string, startDate, endDate time.Time) ([]models.DailyAggregate, error) {
	query := map[string]interface{}{
		"user_id":       fmt.Sprintf("eq.%s", userID),
		"event_type_id": fmt.Sprintf("eq.%s", eventTypeID),
		"and":           fmt.Sprintf("(date.gte.%s,date.lte.%s)", startDate.Format("2006-01-02"), endDate.Format("2006-01-02")),
		"select":        "*,event_type:event_types(*)",
		"order":         "date.asc",
	}

	body, err := r.client.Query("daily_aggregates", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get daily aggregates: %w", err)
	}

	var aggs []models.DailyAggregate
	if err := json.Unmarshal(body, &aggs); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return aggs, nil
}

func (r *dailyAggregateRepository) DeleteByUserID(ctx context.Context, userID string) error {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
	}

	if err := r.client.DeleteWhere("daily_aggregates", query); err != nil {
		return fmt.Errorf("failed to delete daily aggregates: %w", err)
	}

	return nil
}

func (r *dailyAggregateRepository) DeleteOlderThan(ctx context.Context, userID string, date time.Time) error {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"date":    fmt.Sprintf("lt.%s", date.Format("2006-01-02")),
	}

	if err := r.client.DeleteWhere("daily_aggregates", query); err != nil {
		return fmt.Errorf("failed to delete old daily aggregates: %w", err)
	}

	return nil
}
