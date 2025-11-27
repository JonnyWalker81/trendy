package handlers

import (
	"net/http"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/JonnyWalker81/trendy/backend/internal/service"
	"github.com/gin-gonic/gin"
)

// InsightsHandler handles insights-related HTTP requests
type InsightsHandler struct {
	intelligenceService service.IntelligenceService
}

// NewInsightsHandler creates a new insights handler
func NewInsightsHandler(intelligenceService service.IntelligenceService) *InsightsHandler {
	return &InsightsHandler{
		intelligenceService: intelligenceService,
	}
}

// GetInsights returns all insights for the authenticated user
// GET /api/v1/insights
func (h *InsightsHandler) GetInsights(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	log := logger.Ctx(c.Request.Context())

	insights, err := h.intelligenceService.GetInsights(c.Request.Context(), userID.(string))
	if err != nil {
		log.Error("failed to get insights", logger.Err(err), logger.String("user_id", userID.(string)))
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Also get weekly summary
	weeklySummary, err := h.intelligenceService.GetWeeklySummary(c.Request.Context(), userID.(string))
	if err != nil {
		log.Error("failed to get weekly summary", logger.Err(err), logger.String("user_id", userID.(string)))
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	insights.WeeklySummary = weeklySummary

	c.JSON(http.StatusOK, insights)
}

// GetCorrelations returns only correlation insights
// GET /api/v1/insights/correlations
func (h *InsightsHandler) GetCorrelations(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	insights, err := h.intelligenceService.GetInsights(c.Request.Context(), userID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"correlations": insights.Correlations,
		"computed_at":  insights.ComputedAt,
	})
}

// GetStreaks returns all streak data
// GET /api/v1/insights/streaks
func (h *InsightsHandler) GetStreaks(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	streaks, err := h.intelligenceService.GetStreaks(c.Request.Context(), userID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"streaks": streaks,
	})
}

// GetWeeklySummary returns week-over-week comparison
// GET /api/v1/insights/weekly-summary
func (h *InsightsHandler) GetWeeklySummary(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	summary, err := h.intelligenceService.GetWeeklySummary(c.Request.Context(), userID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"weekly_summary": summary,
	})
}

// RefreshInsights forces recomputation of insights
// POST /api/v1/insights/refresh
func (h *InsightsHandler) RefreshInsights(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	log := logger.Ctx(c.Request.Context())

	if err := h.intelligenceService.ComputeInsights(c.Request.Context(), userID.(string)); err != nil {
		log.Error("failed to compute insights", logger.Err(err), logger.String("user_id", userID.(string)))
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  "success",
		"message": "Insights refreshed successfully",
	})
}
