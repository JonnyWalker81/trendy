package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/pkg/supabase"
)

type insightRepository struct {
	client *supabase.Client
}

// NewInsightRepository creates a new insight repository
func NewInsightRepository(client *supabase.Client) InsightRepository {
	return &insightRepository{client: client}
}

func (r *insightRepository) Create(ctx context.Context, insight *models.Insight) (*models.Insight, error) {
	data := map[string]interface{}{
		"user_id":      insight.UserID,
		"insight_type": insight.InsightType,
		"category":     insight.Category,
		"title":        insight.Title,
		"description":  insight.Description,
		"metric_value": insight.MetricValue,
		"sample_size":  insight.SampleSize,
		"confidence":   insight.Confidence,
		"direction":    insight.Direction,
		"computed_at":  insight.ComputedAt,
		"valid_until":  insight.ValidUntil,
	}

	if insight.EventTypeAID != nil {
		data["event_type_a_id"] = *insight.EventTypeAID
	}
	if insight.EventTypeBID != nil {
		data["event_type_b_id"] = *insight.EventTypeBID
	}
	if insight.PropertyKey != nil {
		data["property_key"] = *insight.PropertyKey
	}
	if insight.PValue != nil {
		data["p_value"] = *insight.PValue
	}
	if insight.Metadata != nil && len(insight.Metadata) > 0 {
		data["metadata"] = insight.Metadata
	}

	body, err := r.client.Insert("insights", data)
	if err != nil {
		return nil, fmt.Errorf("failed to create insight: %w", err)
	}

	var insights []models.Insight
	if err := json.Unmarshal(body, &insights); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if len(insights) == 0 {
		return nil, fmt.Errorf("no insight returned")
	}

	return &insights[0], nil
}

func (r *insightRepository) BulkCreate(ctx context.Context, insights []models.Insight) error {
	if len(insights) == 0 {
		return nil
	}

	data := make([]map[string]interface{}, len(insights))
	for i, insight := range insights {
		// PostgREST requires all objects to have the same keys for bulk insert
		// Use nil for optional fields that are not set
		item := map[string]interface{}{
			"user_id":         insight.UserID,
			"insight_type":    insight.InsightType,
			"category":        insight.Category,
			"title":           insight.Title,
			"description":     insight.Description,
			"metric_value":    insight.MetricValue,
			"sample_size":     insight.SampleSize,
			"confidence":      insight.Confidence,
			"direction":       insight.Direction,
			"computed_at":     insight.ComputedAt,
			"valid_until":     insight.ValidUntil,
			"event_type_a_id": nil,
			"event_type_b_id": nil,
			"property_key":    nil,
			"p_value":         nil,
			"metadata":        map[string]interface{}{},
		}

		// Override with actual values if present
		if insight.EventTypeAID != nil {
			item["event_type_a_id"] = *insight.EventTypeAID
		}
		if insight.EventTypeBID != nil {
			item["event_type_b_id"] = *insight.EventTypeBID
		}
		if insight.PropertyKey != nil {
			item["property_key"] = *insight.PropertyKey
		}
		if insight.PValue != nil {
			item["p_value"] = *insight.PValue
		}
		if insight.Metadata != nil && len(insight.Metadata) > 0 {
			item["metadata"] = insight.Metadata
		}

		data[i] = item
	}

	_, err := r.client.Insert("insights", data)
	if err != nil {
		return fmt.Errorf("failed to bulk create insights: %w", err)
	}

	return nil
}

func (r *insightRepository) GetByUserID(ctx context.Context, userID string) ([]models.Insight, error) {
	// Use simple select without embedded resources to avoid schema cache issues
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
		"select":  "*",
		"order":   "computed_at.desc",
	}

	body, err := r.client.Query("insights", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get insights: %w", err)
	}

	var insights []models.Insight
	if err := json.Unmarshal(body, &insights); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return insights, nil
}

func (r *insightRepository) GetValidByUserID(ctx context.Context, userID string) ([]models.Insight, error) {
	now := time.Now().Format(time.RFC3339)
	// Use simple select without embedded resources to avoid schema cache issues
	query := map[string]interface{}{
		"user_id":     fmt.Sprintf("eq.%s", userID),
		"valid_until": fmt.Sprintf("gt.%s", now),
		"select":      "*",
		"order":       "computed_at.desc",
	}

	body, err := r.client.Query("insights", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get valid insights: %w", err)
	}

	var insights []models.Insight
	if err := json.Unmarshal(body, &insights); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return insights, nil
}

func (r *insightRepository) GetByType(ctx context.Context, userID string, insightType models.InsightType) ([]models.Insight, error) {
	now := time.Now().Format(time.RFC3339)
	// Use simple select without embedded resources to avoid schema cache issues
	query := map[string]interface{}{
		"user_id":      fmt.Sprintf("eq.%s", userID),
		"insight_type": fmt.Sprintf("eq.%s", insightType),
		"valid_until":  fmt.Sprintf("gt.%s", now),
		"select":       "*",
		"order":        "metric_value.desc",
	}

	body, err := r.client.Query("insights", query)
	if err != nil {
		return nil, fmt.Errorf("failed to get insights by type: %w", err)
	}

	var insights []models.Insight
	if err := json.Unmarshal(body, &insights); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return insights, nil
}

func (r *insightRepository) DeleteByUserID(ctx context.Context, userID string) error {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
	}

	if err := r.client.DeleteWhere("insights", query); err != nil {
		return fmt.Errorf("failed to delete insights: %w", err)
	}

	return nil
}

func (r *insightRepository) DeleteExpired(ctx context.Context, userID string) error {
	now := time.Now().Format(time.RFC3339)
	query := map[string]interface{}{
		"user_id":     fmt.Sprintf("eq.%s", userID),
		"valid_until": fmt.Sprintf("lt.%s", now),
	}

	if err := r.client.DeleteWhere("insights", query); err != nil {
		return fmt.Errorf("failed to delete expired insights: %w", err)
	}

	return nil
}

func (r *insightRepository) InvalidateAll(ctx context.Context, userID string) error {
	query := map[string]interface{}{
		"user_id": fmt.Sprintf("eq.%s", userID),
	}

	data := map[string]interface{}{
		"valid_until": time.Now().Add(-1 * time.Hour), // Set to past
	}

	_, err := r.client.UpdateWhere("insights", query, data)
	if err != nil {
		return fmt.Errorf("failed to invalidate insights: %w", err)
	}

	return nil
}
