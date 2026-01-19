package models

import "time"

// InsightType represents the type of insight
type InsightType string

const (
	InsightTypeCorrelation InsightType = "correlation"
	InsightTypePattern     InsightType = "pattern"
	InsightTypeStreak      InsightType = "streak"
	InsightTypeSummary     InsightType = "summary"
)

// InsightCategory represents the category of insight
type InsightCategory string

const (
	InsightCategoryCrossEvent InsightCategory = "cross_event"
	InsightCategoryProperty   InsightCategory = "property"
	InsightCategoryTimeOfDay  InsightCategory = "time_of_day"
	InsightCategoryDayOfWeek  InsightCategory = "day_of_week"
	InsightCategoryWeekly     InsightCategory = "weekly"
	InsightCategoryStreak     InsightCategory = "streak"
)

// Confidence represents the confidence level of an insight
type Confidence string

const (
	ConfidenceHigh   Confidence = "high"
	ConfidenceMedium Confidence = "medium"
	ConfidenceLow    Confidence = "low"
)

// Direction represents the direction of a correlation or trend
type Direction string

const (
	DirectionPositive Direction = "positive"
	DirectionNegative Direction = "negative"
	DirectionNeutral  Direction = "neutral"
)

// StreakType represents whether a streak is current or historical
type StreakType string

const (
	StreakTypeCurrent StreakType = "current"
	StreakTypeLongest StreakType = "longest"
)

// Insight represents a computed insight
type Insight struct {
	ID           string                 `json:"id"`
	UserID       string                 `json:"user_id"`
	InsightType  InsightType            `json:"insight_type"`
	Category     InsightCategory        `json:"category"`
	Title        string                 `json:"title"`
	Description  string                 `json:"description"`
	EventTypeAID *string                `json:"event_type_a_id,omitempty"`
	EventTypeBID *string                `json:"event_type_b_id,omitempty"`
	PropertyKey  *string                `json:"property_key,omitempty"`
	MetricValue  float64                `json:"metric_value"`
	PValue       *float64               `json:"p_value,omitempty"`
	SampleSize   int                    `json:"sample_size"`
	Confidence   Confidence             `json:"confidence"`
	Direction    Direction              `json:"direction"`
	Metadata     map[string]interface{} `json:"metadata,omitempty"`
	ComputedAt   time.Time              `json:"computed_at"`
	ValidUntil   time.Time              `json:"valid_until"`
	CreatedAt    time.Time              `json:"created_at"`
	// Expanded relations (populated on fetch)
	EventTypeA *EventType `json:"event_type_a,omitempty"`
	EventTypeB *EventType `json:"event_type_b,omitempty"`
}

// DailyAggregate represents aggregated event data for a single day
type DailyAggregate struct {
	ID                   string             `json:"id"`
	UserID               string             `json:"user_id"`
	Date                 time.Time          `json:"date"`
	EventTypeID          string             `json:"event_type_id"`
	EventCount           int                `json:"event_count"`
	TotalDurationSeconds *float64           `json:"total_duration_seconds,omitempty"`
	AvgNumericValue      *float64           `json:"avg_numeric_value,omitempty"`
	PropertyAggregates   map[string]PropAgg `json:"property_aggregates,omitempty"`
	CreatedAt            time.Time          `json:"created_at"`
	UpdatedAt            time.Time          `json:"updated_at"`
	// Expanded relations (populated on fetch)
	EventType *EventType `json:"event_type,omitempty"`
}

// PropAgg holds aggregated values for a single property
type PropAgg struct {
	Sum   float64 `json:"sum"`
	Avg   float64 `json:"avg"`
	Min   float64 `json:"min"`
	Max   float64 `json:"max"`
	Count int     `json:"count"`
}

// Streak represents a consecutive day sequence for an event type
type Streak struct {
	ID          string     `json:"id"`
	UserID      string     `json:"user_id"`
	EventTypeID string     `json:"event_type_id"`
	StreakType  StreakType `json:"streak_type"`
	StartDate   time.Time  `json:"start_date"`
	EndDate     *time.Time `json:"end_date,omitempty"`
	Length      int        `json:"length"`
	IsActive    bool       `json:"is_active"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	// Expanded relations (populated on fetch)
	EventType *EventType `json:"event_type,omitempty"`
}

// WeeklySummary represents week-over-week comparison for an event type
type WeeklySummary struct {
	EventTypeID    string  `json:"event_type_id"`
	EventTypeName  string  `json:"event_type_name"`
	EventTypeColor string  `json:"event_type_color"`
	EventTypeIcon  string  `json:"event_type_icon"`
	ThisWeekCount  int     `json:"this_week_count"`
	LastWeekCount  int     `json:"last_week_count"`
	ChangePercent  float64 `json:"change_percent"`
	Direction      string  `json:"direction"` // "up", "down", "same"
}

// TimePattern represents time-based pattern analysis
type TimePattern struct {
	PatternType  string    `json:"pattern_type"` // "hour_distribution", "day_of_week"
	Distribution []float64 `json:"distribution"` // Percentages for each bucket
	PeakValue    int       `json:"peak_value"`   // Index of peak (hour 0-23 or day 0-6)
	PeakLabel    string    `json:"peak_label"`   // Human readable label ("Tuesday", "8 AM")
	PeakPercent  float64   `json:"peak_percent"` // Percentage at peak
	Consistency  float64   `json:"consistency"`  // 0-1 score (1 = very consistent)
}

// CorrelationResult holds the result of a correlation calculation
type CorrelationResult struct {
	EventTypeAID   string     `json:"event_type_a_id"`
	EventTypeBID   string     `json:"event_type_b_id"`
	Coefficient    float64    `json:"coefficient"` // Pearson r value (-1 to 1)
	PValue         float64    `json:"p_value"`     // Statistical significance
	SampleSize     int        `json:"sample_size"` // Number of overlapping days
	Confidence     Confidence `json:"confidence"`  // high/medium/low
	Direction      Direction  `json:"direction"`   // positive/negative/neutral
	LagDays        int        `json:"lag_days"`    // 0 = same day, 1 = next day correlation
	EventTypeAName string     `json:"event_type_a_name,omitempty"`
	EventTypeBName string     `json:"event_type_b_name,omitempty"`
}

// InsightsResponse is the API response containing all insights
type InsightsResponse struct {
	Correlations   []Insight       `json:"correlations"`
	Patterns       []Insight       `json:"patterns"`
	Streaks        []Insight       `json:"streaks"`
	WeeklySummary  []WeeklySummary `json:"weekly_summary"`
	ComputedAt     time.Time       `json:"computed_at"`
	DataSufficient bool            `json:"data_sufficient"`
	MinDaysNeeded  int             `json:"min_days_needed,omitempty"`
	TotalDays      int             `json:"total_days"`
}

// InsightMetadata holds additional context for an insight
type InsightMetadata struct {
	// For correlations
	Coefficient float64 `json:"coefficient,omitempty"`
	LagDays     int     `json:"lag_days,omitempty"`

	// For time patterns
	Distribution []float64 `json:"distribution,omitempty"`
	PeakValue    int       `json:"peak_value,omitempty"`
	PeakLabel    string    `json:"peak_label,omitempty"`
	Consistency  float64   `json:"consistency,omitempty"`

	// For streaks
	IsLongest     bool       `json:"is_longest,omitempty"`
	PreviousBest  int        `json:"previous_best,omitempty"`
	StreakEndDate *time.Time `json:"streak_end_date,omitempty"`
}
