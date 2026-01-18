package handlers

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/apierror"
	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/service"
	"github.com/gin-gonic/gin"
)

type EventHandler struct {
	eventService service.EventService
}

// NewEventHandler creates a new event handler
func NewEventHandler(eventService service.EventService) *EventHandler {
	return &EventHandler{
		eventService: eventService,
	}
}

// CreateEvent handles POST /api/v1/events
func (h *EventHandler) CreateEvent(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		requestID := apierror.GetRequestID(c)
		apierror.WriteProblem(c, apierror.NewUnauthorizedError(requestID))
		return
	}

	var req models.CreateEventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		requestID := apierror.GetRequestID(c)
		apierror.WriteProblem(c, apierror.NewBadRequestError(requestID, err.Error(), "Invalid request format"))
		return
	}

	event, wasCreated, err := h.eventService.CreateEvent(c.Request.Context(), userID.(string), &req)
	if err != nil {
		requestID := apierror.GetRequestID(c)

		// Handle UUIDv7 validation errors
		if errors.Is(err, service.ErrInvalidUUID) || errors.Is(err, service.ErrNotUUIDv7) {
			apierror.WriteProblem(c, apierror.NewInvalidUUIDError(requestID, "id", *req.ID))
			return
		}
		if errors.Is(err, service.ErrFutureTimestamp) {
			apierror.WriteProblem(c, apierror.NewFutureTimestampError(requestID, "id"))
			return
		}

		// Handle unique constraint violation (shouldn't happen with upsert, but just in case)
		if strings.Contains(err.Error(), "unique") || strings.Contains(err.Error(), "duplicate") ||
			strings.Contains(err.Error(), "23505") { // PostgreSQL unique violation code
			apierror.WriteProblem(c, apierror.NewConflictError(requestID, "An event with this ID already exists"))
			return
		}

		// Internal error
		apierror.WriteProblem(c, apierror.NewInternalError(requestID))
		return
	}

	// Return 201 for new creates, 200 for duplicates (idempotent)
	if wasCreated {
		c.JSON(http.StatusCreated, event)
	} else {
		c.JSON(http.StatusOK, event)
	}
}

// CreateEventsBatch handles POST /api/v1/events/batch
func (h *EventHandler) CreateEventsBatch(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	var req models.BatchCreateEventsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	response, err := h.eventService.CreateEventsBatch(c.Request.Context(), userID.(string), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Return 207 Multi-Status if there were partial failures
	if response.Failed > 0 && response.Success > 0 {
		c.JSON(http.StatusMultiStatus, response)
		return
	}

	// Return 400 if all failed
	if response.Failed > 0 && response.Success == 0 {
		c.JSON(http.StatusBadRequest, response)
		return
	}

	c.JSON(http.StatusCreated, response)
}

// GetEvents handles GET /api/v1/events
func (h *EventHandler) GetEvents(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	// Parse pagination parameters
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	events, err := h.eventService.GetUserEvents(c.Request.Context(), userID.(string), limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, events)
}

// ExportEvents handles GET /api/v1/events/export
func (h *EventHandler) ExportEvents(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	// Parse optional date range parameters
	var startDate, endDate *time.Time
	if startDateStr := c.Query("start_date"); startDateStr != "" {
		parsed, err := time.Parse(time.RFC3339, startDateStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid start_date format, use RFC3339"})
			return
		}
		startDate = &parsed
	}
	if endDateStr := c.Query("end_date"); endDateStr != "" {
		parsed, err := time.Parse(time.RFC3339, endDateStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid end_date format, use RFC3339"})
			return
		}
		endDate = &parsed
	}

	// Validate date range
	if startDate != nil && endDate != nil && startDate.After(*endDate) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "start_date must be before or equal to end_date"})
		return
	}

	// Parse optional event type IDs (comma-separated)
	var eventTypeIDs []string
	if eventTypeIDsStr := c.Query("event_type_ids"); eventTypeIDsStr != "" {
		eventTypeIDs = strings.Split(eventTypeIDsStr, ",")
		// Trim whitespace from each ID
		for i := range eventTypeIDs {
			eventTypeIDs[i] = strings.TrimSpace(eventTypeIDs[i])
		}
	}

	// Get events
	events, err := h.eventService.ExportEvents(c.Request.Context(), userID.(string), startDate, endDate, eventTypeIDs)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, events)
}

// GetEvent handles GET /api/v1/events/:id
func (h *EventHandler) GetEvent(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	eventID := c.Param("id")
	event, err := h.eventService.GetEvent(c.Request.Context(), userID.(string), eventID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "event not found"})
		return
	}

	c.JSON(http.StatusOK, event)
}

// UpdateEvent handles PUT /api/v1/events/:id
func (h *EventHandler) UpdateEvent(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	eventID := c.Param("id")

	var req models.UpdateEventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Debug logging for properties
	if req.Properties != nil {
		propCount := len(*req.Properties)
		propKeys := make([]string, 0, propCount)
		for k := range *req.Properties {
			propKeys = append(propKeys, k)
		}
		c.Request.Context().Value("logger") // placeholder - actual log below
		// Using fmt for now since logger might not be in context
		println("📝 UpdateEvent received", propCount, "properties:", strings.Join(propKeys, ", "))
	} else {
		println("📝 UpdateEvent received nil properties")
	}

	event, err := h.eventService.UpdateEvent(c.Request.Context(), userID.(string), eventID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Log what's being returned
	if event.Properties != nil {
		propCount := len(event.Properties)
		propKeys := make([]string, 0, propCount)
		for k := range event.Properties {
			propKeys = append(propKeys, k)
		}
		println("📝 UpdateEvent returning", propCount, "properties:", strings.Join(propKeys, ", "))
	}

	c.JSON(http.StatusOK, event)
}

// DeleteEvent handles DELETE /api/v1/events/:id
func (h *EventHandler) DeleteEvent(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	eventID := c.Param("id")

	if err := h.eventService.DeleteEvent(c.Request.Context(), userID.(string), eventID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}
