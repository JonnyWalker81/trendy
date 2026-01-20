package handlers

import (
	"net/http"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/JonnyWalker81/trendy/backend/internal/models"
	"github.com/JonnyWalker81/trendy/backend/internal/service"
	"github.com/gin-gonic/gin"
)

type OnboardingHandler struct {
	onboardingService service.OnboardingService
}

// NewOnboardingHandler creates a new onboarding handler
func NewOnboardingHandler(onboardingService service.OnboardingService) *OnboardingHandler {
	return &OnboardingHandler{
		onboardingService: onboardingService,
	}
}

// GetOnboardingStatus handles GET /api/v1/users/onboarding
func (h *OnboardingHandler) GetOnboardingStatus(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	log := logger.Ctx(c.Request.Context())

	status, err := h.onboardingService.GetOnboardingStatus(c.Request.Context(), userID.(string))
	if err != nil {
		log.Error("failed to get onboarding status",
			logger.String("user_id", userID.(string)),
			logger.Err(err),
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get onboarding status"})
		return
	}

	c.JSON(http.StatusOK, status)
}

// UpdateOnboardingStatus handles PATCH /api/v1/users/onboarding
func (h *OnboardingHandler) UpdateOnboardingStatus(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	log := logger.Ctx(c.Request.Context())

	var req models.UpdateOnboardingStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	status, err := h.onboardingService.UpdateOnboardingStatus(c.Request.Context(), userID.(string), &req)
	if err != nil {
		log.Error("failed to update onboarding status",
			logger.String("user_id", userID.(string)),
			logger.Err(err),
		)
		// Check if it's a validation error (permission status validation)
		// Validation errors from service contain "invalid" in the message
		if err.Error() != "" && (err.Error()[:7] == "invalid") {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update onboarding status"})
		return
	}

	c.JSON(http.StatusOK, status)
}

// ResetOnboardingStatus handles DELETE /api/v1/users/onboarding
func (h *OnboardingHandler) ResetOnboardingStatus(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not authenticated"})
		return
	}

	log := logger.Ctx(c.Request.Context())

	status, err := h.onboardingService.ResetOnboardingStatus(c.Request.Context(), userID.(string))
	if err != nil {
		log.Error("failed to reset onboarding status",
			logger.String("user_id", userID.(string)),
			logger.Err(err),
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to reset onboarding status"})
		return
	}

	// Return 200 with the reset status (not 204) so iOS can see the new state
	c.JSON(http.StatusOK, status)
}
