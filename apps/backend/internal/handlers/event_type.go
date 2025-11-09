package handlers

import (
	"context"
	"net/http"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/service"
	"github.com/gin-gonic/gin"
)

type EventTypeHandler struct {
	eventTypeService service.EventTypeService
}

// NewEventTypeHandler creates a new event type handler
func NewEventTypeHandler(eventTypeService service.EventTypeService) *EventTypeHandler {
	return &EventTypeHandler{
		eventTypeService: eventTypeService,
	}
}

// CreateEventType handles POST /api/v1/event-types
func (h *EventTypeHandler) CreateEventType(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	userToken, _ := c.Get("user_token")

	var req models.CreateEventTypeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create context with user token for RLS
	ctx := context.WithValue(c.Request.Context(), "user_token", userToken)

	eventType, err := h.eventTypeService.CreateEventType(ctx, userID.(string), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, eventType)
}

// GetEventTypes handles GET /api/v1/event-types
func (h *EventTypeHandler) GetEventTypes(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	eventTypes, err := h.eventTypeService.GetUserEventTypes(c.Request.Context(), userID.(string))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, eventTypes)
}

// GetEventType handles GET /api/v1/event-types/:id
func (h *EventTypeHandler) GetEventType(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	eventTypeID := c.Param("id")
	eventType, err := h.eventTypeService.GetEventType(c.Request.Context(), userID.(string), eventTypeID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "event type not found"})
		return
	}

	c.JSON(http.StatusOK, eventType)
}

// UpdateEventType handles PUT /api/v1/event-types/:id
func (h *EventTypeHandler) UpdateEventType(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	eventTypeID := c.Param("id")

	var req models.UpdateEventTypeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	eventType, err := h.eventTypeService.UpdateEventType(c.Request.Context(), userID.(string), eventTypeID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, eventType)
}

// DeleteEventType handles DELETE /api/v1/event-types/:id
func (h *EventTypeHandler) DeleteEventType(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	eventTypeID := c.Param("id")

	if err := h.eventTypeService.DeleteEventType(c.Request.Context(), userID.(string), eventTypeID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}
