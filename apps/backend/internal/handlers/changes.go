package handlers

import (
	"net/http"
	"strconv"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
	"github.com/gin-gonic/gin"
)

type ChangesHandler struct {
	changeLogRepo repository.ChangeLogRepository
}

// NewChangesHandler creates a new changes handler
func NewChangesHandler(changeLogRepo repository.ChangeLogRepository) *ChangesHandler {
	return &ChangesHandler{
		changeLogRepo: changeLogRepo,
	}
}

// GetLatestCursor handles GET /api/v1/changes/latest-cursor
// Returns the maximum change_log ID for the user, useful after bootstrap to skip stale entries
func (h *ChangesHandler) GetLatestCursor(c *gin.Context) {
	log := logger.FromContext(c.Request.Context())

	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	cursor, err := h.changeLogRepo.GetLatestCursor(c.Request.Context(), userID.(string))
	if err != nil {
		log.Error("failed to get latest cursor",
			logger.Err(err),
			logger.String("user_id", userID.(string)),
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get latest cursor"})
		return
	}

	log.Debug("returning latest cursor",
		logger.String("user_id", userID.(string)),
		logger.Int64("cursor", cursor),
	)

	c.JSON(http.StatusOK, gin.H{"cursor": cursor})
}

// GetChanges handles GET /api/v1/changes
// Query params:
//   - since: cursor (default 0)
//   - limit: max results (default 100, max 500)
func (h *ChangesHandler) GetChanges(c *gin.Context) {
	log := logger.FromContext(c.Request.Context())

	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	// Parse cursor from query param
	var cursor int64 = 0
	if sinceStr := c.Query("since"); sinceStr != "" {
		parsed, err := strconv.ParseInt(sinceStr, 10, 64)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid 'since' parameter: must be an integer"})
			return
		}
		cursor = parsed
	}

	// Parse limit from query param
	limit := 100
	if limitStr := c.Query("limit"); limitStr != "" {
		parsed, err := strconv.Atoi(limitStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid 'limit' parameter: must be an integer"})
			return
		}
		if parsed > 0 && parsed <= 500 {
			limit = parsed
		}
	}

	log.Debug("fetching changes",
		logger.String("user_id", userID.(string)),
		logger.Int64("since", cursor),
		logger.Int("limit", limit),
	)

	// Fetch changes from repository
	response, err := h.changeLogRepo.GetSince(c.Request.Context(), userID.(string), cursor, limit)
	if err != nil {
		log.Error("failed to fetch changes",
			logger.Err(err),
			logger.String("user_id", userID.(string)),
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch changes"})
		return
	}

	log.Debug("fetched changes",
		logger.Int("count", len(response.Changes)),
		logger.Int64("next_cursor", response.NextCursor),
		logger.Bool("has_more", response.HasMore),
	)

	c.JSON(http.StatusOK, response)
}
