package handlers

import (
	"context"
	"fmt"
	"net/http"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/service"
	"github.com/gin-gonic/gin"
)

type GeofenceHandler struct {
	geofenceService service.GeofenceService
}

// NewGeofenceHandler creates a new geofence handler
func NewGeofenceHandler(geofenceService service.GeofenceService) *GeofenceHandler {
	return &GeofenceHandler{
		geofenceService: geofenceService,
	}
}

// CreateGeofence handles POST /api/v1/geofences
func (h *GeofenceHandler) CreateGeofence(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	userToken, _ := c.Get("user_token")

	var req models.CreateGeofenceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Log the received request for debugging
	log := logger.Ctx(c.Request.Context())
	log.Info("CreateGeofence request received",
		logger.String("name", req.Name),
		logger.String("is_active", fmt.Sprintf("%v", req.IsActive)),
		logger.String("notify_on_entry", fmt.Sprintf("%v", req.NotifyOnEntry)),
		logger.String("notify_on_exit", fmt.Sprintf("%v", req.NotifyOnExit)),
	)

	// Create context with user token for RLS
	ctx := context.WithValue(c.Request.Context(), "user_token", userToken)

	geofence, err := h.geofenceService.CreateGeofence(ctx, userID.(string), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, geofence)
}

// GetGeofences handles GET /api/v1/geofences
func (h *GeofenceHandler) GetGeofences(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	// Check if query parameter active=true is set
	activeOnly := c.Query("active") == "true"

	var geofences []models.Geofence
	var err error

	if activeOnly {
		geofences, err = h.geofenceService.GetActiveGeofences(c.Request.Context(), userID.(string))
	} else {
		geofences, err = h.geofenceService.GetUserGeofences(c.Request.Context(), userID.(string))
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, geofences)
}

// GetGeofence handles GET /api/v1/geofences/:id
func (h *GeofenceHandler) GetGeofence(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	geofenceID := c.Param("id")
	geofence, err := h.geofenceService.GetGeofence(c.Request.Context(), userID.(string), geofenceID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "geofence not found"})
		return
	}

	c.JSON(http.StatusOK, geofence)
}

// UpdateGeofence handles PUT /api/v1/geofences/:id
func (h *GeofenceHandler) UpdateGeofence(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	geofenceID := c.Param("id")

	var req models.UpdateGeofenceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	geofence, err := h.geofenceService.UpdateGeofence(c.Request.Context(), userID.(string), geofenceID, &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, geofence)
}

// DeleteGeofence handles DELETE /api/v1/geofences/:id
func (h *GeofenceHandler) DeleteGeofence(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	geofenceID := c.Param("id")
	if err := h.geofenceService.DeleteGeofence(c.Request.Context(), userID.(string), geofenceID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}
