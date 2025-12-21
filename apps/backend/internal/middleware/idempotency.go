package middleware

import (
	"bytes"
	"net/http"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/JonnyWalker81/trendy/backend/internal/repository"
	"github.com/gin-gonic/gin"
)

const (
	// IdempotencyKeyHeader is the HTTP header name for idempotency keys
	IdempotencyKeyHeader = "Idempotency-Key"
)

// idempotencyBodyWriter wraps gin.ResponseWriter to capture the response body for idempotency caching
type idempotencyBodyWriter struct {
	gin.ResponseWriter
	body *bytes.Buffer
}

func (w *idempotencyBodyWriter) Write(b []byte) (int, error) {
	w.body.Write(b)
	return w.ResponseWriter.Write(b)
}

// Idempotency middleware ensures exactly-once semantics for create operations.
// If an Idempotency-Key header is provided:
//   - Check if we've seen this key before for the same route and user
//   - If yes, return the cached response (replay)
//   - If no, process the request and cache the response for future replays
//
// The middleware only applies to mutating requests (POST, PUT, PATCH).
// GET and DELETE requests are ignored (GETs are naturally idempotent, DELETEs are handled differently).
func Idempotency(repo repository.IdempotencyRepository) gin.HandlerFunc {
	return func(c *gin.Context) {
		log := logger.FromContext(c.Request.Context())

		// Only apply to mutating requests
		method := c.Request.Method
		if method != http.MethodPost && method != http.MethodPut && method != http.MethodPatch {
			c.Next()
			return
		}

		// Check for idempotency key header
		key := c.GetHeader(IdempotencyKeyHeader)
		if key == "" {
			// No idempotency key - proceed without caching
			c.Next()
			return
		}

		// Get user ID from context (set by auth middleware)
		userID, exists := c.Get("user_id")
		if !exists {
			log.Warn("idempotency check failed: no user_id in context")
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required for idempotent requests"})
			c.Abort()
			return
		}

		userIDStr, ok := userID.(string)
		if !ok {
			log.Error("idempotency check failed: invalid user_id type")
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
			c.Abort()
			return
		}

		// Build the route identifier (method + path)
		route := method + " " + c.FullPath()

		log.Debug("checking idempotency",
			logger.String("key", key),
			logger.String("route", route),
			logger.String("user_id", userIDStr),
		)

		// Check for existing idempotency record
		existing, err := repo.Get(c.Request.Context(), key, route, userIDStr)
		if err != nil {
			log.Error("failed to check idempotency key",
				logger.Err(err),
				logger.String("key", key),
			)
			// On error, we proceed without idempotency to avoid blocking valid requests
			c.Next()
			return
		}

		// If we found an existing record, replay the cached response
		if existing != nil {
			log.Info("replaying idempotent response",
				logger.String("key", key),
				logger.String("route", route),
				logger.Int("status_code", existing.StatusCode),
			)

			c.Header("X-Idempotency-Replayed", "true")
			c.Data(existing.StatusCode, "application/json", existing.ResponseBody)
			c.Abort()
			return
		}

		// No existing record - capture the response for storage
		blw := &idempotencyBodyWriter{
			body:           bytes.NewBuffer(nil),
			ResponseWriter: c.Writer,
		}
		c.Writer = blw

		// Process the request
		c.Next()

		// Only cache successful responses (2xx)
		statusCode := c.Writer.Status()
		if statusCode >= 200 && statusCode < 300 {
			// Store the idempotency record
			if err := repo.Store(c.Request.Context(), key, route, userIDStr, blw.body.Bytes(), statusCode); err != nil {
				// Log but don't fail - the request already succeeded
				log.Warn("failed to store idempotency key",
					logger.Err(err),
					logger.String("key", key),
				)
			} else {
				log.Debug("stored idempotency key",
					logger.String("key", key),
					logger.String("route", route),
					logger.Int("status_code", statusCode),
				)
			}
		}
	}
}
