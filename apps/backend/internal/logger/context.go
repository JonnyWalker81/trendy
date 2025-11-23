package logger

import (
	"context"

	"github.com/google/uuid"
)

// Context keys for logging values
type contextKey string

const (
	requestIDKey contextKey = "request_id"
	userIDKey    contextKey = "user_id"
	loggerKey    contextKey = "logger"
)

// WithRequestID adds a request ID to the context
// If requestID is empty, a new UUID is generated
func WithRequestID(ctx context.Context, requestID string) context.Context {
	if requestID == "" {
		requestID = uuid.New().String()
	}
	return context.WithValue(ctx, requestIDKey, requestID)
}

// RequestIDFromContext extracts the request ID from context
func RequestIDFromContext(ctx context.Context) string {
	if id, ok := ctx.Value(requestIDKey).(string); ok {
		return id
	}
	return ""
}

// WithUserID adds a user ID to the context
func WithUserID(ctx context.Context, userID string) context.Context {
	return context.WithValue(ctx, userIDKey, userID)
}

// UserIDFromContext extracts the user ID from context
func UserIDFromContext(ctx context.Context) string {
	if id, ok := ctx.Value(userIDKey).(string); ok {
		return id
	}
	return ""
}

// WithLogger adds a logger to the context
func WithLogger(ctx context.Context, l Logger) context.Context {
	return context.WithValue(ctx, loggerKey, l)
}

// FromContext extracts the logger from context, or returns the default logger
func FromContext(ctx context.Context) Logger {
	if l, ok := ctx.Value(loggerKey).(Logger); ok {
		return l
	}
	return Default()
}

// extractContextFields extracts all logging-relevant fields from context
func extractContextFields(ctx context.Context) []Field {
	var fields []Field

	if requestID := RequestIDFromContext(ctx); requestID != "" {
		fields = append(fields, String("request_id", requestID))
	}

	if userID := UserIDFromContext(ctx); userID != "" {
		fields = append(fields, String("user_id", userID))
	}

	return fields
}

// Ctx returns a logger enriched with context values
// This is a convenience function for use in handlers/services
func Ctx(ctx context.Context) Logger {
	return FromContext(ctx).WithContext(ctx)
}
