package handlers

import (
	"context"
	"net/http"

	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/service"
	"github.com/gin-gonic/gin"
)

type PropertyDefinitionHandler struct {
	propertyDefService service.PropertyDefinitionService
}

// NewPropertyDefinitionHandler creates a new property definition handler
func NewPropertyDefinitionHandler(propertyDefService service.PropertyDefinitionService) *PropertyDefinitionHandler {
	return &PropertyDefinitionHandler{
		propertyDefService: propertyDefService,
	}
}

// CreatePropertyDefinition handles POST /api/v1/event-types/:id/properties
func (h *PropertyDefinitionHandler) CreatePropertyDefinition(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	userToken, _ := c.Get("user_token")
	eventTypeID := c.Param("id")

	var req models.CreatePropertyDefinitionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Set event_type_id from URL parameter
	req.EventTypeID = eventTypeID

	// Create context with user token for RLS
	ctx := context.WithValue(c.Request.Context(), "user_token", userToken)

	propertyDef, err := h.propertyDefService.CreatePropertyDefinition(ctx, userID.(string), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, propertyDef)
}

// GetPropertyDefinitionsByEventType handles GET /api/v1/event-types/:id/properties
func (h *PropertyDefinitionHandler) GetPropertyDefinitionsByEventType(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	eventTypeID := c.Param("id")

	propertyDefs, err := h.propertyDefService.GetPropertyDefinitionsByEventType(c.Request.Context(), userID.(string), eventTypeID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, propertyDefs)
}

// GetPropertyDefinition handles GET /api/v1/property-definitions/:id
func (h *PropertyDefinitionHandler) GetPropertyDefinition(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	propertyDefID := c.Param("id")
	propertyDef, err := h.propertyDefService.GetPropertyDefinition(c.Request.Context(), userID.(string), propertyDefID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "property definition not found"})
		return
	}

	c.JSON(http.StatusOK, propertyDef)
}

// UpdatePropertyDefinition handles PUT /api/v1/property-definitions/:id
func (h *PropertyDefinitionHandler) UpdatePropertyDefinition(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	propertyDefID := c.Param("id")

	var req models.UpdatePropertyDefinitionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	propertyDef, err := h.propertyDefService.UpdatePropertyDefinition(c.Request.Context(), userID.(string), propertyDefID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, propertyDef)
}

// DeletePropertyDefinition handles DELETE /api/v1/property-definitions/:id
func (h *PropertyDefinitionHandler) DeletePropertyDefinition(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	propertyDefID := c.Param("id")

	if err := h.propertyDefService.DeletePropertyDefinition(c.Request.Context(), userID.(string), propertyDefID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}
