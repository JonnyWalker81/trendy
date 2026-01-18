package handlers

import (
	"net/http"

	"github.com/JonnyWalker81/trendy/backend/internal/apierror"
	"github.com/JonnyWalker81/trendy/backend/internal/service"
	"github.com/gin-gonic/gin"
)

type SyncHandler struct {
	syncService service.SyncService
}

func NewSyncHandler(syncService service.SyncService) *SyncHandler {
	return &SyncHandler{syncService: syncService}
}

func (h *SyncHandler) GetSyncStatus(c *gin.Context) {
	userID, exists := c.Get("user_id")
	if !exists {
		requestID := apierror.GetRequestID(c)
		apierror.WriteProblem(c, apierror.NewUnauthorizedError(requestID))
		return
	}

	status, err := h.syncService.GetSyncStatus(c.Request.Context(), userID.(string))
	if err != nil {
		requestID := apierror.GetRequestID(c)
		apierror.WriteProblem(c, apierror.NewInternalError(requestID))
		return
	}

	c.Header("Cache-Control", "private, max-age=30")
	c.JSON(http.StatusOK, status)
}
