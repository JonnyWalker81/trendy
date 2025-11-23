package middleware

import (
	"bytes"
	"io"
	"time"

	"github.com/JonnyWalker81/trendy/backend/internal/logger"
	"github.com/gin-gonic/gin"
)

// RequestIDHeader is the header name for request ID propagation
const RequestIDHeader = "X-Request-ID"

// Logger middleware for structured HTTP request logging
func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		// Generate or extract request ID
		requestID := c.GetHeader(RequestIDHeader)
		if requestID == "" {
			requestID = logger.RequestIDFromContext(c.Request.Context())
		}

		// Add request ID to context
		ctx := logger.WithRequestID(c.Request.Context(), requestID)
		c.Request = c.Request.WithContext(ctx)

		// Set request ID in response header for correlation
		c.Header(RequestIDHeader, logger.RequestIDFromContext(ctx))

		// Store request ID in Gin context for other middleware/handlers
		c.Set("request_id", logger.RequestIDFromContext(ctx))

		// Create logger with request context
		log := logger.Default().With(
			logger.String("request_id", logger.RequestIDFromContext(ctx)),
			logger.String("method", c.Request.Method),
			logger.String("path", c.Request.URL.Path),
			logger.String("client_ip", c.ClientIP()),
		)

		// Store logger in context for handlers
		ctx = logger.WithLogger(ctx, log)
		c.Request = c.Request.WithContext(ctx)

		// Log request start at debug level
		log.Debug("request started",
			logger.String("user_agent", c.Request.UserAgent()),
			logger.String("query", c.Request.URL.RawQuery),
		)

		// Process request
		c.Next()

		// Calculate duration
		duration := time.Since(start)
		statusCode := c.Writer.Status()

		// Build response log fields
		fields := []logger.Field{
			logger.Int("status", statusCode),
			logger.Duration("duration", duration),
			logger.Int("response_size", c.Writer.Size()),
		}

		// Add user_id if authenticated
		if userID, exists := c.Get("user_id"); exists {
			fields = append(fields, logger.String("user_id", userID.(string)))
		}

		// Add error if present
		if len(c.Errors) > 0 {
			fields = append(fields, logger.String("errors", c.Errors.String()))
		}

		// Log at appropriate level based on status code
		switch {
		case statusCode >= 500:
			log.Error("request completed", fields...)
		case statusCode >= 400:
			log.Warn("request completed", fields...)
		default:
			log.Info("request completed", fields...)
		}
	}
}

// bodyLogWriter wraps gin.ResponseWriter to capture response body
type bodyLogWriter struct {
	gin.ResponseWriter
	body *bytes.Buffer
}

func (w bodyLogWriter) Write(b []byte) (int, error) {
	w.body.Write(b)
	return w.ResponseWriter.Write(b)
}

// LoggerWithBodies middleware that also logs request/response bodies
// WARNING: Use only in development - security and performance impact
func LoggerWithBodies() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		// Generate or extract request ID
		requestID := c.GetHeader(RequestIDHeader)
		ctx := logger.WithRequestID(c.Request.Context(), requestID)
		c.Request = c.Request.WithContext(ctx)
		c.Header(RequestIDHeader, logger.RequestIDFromContext(ctx))
		c.Set("request_id", logger.RequestIDFromContext(ctx))

		// Create logger with request context
		log := logger.Default().With(
			logger.String("request_id", logger.RequestIDFromContext(ctx)),
			logger.String("method", c.Request.Method),
			logger.String("path", c.Request.URL.Path),
		)

		// Read and restore request body
		var requestBody []byte
		if c.Request.Body != nil {
			requestBody, _ = io.ReadAll(c.Request.Body)
			c.Request.Body = io.NopCloser(bytes.NewBuffer(requestBody))
		}

		// Capture response body
		blw := &bodyLogWriter{body: bytes.NewBufferString(""), ResponseWriter: c.Writer}
		c.Writer = blw

		// Log request with body
		log.Debug("request started",
			logger.String("request_body", truncateBody(string(requestBody))),
		)

		// Store logger in context
		ctx = logger.WithLogger(ctx, log)
		c.Request = c.Request.WithContext(ctx)

		// Process request
		c.Next()

		// Log response with body
		duration := time.Since(start)
		statusCode := c.Writer.Status()

		log.Debug("request completed",
			logger.Int("status", statusCode),
			logger.Duration("duration", duration),
			logger.String("response_body", truncateBody(blw.body.String())),
		)
	}
}

// truncateBody limits body size for logging to prevent huge log entries
func truncateBody(body string) string {
	const maxLen = 1000
	if len(body) > maxLen {
		return body[:maxLen] + "... [truncated]"
	}
	return body
}
