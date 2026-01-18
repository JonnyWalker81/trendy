package apierror

import (
	"fmt"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

// ContentTypeProblemJSON is the MIME type for RFC 9457 Problem Details.
const ContentTypeProblemJSON = "application/problem+json"

// WriteProblem writes a ProblemDetails response to the gin context.
// It sets the correct Content-Type header and, if RetryAfter is set,
// also sets the Retry-After header.
func WriteProblem(c *gin.Context, problem *ProblemDetails) {
	c.Header("Content-Type", ContentTypeProblemJSON)

	// Set Retry-After header if specified (for 429 and 503 responses)
	if problem.RetryAfter != nil {
		c.Header("Retry-After", strconv.Itoa(*problem.RetryAfter))
	}

	c.JSON(problem.Status, problem)
}

// GetRequestID extracts the request ID from the gin context.
// Returns empty string if not found.
func GetRequestID(c *gin.Context) string {
	if requestID, exists := c.Get("request_id"); exists {
		if id, ok := requestID.(string); ok {
			return id
		}
	}
	return c.GetHeader("X-Request-ID")
}

// NewValidationError creates a 400 Bad Request response for validation failures.
// Multiple field errors can be included to report all validation issues at once.
func NewValidationError(requestID string, errors []FieldError) *ProblemDetails {
	return &ProblemDetails{
		Type:        TypeValidation,
		Title:       TitleValidation,
		Status:      http.StatusBadRequest,
		Detail:      "One or more fields failed validation",
		RequestID:   requestID,
		UserMessage: "Please check your input and try again",
		Errors:      errors,
	}
}

// NewNotFoundError creates a 404 Not Found response.
func NewNotFoundError(requestID, resource, id string) *ProblemDetails {
	return &ProblemDetails{
		Type:        TypeNotFound,
		Title:       TitleNotFound,
		Status:      http.StatusNotFound,
		Detail:      fmt.Sprintf("%s with ID '%s' was not found", resource, id),
		RequestID:   requestID,
		UserMessage: fmt.Sprintf("The requested %s could not be found", resource),
	}
}

// NewConflictError creates a 409 Conflict response.
// Note: Per 06-CONTEXT.md, duplicates should return 200 for idempotency.
// Use this for actual conflicts, not duplicate submissions.
func NewConflictError(requestID, detail string) *ProblemDetails {
	return &ProblemDetails{
		Type:        TypeConflict,
		Title:       TitleConflict,
		Status:      http.StatusConflict,
		Detail:      detail,
		RequestID:   requestID,
		UserMessage: "This action conflicts with existing data",
	}
}

// NewRateLimitError creates a 429 Too Many Requests response.
// retryAfter specifies seconds until the client should retry.
func NewRateLimitError(requestID string, retryAfter int) *ProblemDetails {
	return &ProblemDetails{
		Type:        TypeRateLimit,
		Title:       TitleRateLimit,
		Status:      http.StatusTooManyRequests,
		Detail:      fmt.Sprintf("Rate limit exceeded. Please retry after %d seconds", retryAfter),
		RequestID:   requestID,
		UserMessage: "Too many requests. Please wait before trying again.",
		RetryAfter:  &retryAfter,
	}
}

// NewInternalError creates a 500 Internal Server Error response.
// IMPORTANT: This intentionally hides internal error details from the client.
// The actual error should be logged server-side for debugging.
func NewInternalError(requestID string) *ProblemDetails {
	return &ProblemDetails{
		Type:        TypeInternal,
		Title:       TitleInternal,
		Status:      http.StatusInternalServerError,
		Detail:      "An unexpected error occurred",
		RequestID:   requestID,
		UserMessage: "Something went wrong. Please try again later.",
	}
}

// NewBadRequestError creates a 400 Bad Request response for malformed requests.
func NewBadRequestError(requestID, detail, userMessage string) *ProblemDetails {
	return &ProblemDetails{
		Type:        TypeBadRequest,
		Title:       TitleBadRequest,
		Status:      http.StatusBadRequest,
		Detail:      detail,
		RequestID:   requestID,
		UserMessage: userMessage,
	}
}

// NewUnauthorizedError creates a 401 Unauthorized response.
func NewUnauthorizedError(requestID string) *ProblemDetails {
	return &ProblemDetails{
		Type:        TypeUnauthorized,
		Title:       TitleUnauthorized,
		Status:      http.StatusUnauthorized,
		Detail:      "Authentication is required to access this resource",
		RequestID:   requestID,
		UserMessage: "Please sign in to continue",
		Action:      "authenticate",
	}
}

// NewForbiddenError creates a 403 Forbidden response.
func NewForbiddenError(requestID string) *ProblemDetails {
	return &ProblemDetails{
		Type:        TypeForbidden,
		Title:       TitleForbidden,
		Status:      http.StatusForbidden,
		Detail:      "You do not have permission to access this resource",
		RequestID:   requestID,
		UserMessage: "You don't have permission to perform this action",
	}
}

// NewInvalidUUIDError creates a 400 Bad Request response for invalid UUID format.
func NewInvalidUUIDError(requestID, field, value string) *ProblemDetails {
	return &ProblemDetails{
		Type:        TypeInvalidUUID,
		Title:       TitleInvalidUUID,
		Status:      http.StatusBadRequest,
		Detail:      fmt.Sprintf("Invalid UUID format for field '%s': '%s'", field, value),
		RequestID:   requestID,
		UserMessage: "Invalid identifier format",
		Errors: []FieldError{
			{Field: field, Message: "must be a valid UUID", Code: "invalid_uuid"},
		},
	}
}

// NewFutureTimestampError creates a 400 Bad Request response for timestamps too far in the future.
func NewFutureTimestampError(requestID, field string) *ProblemDetails {
	return &ProblemDetails{
		Type:        TypeFutureTimestamp,
		Title:       TitleFutureTimestamp,
		Status:      http.StatusBadRequest,
		Detail:      fmt.Sprintf("Field '%s' contains a timestamp more than 1 minute in the future", field),
		RequestID:   requestID,
		UserMessage: "The timestamp is too far in the future",
		Errors: []FieldError{
			{Field: field, Message: "timestamp cannot be more than 1 minute in the future", Code: "future_timestamp"},
		},
	}
}

// NewServiceUnavailableError creates a 503 Service Unavailable response.
// retryAfter specifies seconds until the client should retry.
func NewServiceUnavailableError(requestID string, retryAfter int) *ProblemDetails {
	return &ProblemDetails{
		Type:        TypeInternal,
		Title:       "Service Unavailable",
		Status:      http.StatusServiceUnavailable,
		Detail:      "The service is temporarily unavailable",
		RequestID:   requestID,
		UserMessage: "Service is temporarily unavailable. Please try again later.",
		RetryAfter:  &retryAfter,
	}
}
